import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/diagnostic_exporter.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';

void main() {
  final now = DateTime.utc(2026);
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
}
