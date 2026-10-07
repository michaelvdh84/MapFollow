import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';
import 'package:mapfollow/presentation/battery_summary.dart';

void main() {
  final now = DateTime.utc(2026);
  Future<void> show(
    WidgetTester tester,
    List<BatterySample> samples, {
    bool detailed = false,
    bool interrupted = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BatterySummary(
          samples: samples,
          detailed: detailed,
          interrupted: interrupted,
        ),
      ),
    ),
  );

  testWidgets('legacy history shows battery unavailable', (tester) async {
    await show(tester, []);
    expect(find.text('Batterie non mesurée'), findsOneWidget);
  });

  testWidgets('ongoing run never displays an incomplete final consumption', (
    tester,
  ) async {
    await show(tester, [
      BatterySample(
        timestamp: now,
        levelPercent: 100,
        charging: false,
        event: 'start',
      ),
      BatterySample(
        timestamp: now.add(const Duration(minutes: 1)),
        levelPercent: 99,
        charging: false,
      ),
    ]);
    expect(find.textContaining('bilan à la fin'), findsOneWidget);
    expect(find.textContaining('baisse'), findsNothing);
  });

  testWidgets('recovered legacy run with only finish cannot invent a start', (
    tester,
  ) async {
    await show(tester, [
      BatterySample(
        timestamp: now,
        levelPercent: 93,
        charging: false,
        event: 'finish',
      ),
    ]);
    expect(find.textContaining('Batterie : -- → 93 %'), findsOneWidget);
    expect(find.textContaining('baisse'), findsNothing);
    expect(find.textContaining('indisponibles'), findsOneWidget);
  });

  testWidgets('summary explains whole-phone scope and interruptions', (
    tester,
  ) async {
    await show(tester, [
      BatterySample(
        timestamp: now,
        levelPercent: 100,
        charging: false,
        event: 'start',
      ),
      BatterySample(
        timestamp: now.add(const Duration(hours: 1)),
        levelPercent: 93,
        charging: false,
        event: 'finish',
      ),
    ], interrupted: true);
    expect(find.textContaining('baisse 7 points'), findsOneWidget);
    expect(find.textContaining('YouTube Music'), findsOneWidget);
    expect(find.textContaining('Mesure interrompue'), findsOneWidget);
    expect(find.textContaining('Courbe'), findsNothing);
  });

  testWidgets(
    'diagnostics chart needs three values and warns for charging/missing',
    (tester) async {
      await show(tester, [
        BatterySample(
          timestamp: now,
          levelPercent: 99,
          charging: false,
          event: 'start',
        ),
        BatterySample(timestamp: now.add(const Duration(minutes: 1))),
        BatterySample(
          timestamp: now.add(const Duration(minutes: 2)),
          levelPercent: 100,
          charging: true,
        ),
        BatterySample(
          timestamp: now.add(const Duration(minutes: 3)),
          levelPercent: 99,
          charging: false,
          event: 'finish',
        ),
      ], detailed: true);
      expect(find.textContaining('Recharge détectée'), findsOneWidget);
      expect(find.textContaining('indisponibles'), findsOneWidget);
      expect(find.textContaining('Courbe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
