import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/presentation/history_tools.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'cancel preserves data and confirmed checkbox removes generated route',
    (tester) async {
      final repo = MemoryRepository();
      final run = RunSession(
        id: 'test',
        startedAt: DateTime.utc(2026),
        simulated: true,
        mode: RunMode.free,
        status: RunStatus.finished,
        generatedRouteId: 'recorded-test',
      );
      await repo.createRun(run);
      await repo.saveRoute(
        Route(
          id: 'recorded-test',
          name: 'SIMULATION',
          segments: syntheticRoute().segments,
        ),
      );
      final c = RunController(repository: repo, voice: FakeVoice());
      await c.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryTools(controller: c, run: run),
          ),
        ),
      );
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(repo.runs, hasLength(1));
      expect(repo.routes, hasLength(1));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer définitivement'));
      await tester.pumpAndSettle();
      expect(repo.runs, isEmpty);
      expect(repo.routes, isEmpty);
      await c.shutdown();
      c.dispose();
    },
  );
}
