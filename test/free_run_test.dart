import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/data/voice_service.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/navigation.dart';
import 'package:mapfollow/domain/recorded_route.dart';

import 'fakes.dart';

class CountingVoice implements VoiceService {
  int prepareCalls = 0;
  int speakCalls = 0;
  Object? prepareError;
  @override
  Future<void> prepare(double volume) async {
    prepareCalls++;
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<bool> speak(String text) async {
    speakCalls++;
    return true;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LocationFix fix(double latitude, double longitude, DateTime at) =>
      LocationFix(
        point: RoutePoint(latitude, longitude),
        timestamp: at,
        accuracy: 3,
      );

  test(
    'free run starts without library route or voice preparation and splits gaps',
    () async {
      final repository = MemoryRepository();
      final voice = CountingVoice()
        ..prepareError = StateError('Voice must not be prepared');
      final source = FakeLocationSource();
      PreparedRoute? sourceRoute;
      var notificationRequests = 0;
      final controller = RunController(
        repository: repository,
        voice: voice,
        requestNotifications: () async => notificationRequests++,
        locationFactory: (route, _, _, _) {
          sourceRoute = route;
          return source;
        },
      );
      await controller.initialize();
      expect(controller.routes, isEmpty);

      await controller.start(simulated: false, mode: RunMode.free);
      expect(sourceRoute, isNull);
      expect(controller.session!.routeId, isNull);
      expect(controller.session!.mode, RunMode.free);
      expect(voice.prepareCalls, 0);
      expect(voice.speakCalls, 0);
      expect(notificationRequests, 1);

      final first = DateTime.now().toUtc();
      source.controller.add(fix(50, 4, first));
      source.controller.add(
        fix(91, 4, first.add(const Duration(milliseconds: 1))),
      );
      source.controller.add(
        fix(50, 4.00005, first.add(const Duration(seconds: 1))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await controller.flush();
      expect(controller.session!.segments, hasLength(2));
      expect(controller.session!.segments.first, hasLength(1));
      expect(controller.session!.segments.last, hasLength(1));
      expect(voice.speakCalls, 0);

      await controller.pause();
      expect(source.stopped, isTrue);
      await controller.shutdown();
      controller.dispose();
    },
  );

  test(
    'free permission refusal leaves no durable session and never prepares voice',
    () async {
      final repository = MemoryRepository();
      final voice = CountingVoice()
        ..prepareError = StateError('Voice must not be prepared');
      final source = FakeLocationSource();
      final controller = RunController(
        repository: repository,
        voice: voice,
        requestNotifications: () async =>
            throw StateError('Permission refused'),
        locationFactory: (_, _, _, _) => source,
      );
      await controller.initialize();
      await expectLater(
        controller.start(simulated: false, mode: RunMode.free),
        throwsStateError,
      );
      expect(repository.runs, isEmpty);
      expect(source.stopped, isTrue);
      expect(voice.prepareCalls, 0);
      controller.dispose();
    },
  );

  test(
    'free append failure rolls back the failed point, stops GPS, then resumes in a new segment',
    () async {
      final repository = MemoryRepository();
      final sources = <FakeLocationSource>[];
      final controller = RunController(
        repository: repository,
        voice: CountingVoice(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) {
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await controller.initialize();
      await controller.start(simulated: false, mode: RunMode.free);
      final at = DateTime.now().toUtc();
      sources[0].controller.add(fix(50, 4, at));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.flush();
      expect(controller.session!.segments.single, hasLength(1));

      repository.failWrites = true;
      sources[0].controller.add(
        fix(50, 4.00005, at.add(const Duration(seconds: 1))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.flush();
      expect(controller.session!.status, RunStatus.interrupted);
      expect(controller.session!.segments.single, hasLength(1));
      expect(controller.session!.distance, 0);
      expect(sources[0].stopped, isTrue);

      repository.failWrites = false;
      await controller.resume();
      expect(controller.session!.segments, hasLength(2));
      sources[1].controller.add(
        fix(50, 4.0001, at.add(const Duration(seconds: 2))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.flush();
      expect(controller.session!.segments[1], hasLength(1));
      expect(controller.session!.segments.first, hasLength(1));

      await controller.shutdown();
      controller.dispose();
    },
  );

  test(
    'resumed free run rejects a timestamp older than the last recorded point',
    () async {
      final repository = MemoryRepository();
      final started = DateTime.now().toUtc().subtract(
        const Duration(seconds: 8),
      );
      final oldRun = RunSession(
        id: 'monotonic-free',
        mode: RunMode.free,
        startedAt: started,
        simulated: false,
        status: RunStatus.interrupted,
      );
      await repository.createRun(oldRun);
      await repository.appendFix(oldRun, fix(50, 4, started), 0);
      await repository.appendFix(
        oldRun,
        fix(50, 4.0001, started.add(const Duration(seconds: 1))),
        0,
      );
      final sources = <FakeLocationSource>[];
      final controller = RunController(
        repository: repository,
        voice: CountingVoice(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) {
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await controller.initialize();
      await controller.recover();
      final lastSaved = started.add(const Duration(seconds: 1));
      sources.single.controller.add(
        fix(50, 4.00012, lastSaved.subtract(const Duration(milliseconds: 1))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.flush();
      expect(controller.session!.segments, hasLength(2));
      expect(controller.session!.segments.last, isEmpty);

      sources.single.controller.add(
        fix(50, 4.00012, lastSaved.add(const Duration(seconds: 1))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await controller.flush();
      expect(controller.session!.segments.last, hasLength(1));
      await controller.shutdown();
      controller.dispose();
    },
  );

  test(
    'storage failure saving a resumed free run stops its new GPS source',
    () async {
      final repository = MemoryRepository();
      final sources = <FakeLocationSource>[];
      final controller = RunController(
        repository: repository,
        voice: CountingVoice(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) {
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await controller.initialize();
      await controller.start(simulated: false, mode: RunMode.free);
      await controller.pause();
      repository.failWrites = true;
      await expectLater(controller.resume(), throwsStateError);
      expect(sources.last.stopped, isTrue);
      expect(controller.running, isFalse);
      expect(controller.session!.status, RunStatus.interrupted);
      expect(controller.error, contains('Reprise interrompue'));
      repository.failWrites = false;
      await controller.shutdown();
      controller.dispose();
    },
  );

  test(
    'free recovery resumes with no original route and generated finish is retryable',
    () async {
      final repository = MemoryRepository();
      final voice = CountingVoice();
      final oldRun = RunSession(
        id: 'recover-free',
        routeId: null,
        mode: RunMode.free,
        name: 'Run libre synthétique',
        startedAt: DateTime.now().toUtc(),
        simulated: false,
        status: RunStatus.interrupted,
      );
      await repository.createRun(oldRun);
      final oldTime = DateTime.now().toUtc().subtract(
        const Duration(seconds: 2),
      );
      await repository.appendFix(oldRun, fix(50, 4, oldTime), 0);
      await repository.appendFix(
        oldRun,
        fix(50, 4.0001, oldTime.add(const Duration(seconds: 1))),
        0,
      );

      final sources = <FakeLocationSource>[];
      final sourceRoutes = <PreparedRoute?>[];
      final controller = RunController(
        repository: repository,
        voice: voice,
        requestNotifications: () async {},
        locationFactory: (route, _, _, _) {
          sourceRoutes.add(route);
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await controller.initialize();
      expect(controller.recoverable!.routeId, isNull);
      await controller.recover();
      expect(controller.running, isTrue);
      expect(sourceRoutes.single, isNull);
      expect(controller.session!.segments, hasLength(2));
      expect(voice.prepareCalls, 0);

      await controller.pause();
      repository.failWrites = true;
      await expectLater(controller.finishAfterPending(), throwsStateError);
      expect(controller.session, isNotNull);
      expect(controller.lastFinished, isNull);
      expect(controller.session!.generatedRouteId, isNull);

      repository.failWrites = false;
      await controller.finishAfterPending();
      final finished = controller.lastFinished!;
      expect(finished.status, RunStatus.finished);
      expect(finished.generatedRouteId, 'recorded-recover-free');
      expect(routeFromRun(finished), isNotNull);
      expect(
        controller.routes.where((r) => r.id == 'recorded-recover-free'),
        hasLength(1),
      );
      expect(
        (await repository.loadRun('recover-free')).status,
        RunStatus.finished,
      );

      await controller.shutdown();
      controller.dispose();
    },
  );

  test(
    'free simulated run keeps its SIMULATION prefix and renames its generated route',
    () async {
      final repository = MemoryRepository();
      final voice = CountingVoice();
      final source = FakeLocationSource();
      final controller = RunController(
        repository: repository,
        voice: voice,
        requestNotifications: () async {},
        // Free simulation may receive its private demo geometry for synthetic GPS.
        locationFactory: (_, _, _, _) => source,
      );
      await controller.initialize();
      await controller.start(simulated: true, mode: RunMode.free);
      expect(controller.session!.routeId, isNull);
      expect(controller.session!.name, startsWith('SIMULATION'));
      expect(voice.prepareCalls, 0);

      final at = DateTime.now().toUtc();
      source.controller.add(fix(50, 4, at));
      source.controller.add(
        fix(50, 4.0001, at.add(const Duration(seconds: 1))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await controller.finishAfterPending();

      await controller.renameRun(
        controller.lastFinished!.id,
        'Balade synthétique',
      );
      expect(controller.lastFinished!.name, 'SIMULATION · Balade synthétique');
      expect(
        controller.generatedRoute(controller.lastFinished!)!.name,
        'SIMULATION · Balade synthétique',
      );
      final stored = await repository.loadRun(controller.lastFinished!.id);
      expect(stored.name, 'SIMULATION · Balade synthétique');
      expect(repository.routes['recorded-${stored.id}']!.name, stored.name);

      await controller.shutdown();
      controller.dispose();
    },
  );
}
