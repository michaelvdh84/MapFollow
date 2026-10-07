import 'dart:convert';

import '../domain/models.dart';
import '../domain/run_diagnostics.dart';

/// Called only by an explicit export action; positions remain local otherwise.
class DiagnosticExporter {
  String export(
    RunSession session, {
    required List<Map<String, dynamic>> diagnostics,
  }) => const JsonEncoder.withIndent('  ').convert(
    _serializable({
      'format': 'mapfollow-diagnostics',
      'version': 1,
      'batteryScope': 'wholeDevice',
      'session': session.toJson(),
      if (session.diagnosticsMode == DiagnosticsMode.diagnostic)
        'segments': session.segments
            .map((segment) => segment.map((fix) => fix.toJson()).toList())
            .toList(),
      'diagnostics': session.diagnosticsMode == DiagnosticsMode.diagnostic
          ? diagnostics
          : const <Map<String, dynamic>>[],
    }),
  );

  Object? _serializable(Object? value) {
    if (value is num && !value.isFinite) return null;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is List) return value.map(_serializable).toList();
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          // Satellite observations are deliberately ephemeral in MapFollow.
          if (!const {
            'gnss',
            'constellations',
            'satelliteCount',
            'satellites',
          }.contains(entry.key.toString()))
            entry.key.toString(): _serializable(entry.value),
      };
    }
    return value;
  }
}
