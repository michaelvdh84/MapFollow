import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/data/location_source.dart';
import 'package:mapfollow/domain/models.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryRepository repository;
  late RunController controller;
  late FakeVoice voice;
  late List<FakeLocationSource> sources;
  setUp(() async {
    repository = MemoryRepository();
    await repository.saveRoute(syntheticRoute());
    voice = FakeVoice();
    sources = [];
    controller = RunController(
      repository: repository,
      voice: voice,
      requestNotifications: () async {},
      locationFactory: (_, _, _, _) {
        final source = FakeLocationSource();
        sources.add(source);
        return source;
      },
    );
    await controller.initialize();
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
  });
  Future<void> addFix(double longitude, {double accuracy = 3}) async {
    sources.last.controller.add(
      LocationFix(
        point: RoutePoint(0, longitude),
        timestamp: DateTime.now().toUtc(),
        accuracy: accuracy,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.flush();
  }

  test(
    'one active session; pause stops GPS and resume splits export segments',
    () async {
      await controller.start(simulated: true);
      await addFix(0);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await addFix(.00004);
      expect(controller.session!.segments.single, hasLength(2));
      expect(controller.session!.distance, greaterThan(4));
      await expectLater(controller.start(simulated: true), throwsStateError);
      await controller.pause();
      expect(sources.first.stopped, isTrue);
      expect(controller.session!.status, RunStatus.paused);
      await controller.resume();
      await addFix(.00006);
      expect(controller.session!.segments, hasLength(2));
      await controller.finishAfterPending();
      expect(controller.session, isNull);
      final stored = await repository.loadRun(controller.history.single.id);
      expect(stored.status, RunStatus.finished);
      expect(stored.segments, hasLength(2));
      expect(stored.simulated, isTrue);
    },
  );
  test(
    'recovery is explicit and retains points and consumed directions',
    () async {
      final run = RunSession(
        id: 'crashed',
        routeId: 'synthetic',
        startedAt: DateTime.now(),
        simulated: true,
        progress: 80,
        announcedCueIds: {'estimated-0-1'},
      );
      await repository.createRun(run);
      await repository.appendFix(
        run,
        LocationFix(
          point: const RoutePoint(0, .0007),
          timestamp: DateTime.now(),
          accuracy: 3,
        ),
        0,
      );
      await controller.initialize();
      expect(controller.running, isFalse);
      expect(controller.recoverable!.status, RunStatus.interrupted);
      expect(controller.recoverable!.segments.single, hasLength(1));
      await controller.recover();
      expect(controller.running, isTrue);
      expect(controller.session!.announcedCueIds, contains('estimated-0-1'));
      expect(controller.session!.segments, hasLength(2));
    },
  );
  test('denied permission creates no durable session', () async {
    final blocked = RunController(
      repository: repository,
      voice: voice,
      locationFactory: (_, _, _, _) => FakeLocationSource()
        ..preparationError = const LocationAccessException('Refus synthétique'),
    );
    await blocked.initialize();
    await expectLater(
      blocked.start(simulated: false),
      throwsA(isA<LocationAccessException>()),
    );
    expect(repository.runs, isEmpty);
    blocked.dispose();
  });
  test(
    'poor GPS suspends guidance and starts a fresh recorded segment',
    () async {
      await controller.start(simulated: true);
      await addFix(0);
      await addFix(.00001, accuracy: 80);
      expect(controller.gpsReliable, isFalse);
      expect(voice.announcements.last, contains('suspendu'));
      await addFix(.00003);
      expect(controller.gpsReliable, isTrue);
      expect(controller.session!.segments, hasLength(2));
    },
  );
  test(
    'storage failure interrupts tracking rather than pretending to record',
    () async {
      await controller.start(simulated: true);
      repository.failWrites = true;
      await addFix(0);
      expect(controller.session!.status, RunStatus.interrupted);
      expect(controller.error, contains('Enregistrement interrompu'));
      expect(sources.single.stopped, isTrue);
      expect(controller.session!.segments.single, isEmpty);
      expect(controller.session!.distance, 0);
      expect(controller.session!.progress, 0);
      repository.failWrites = false;
    },
  );
}
