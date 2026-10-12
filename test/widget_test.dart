import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/presentation/app.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'French library, history and persistent settings are accessible',
    (tester) async {
      final repository = MemoryRepository();
      final controller = RunController(
        repository: repository,
        voice: FakeVoice(),
        readApplicationVersion: () async => '9.8.7+42',
      );
      await controller.initialize();
      await tester.pumpWidget(MapFollowApp(controller: controller));
      expect(find.text('Importer GPX, TCX ou PWX'), findsOneWidget);
      await tester.tap(find.text('POC'));
      await tester.pumpAndSettle();
      expect(find.text('9.8.7+42'), findsOneWidget);
      expect(find.text('0.3.0'), findsNothing);
      Navigator.of(
        tester.element(find.text('9.8.7+42')),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();
      expect(find.text('Importer GPX, TCX ou PWX'), findsOneWidget);
      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();
      expect(find.text('Vos courses'), findsOneWidget);
      await tester.tap(find.text('Réglages'));
      await tester.pumpAndSettle();
      expect(find.text('Prévenir 20 m avant le virage'), findsOneWidget);
      final slider = find.byType(Slider).first;
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(100, 0));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Enregistrer les réglages')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer les réglages'));
      await tester.pumpAndSettle();
      expect(repository.settings.warningDistance, greaterThan(20));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await controller.shutdown();
      controller.dispose();
    },
  );
}
