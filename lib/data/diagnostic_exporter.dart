import 'dart:convert';

import '../domain/models.dart';
import '../domain/run_diagnostics.dart';

/// Export explicite ; les positions nécessitent une option distincte.
class DiagnosticExporter {
  String export(
    RunSession session, {
    required List<Map<String, dynamic>> diagnostics,
    bool includePositions = false,
  }) {
    final detailed = session.diagnosticsMode == DiagnosticsMode.diagnostic;
    final events = detailed ? diagnostics : const <Map<String, dynamic>>[];
    return const JsonEncoder.withIndent('  ').convert(
      _serializable({
        'format': 'mapfollow-diagnostics',
        'version': 2,
        'positionsIncluded': includePositions && detailed,
        'batteryScope': 'wholeDevice',
        'session': session.toJson(),
        'summary': _summary(session, events),
        if (!detailed)
          'detailAvailability':
              'GPS details were not recorded. Battery and session metadata only.',
        if (includePositions && detailed)
          'segments': session.segments
              .map((s) => s.map((fix) => fix.toJson()).toList())
              .toList(),
        'diagnostics': events,
      }, includePositions: includePositions && detailed),
    );
  }

  Map<String, dynamic> _summary(
    RunSession run,
    List<Map<String, dynamic>> events,
  ) {
    final locations = events.where((e) => e['event'] == 'location').toList();
    final timestamps = <DateTime>[];
    final receptionTimes = <DateTime>[];
    final accuracies = <double>[];
    final reasons = <String, int>{};
    for (final e in locations) {
      final raw = e['raw'];
      if (raw is Map) {
        final time = DateTime.tryParse(raw['timestamp']?.toString() ?? '');
        if (time != null) timestamps.add(time);
        final accuracy = BatterySample.finite(raw['accuracy']);
        if (accuracy != null && accuracy >= 0) accuracies.add(accuracy);
      }
      final received = DateTime.tryParse(e['receivedAt']?.toString() ?? '');
      if (received != null) receptionTimes.add(received);
      final reason = e['decision']?.toString() ?? 'unknown';
      reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }
    final battery = run.batterySamples;
    final first = battery.isEmpty ? null : battery.first.levelPercent;
    final last = battery.isEmpty ? null : battery.last.levelPercent;
    return {
      'requestedLocationIntervalMillis': run.requestedLocationIntervalMillis,
      'locationFilterVersion': run.locationFilterVersion ?? 'unknown',
      'receivedFixCount': locations.length,
      'acceptedFixCount': locations.where((e) => e['accepted'] == true).length,
      'recordedFixCount': locations.where((e) => e['recorded'] == true).length,
      'filterDecisions': reasons,
      'measurementCadenceSeconds': _cadence(timestamps),
      'receptionCadenceSeconds': _cadence(receptionTimes),
      'accuracyMeters': _distribution(accuracies),
      'segmentCount': run.segments.where((s) => s.isNotEmpty).length,
      'batteryDropPercentagePoints': first == null || last == null
          ? null
          : first - last,
      'chargingObserved': battery.any((s) => s.charging == true),
      'batteryInterrupted': run.batteryInterrupted,
      'batteryMissingMeasurements':
          first == null ||
          last == null ||
          battery.any((s) => s.levelPercent == null),
    };
  }

  Map<String, dynamic> _cadence(List<DateTime> times) {
    final intervals = <double>[];
    var nonMonotonic = 0;
    var gaps = 0;
    for (var i = 1; i < times.length; i++) {
      final seconds = times[i].difference(times[i - 1]).inMicroseconds / 1e6;
      if (seconds <= 0) {
        nonMonotonic++;
      } else if (seconds > 10) {
        gaps++;
      } else {
        intervals.add(seconds);
      }
    }
    return {
      ..._distribution(intervals),
      'gapsOver10Seconds': gaps,
      'nonMonotonicCount': nonMonotonic,
    };
  }

  Map<String, dynamic> _distribution(List<double> values) {
    values.sort();
    double? percentile(double fraction) {
      if (values.isEmpty) return null;
      final index = (values.length - 1) * fraction;
      final low = index.floor();
      final high = index.ceil();
      return values[low] + (values[high] - values[low]) * (index - low);
    }

    return {
      'count': values.length,
      'median': percentile(.5),
      'p95': percentile(.95),
    };
  }

  Object? _serializable(Object? value, {required bool includePositions}) {
    if (value is num && !value.isFinite) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is List) {
      return value
          .map((v) => _serializable(v, includePositions: includePositions))
          .toList();
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!const {
                'gnss',
                'constellations',
                'satelliteCount',
                'satellites',
              }.contains(entry.key.toString()) &&
              (includePositions ||
                  !const {
                    'point',
                    'lat',
                    'lon',
                    'latitude',
                    'longitude',
                    'segments',
                  }.contains(entry.key.toString())))
            entry.key.toString(): _serializable(
              entry.value,
              includePositions: includePositions,
            ),
      };
    }
    return value;
  }
}
