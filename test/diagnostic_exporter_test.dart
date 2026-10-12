import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/diagnostic_exporter.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';

void main() {
  final now = DateTime.utc(2026);
  test(
    'native cadence groups live streams without crossing a reboot and exports no coordinates',
    () {
      final run = RunSession(
        id: 'synthetic-clock',
        startedAt: now,
        simulated: false,
        diagnosticsMode: DiagnosticsMode.diagnostic,
      );
      final data =
          jsonDecode(
                DiagnosticExporter().export(
                  run,
                  diagnostics: [
                    for (final (stream, measured) in [
                      ('first', 90000000000),
                      ('first', 90500000000),
                      ('after-reboot', 1000000000),
                      ('after-reboot', 1500000000),
                    ])
                      {
                        'event': 'location',
                        'raw': {
                          'locationStreamId': stream,
                          'elapsedRealtimeNanos': measured,
                          'receivedElapsedRealtimeNanos': measured + 100000000,
                          'point': {'lat': 0.0, 'lon': 0.0},
                        },
                      },
                  ],
                ),
              )
              as Map;
      final summary = data['summary'];
      expect(summary['monotonicMeasurementCadenceSeconds']['count'], 2);
      expect(summary['monotonicMeasurementCadenceSeconds']['median'], .5);
      expect(
        summary['monotonicMeasurementCadenceSeconds']['nonMonotonicCount'],
        0,
      );
      expect(summary['nativeDeliveryAgeMillis']['median'], 100);
      expect(data['positionsIncluded'], false);
      expect(
        (data['diagnostics'] as List).every(
          (event) => !event['raw'].containsKey('point'),
        ),
        true,
      );
    },
  );
  RunSession session(DiagnosticsMode mode) => RunSession(
    id: 'synthetic-run',
    startedAt: now,
    simulated: true,
    diagnosticsMode: mode,
    batterySamples: [
      BatterySample(timestamp: now, levelPercent: 100, event: 'start'),
    ],
    segments: [
      [LocationFix(point: const RoutePoint(0, 0), timestamp: now, accuracy: 5)],
    ],
  );
  final diagnostics = <Map<String, dynamic>>[
    {
      'type': 'gps',
      'raw': {
        'point': {'lat': 0.0, 'lon': 0.0},
        'speed': null,
        'accuracy': 5.0,
      },
    },
    {'type': 'filter', 'reason': 'jump', 'innovation': double.infinity},
    {
      'gnss': {'seen': 10},
      'constellations': [
        {'seen': 10, 'used': 6},
      ],
    },
  ];

  test(
    'export distinguishes initial and observed filter versions after recovery',
    () {
      final run = RunSession(
        id: 'synthetic-upgrade',
        startedAt: now,
        simulated: false,
        diagnosticsMode: DiagnosticsMode.diagnostic,
        locationFilterVersion: 'kalman-cadence-2',
      );
      final data =
          jsonDecode(
                DiagnosticExporter().export(
                  run,
                  diagnostics: [
                    {'event': 'location', 'decision': 'filtered'},
                    {
                      'event': 'location',
                      'decision': 'filtered',
                      'filterVersion': 'kalman-passive-3',
                    },
                  ],
                ),
              )
              as Map;
      expect(data['summary']['locationFilterVersion'], 'kalman-cadence-2');
      expect(data['summary']['observedFilterVersions'], {
        'kalman-cadence-2': 1,
        'kalman-passive-3': 1,
      });
    },
  );

  test('normal export contains battery metadata and no position payload', () {
    final json =
        jsonDecode(
              DiagnosticExporter().export(
                session(DiagnosticsMode.normal),
                diagnostics: diagnostics,
              ),
            )
            as Map;
    expect(json['batteryScope'], 'wholeDevice');
    expect(json.containsKey('segments'), isFalse);
    expect(json['diagnostics'], isEmpty);
    expect((json['session'] as Map)['batterySamples'], isNotEmpty);
  });

  test(
    'explicit diagnostic export preserves raw fixes without GNSS counts',
    () {
      final json =
          jsonDecode(
                DiagnosticExporter().export(
                  session(DiagnosticsMode.diagnostic),
                  diagnostics: diagnostics,
                  includePositions: true,
                ),
              )
              as Map;
      expect(json['segments'], isNotEmpty);
      final events = json['diagnostics'] as List;
      expect((events.first as Map)['raw'], contains('point'));
      expect((events[1] as Map)['innovation'], isNull);
      expect(events.last, isEmpty);
      expect((events.first as Map)['raw']['speed'], isNull);
    },
  );
  test(
    'default detailed export removes coordinates recursively but retains analysis metrics',
    () {
      final events = [
        for (var i = 0; i < 3; i++)
          <String, dynamic>{
            'event': 'location',
            'receivedAt': now
                .add(Duration(milliseconds: i * 500))
                .toIso8601String(),
            'raw': {
              'point': {'lat': 1.0, 'lon': 2.0},
              'timestamp': now
                  .add(Duration(milliseconds: i * 500))
                  .toIso8601String(),
              'accuracy': 3.0,
              'speed': 2.0,
            },
            'processed': {
              'point': {'lat': 1.0, 'lon': 2.0},
              'speed': 2.0,
            },
            'decision': i == 2 ? 'speed_inconsistent' : 'filtered',
            'accepted': i != 2,
            'recorded': i != 2,
          },
      ];
      final content = DiagnosticExporter().export(
        session(DiagnosticsMode.diagnostic),
        diagnostics: events,
      );
      final data = jsonDecode(content) as Map;
      expect(content, isNot(contains('"lat"')));
      expect(content, isNot(contains('"point"')));
      expect(data['positionsIncluded'], false);
      expect(data.containsKey('segments'), false);
      expect(data['diagnostics'][0]['raw']['speed'], 2);
      expect(data['summary']['receivedFixCount'], 3);
      expect(data['summary']['acceptedFixCount'], 2);
      expect(data['summary']['measurementCadenceSeconds']['median'], .5);
      expect(data['summary']['filterDecisions']['speed_inconsistent'], 1);
      expect(data['summary']['locationFilterVersion'], 'unknown');
    },
  );
}
