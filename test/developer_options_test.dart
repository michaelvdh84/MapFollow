import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/presentation/developer_options.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';

void main() {
  group('custom GPS interval', () {
    test('accepts decimal points and commas and converts to milliseconds', () {
      expect(parseLocationIntervalMillis('0.25'), 250);
      expect(parseLocationIntervalMillis('0,25'), 250);
      expect(parseLocationIntervalMillis('1,125'), 1125);
      expect(parseLocationIntervalMillis('10'), 10000);
      expect(parseLocationIntervalMillis(''), isNull);
    });

    test('enforces the inclusive 0.25 to 10 second range', () {
      for (final value in ['0.249', '10.001', 'abc', 'NaN', 'Infinity']) {
        expect(parseLocationIntervalMillis(value), isNull, reason: value);
        expect(validateLocationInterval(value), isNotNull, reason: value);
      }
      expect(validateLocationInterval(''), isNull);
      expect(validateLocationInterval('0,25'), isNull);
    });
  });

  testWidgets('exports selected finished run with positions off by default', (
    tester,
  ) async {
    final runs = [
      RunSession(
        id: 'synthetic-finished',
        name: 'Course synthétique',
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: RunStatus.finished,
        diagnosticsMode: DiagnosticsMode.normal,
      ),
      RunSession(
        id: 'synthetic-pending',
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: RunStatus.interrupted,
      ),
    ];
    final exports = <(String, bool)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: ListView(
              children: [
                DeveloperOptions(
                  intervalMillis: null,
                  onIntervalChanged: (_) {},
                  diagnosticsMode: DiagnosticsMode.normal,
                  onDiagnosticsModeChanged: (_) {},
                  runs: runs,
                  busy: false,
                  onExport: (id, includePositions) async =>
                      exports.add((id, includePositions)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('developerExportRun')));
    await tester.pumpAndSettle();
    expect(find.text('Course synthétique'), findsWidgets);
    expect(find.text('synthetic-pending'), findsNothing);
    await tester.tap(find.text('Course synthétique').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('developerIncludePositions')), findsNothing);
    expect(
      find.textContaining('Aucun détail GPS n’a été enregistré'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('developerExportLogs')));
    await tester.pump();
    expect(exports, [('synthetic-finished', false)]);
  });

  testWidgets('accepts 0,5 seconds and immediately shows validation errors', (
    tester,
  ) async {
    int? changedInterval;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: ListView(
              children: [
                DeveloperOptions(
                  intervalMillis: null,
                  onIntervalChanged: (value) => changedInterval = value,
                  diagnosticsMode: DiagnosticsMode.normal,
                  onDiagnosticsModeChanged: (_) {},
                  runs: const [],
                  busy: false,
                  onExport: (_, _) async {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final field = find.byKey(const Key('developerLocationInterval'));
    await tester.enterText(field, '0,5');
    await tester.pump();
    expect(changedInterval, 500);
    expect(
      find.text('Saisissez une valeur entre 0,25 et 10 secondes.'),
      findsNothing,
    );

    await tester.enterText(field, '0,24');
    await tester.pump();
    expect(changedInterval, 500);
    expect(
      find.text('Saisissez une valeur entre 0,25 et 10 secondes.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'resets position consent when the selected diagnostic run changes',
    (tester) async {
      final runs = [
        for (final id in ['synthetic-a', 'synthetic-b'])
          RunSession(
            id: id,
            name: id,
            startedAt: DateTime.utc(2026),
            simulated: true,
            status: RunStatus.finished,
            diagnosticsMode: DiagnosticsMode.diagnostic,
          ),
      ];
      final exports = <(String, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: ListView(
                children: [
                  DeveloperOptions(
                    intervalMillis: null,
                    onIntervalChanged: (_) {},
                    diagnosticsMode: DiagnosticsMode.normal,
                    onDiagnosticsModeChanged: (_) {},
                    runs: runs,
                    busy: false,
                    onExport: (id, includePositions) async =>
                        exports.add((id, includePositions)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('developerExportRun')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('synthetic-a').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('developerIncludePositions')));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('developerIncludePositions')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('developerExportRun')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('synthetic-b').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('developerIncludePositions')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('developerExportLogs')));
      await tester.pump();
      expect(exports, [('synthetic-b', false)]);
    },
  );
}
