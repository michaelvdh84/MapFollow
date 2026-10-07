import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/data/location_source.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/presentation/app.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'empty library launches a free run, blank map waits for GPS, recap offers route actions',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProvider,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null),
      );
      final repository = MemoryRepository();
      final source = _WidgetLocationSource();
      final controller = RunController(
        repository: repository,
        voice: FakeVoice(),
        batterySource: FakeBatterySource(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) => source,
      );
      await controller.initialize();
      await tester.pumpWidget(MapFollowApp(controller: controller));
      await tester.pump();

      expect(
        find.text(
          'Aucun parcours enregistré. La démo permet de tester le guidage sans courir.',
        ),
        findsOneWidget,
      );
      expect(find.text('Lancer un Run libre'), findsOneWidget);
      await tester.tap(find.text('Course'));
      await tester.pump();
      expect(
        find.textContaining(
          'Enregistrez votre trajet sans importer de parcours.',
        ),
        findsOneWidget,
      );
      expect(find.text('© OpenStreetMap contributors · ODbL'), findsOneWidget);

      await Scrollable.ensureVisible(
        tester.element(find.text('Lancer un Run libre')),
        alignment: .5,
      );
      await tester.pump();
      await tester.tap(find.text('Lancer un Run libre'));
      await tester.pump();
      await tester.pump();
      expect(find.text('En attente du GPS'), findsOneWidget);
      expect(controller.session!.routeId, isNull);

      final at = DateTime.now().toUtc();
      source.emit(const RoutePoint(50, 4), at);
      source.emit(
        const RoutePoint(50, 4.0001),
        at.add(const Duration(seconds: 1)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await controller.flush();
      await tester.pump();
      expect(controller.session!.status, RunStatus.running);

      await tester.tap(find.text('Terminer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Terminer le Run ?'), findsOneWidget);
      await tester.tap(find.text('Terminer').last);
      await tester.pump();
      expect(controller.busy, isTrue);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 20));
      expect(source.stopped, isTrue);
      expect(controller.session, isNull);
      expect(find.text('Run terminé'), findsOneWidget);
      expect(find.text('Voir le parcours'), findsOneWidget);
      expect(find.text('Renommer'), findsOneWidget);
      expect(find.text('Exporter / partager'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await controller.shutdown();
      controller.dispose();
    },
  );
}

class _WidgetLocationSource implements LocationSource {
  final _fixes = StreamController<LocationFix>.broadcast();
  bool stopped = false;
  @override
  Future<void> prepare() async {}
  @override
  Stream<LocationFix> get fixes => _fixes.stream;
  void emit(RoutePoint point, DateTime at) =>
      _fixes.add(LocationFix(point: point, timestamp: at, accuracy: 3));
  @override
  Future<void> stop() async {
    stopped = true;
    if (!_fixes.isClosed) unawaited(_fixes.close());
  }
}
