import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/domain/models.dart' as domain;
import 'package:mapfollow/presentation/app.dart';
import 'package:mapfollow/presentation/free_run_screen.dart';
import 'package:mapfollow/presentation/formatters.dart';
import 'package:mapfollow/presentation/run_tracking_controls.dart';
import 'package:mapfollow/presentation/running_metrics.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'guided finish recap shows mean speed and pace from active time',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final route = domain.Route(
        id: 'guided-synthetic',
        name: 'Démo guidée',
        segments: [
          domain.RouteSegment(const [
            domain.RoutePoint(50, 4),
            domain.RoutePoint(50, 4.001),
          ]),
        ],
      );
      final c = RunController(
        repository: MemoryRepository(),
        voice: FakeVoice(),
      );
      await c.initialize();
      c.routes = [route];
      c.selectRoute(route);
      c.lastFinished = domain.RunSession(
        id: 'guided-recap',
        routeId: route.id,
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: domain.RunStatus.finished,
        activeSeconds: 600,
        distance: 2000,
      );
      await tester.pumpWidget(MapFollowApp(controller: c));
      await tester.tap(find.text('Course'));
      await tester.pump();
      expect(find.text('Course guidée terminée'), findsOneWidget);
      expect(find.text('Vitesse moyenne : 12.0 km/h'), findsOneWidget);
      expect(find.text('Allure moyenne : 5:00 min/km'), findsOneWidget);
      expect(find.text('Exporter le GPX'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('finished history shows average metrics for both running modes', (
    tester,
  ) async {
    final c = RunController(repository: MemoryRepository(), voice: FakeVoice());
    await c.initialize();
    c.history = [
      domain.RunSession(
        id: 'history-guided',
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: domain.RunStatus.finished,
        activeSeconds: 600,
        distance: 2000,
      ),
      domain.RunSession(
        id: 'history-free',
        mode: domain.RunMode.free,
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: domain.RunStatus.finished,
        activeSeconds: 600,
        distance: 1000,
      ),
    ];
    await tester.pumpWidget(MapFollowApp(controller: c));
    await tester.tap(find.text('Historique'));
    await tester.pump();
    expect(find.text('Vitesse moyenne : 12.0 km/h'), findsOneWidget);
    expect(find.text('Allure moyenne : 5:00 min/km'), findsOneWidget);
    expect(find.text('Vitesse moyenne : 6.0 km/h'), findsOneWidget);
    expect(find.text('Allure moyenne : 10:00 min/km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'future GPS profile remains editable during a run without changing active profile or voice',
    (tester) async {
      final repo = MemoryRepository();
      final voice = FakeVoice();
      final c = RunController(repository: repo, voice: voice);
      c.settings = const domain.GuidanceSettings(
        warningDistance: 80,
        offRouteDistance: 45,
        voiceVolume: .4,
      );
      c.session = domain.RunSession(
        id: 'live-profile',
        startedAt: DateTime.utc(2026),
        simulated: true,
        locationProfile: domain.LocationProfile.balanced,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsScreen(controller: c)),
        ),
      );
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(slider.onChanged, isNull);
      }
      await tester.tap(
        find.byType(DropdownButtonFormField<domain.LocationProfile>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autonomie · 5 s / 5 m').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Enregistrer le profil de la prochaine course'),
      );
      await tester.tap(
        find.text('Enregistrer le profil de la prochaine course'),
      );
      await tester.pump();
      expect(repo.settings.locationProfile, domain.LocationProfile.autonomy);
      expect(c.session!.locationProfile, domain.LocationProfile.balanced);
      expect(repo.settings.warningDistance, 80);
      expect(repo.settings.offRouteDistance, 45);
      expect(repo.settings.voiceVolume, .4);
      expect(voice.stopped, 0);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test(
    'speed distinguishes missing and stationary; pace rounds total seconds',
    () {
      expect(speed(null), '--');
      expect(speed(0), '0.0 km/h');
      expect(speed(3), '10.8 km/h');
      expect(pace(null), '--');
      expect(pace(0), '--');
      expect(pace(1000 / 359.6), '6:00 min/km');
    },
  );

  testWidgets(
    'shared running metrics renders missing, speed and pause states',
    (tester) async {
      Future<void> show(double? value) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RunningMetrics(
              activeSeconds: 61,
              distance: 1200,
              metresPerSecond: value,
            ),
          ),
        ),
      );
      await show(null);
      expect(find.text('Vitesse : --'), findsOneWidget);
      await show(3);
      expect(find.text('Vitesse : 10.8 km/h'), findsOneWidget);
      expect(find.text('Allure : 5:33 min/km'), findsOneWidget);
      await show(0);
      expect(find.text('Vitesse : 0.0 km/h'), findsOneWidget);
      expect(find.text('Allure : --'), findsOneWidget);
      expect(find.text('Durée active : 00:01:01'), findsOneWidget);
    },
  );

  testWidgets('free finish recap uses active duration for mean speed', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => Directory.systemTemp.path,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final c = RunController(repository: MemoryRepository(), voice: FakeVoice());
    c.lastFinished = domain.RunSession(
      id: 'synthetic',
      mode: domain.RunMode.free,
      startedAt: DateTime.utc(2026),
      simulated: true,
      status: domain.RunStatus.finished,
      activeSeconds: 600,
      distance: 1000,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FreeRunScreen(controller: c, onViewRoute: (_) {}),
        ),
      ),
    );
    await tester.ensureVisible(find.byType(RunningMetrics));
    await tester.pump();
    expect(find.text('Vitesse moyenne : 6.0 km/h'), findsOneWidget);
    expect(find.text('Allure moyenne : 10:00 min/km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('settings save GPS profile together with existing thresholds', (
    tester,
  ) async {
    final repo = MemoryRepository();
    final c = RunController(repository: repo, voice: FakeVoice());
    c.settings = const domain.GuidanceSettings(
      warningDistance: 80,
      offRouteDistance: 45,
      voiceVolume: .4,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(controller: c)),
      ),
    );
    await tester.tap(
      find.byType(DropdownButtonFormField<domain.LocationProfile>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autonomie · 5 s / 5 m').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enregistrer les réglages'));
    await tester.tap(find.text('Enregistrer les réglages'));
    await tester.pump();
    expect(repo.settings.locationProfile, domain.LocationProfile.autonomy);
    expect(repo.settings.warningDistance, 80);
    expect(repo.settings.offRouteDistance, 45);
    expect(repo.settings.voiceVolume, .4);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets(
    'active profile is retained and traversal selector persists future choice',
    (tester) async {
      final repo = MemoryRepository();
      final c = RunController(repository: repo, voice: FakeVoice());
      c.session = domain.RunSession(
        id: 'control',
        startedAt: DateTime.utc(2026),
        simulated: true,
        locationProfile: domain.LocationProfile.precise,
        status: domain.RunStatus.paused,
      );
      c.settings = const domain.GuidanceSettings(
        locationProfile: domain.LocationProfile.autonomy,
      );
      await repo.createRun(c.session!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => RunTrackingControls(controller: c),
            ),
          ),
        ),
      );
      expect(
        find.text('Profil GPS de cette course : Précision · 1 s / 2 m'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retour'));
      await tester.pump();
      expect(c.session!.traversalControl, domain.TraversalControl.returning);
      expect(
        (await repo.loadRun('control')).traversalControl,
        domain.TraversalControl.returning,
      );
      expect(find.textContaining('Le guidage garde le sens'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Diagnostics GNSS'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('Diagnostics GNSS indisponibles en simulation.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
