import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/domain/models.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryRepository repository;
  late RunController controller;
  late List<FakeLocationSource> sources;
  late List<LocationProfile> profiles;
  setUp(() async {
    repository = MemoryRepository();
    sources = [];
    profiles = [];
    controller = RunController(
      repository: repository,
      voice: FakeVoice(),
      requestNotifications: () async {},
      locationFactory: (_, _, _, profile) {
        profiles.add(profile);
        final source = FakeLocationSource();
        sources.add(source);
        return source;
      },
    );
    await controller.initialize();
  });
  tearDown(() async {
    repository.failWrites = false;
    await controller.shutdown();
    controller.dispose();
  });
  Future<void> emit(double longitude, DateTime at, double? speed) async {
    sources.last.controller.add(
      LocationFix(
        point: RoutePoint(0, longitude),
        timestamp: at,
        accuracy: 3,
        speed: speed,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.flush();
  }

  test(
    'a running session pins its original profile across pause and resume',
    () async {
      await controller.start(simulated: false, mode: RunMode.free);
      final id = controller.session!.id;
      expect(profiles.single, LocationProfile.precise);
      final announcementsStopped = (controller.voice as FakeVoice).stopped;
      await controller.updateSettings(
        controller.settings.copyWith(locationProfile: LocationProfile.autonomy),
      );
      expect(sources, hasLength(1));
      expect((controller.voice as FakeVoice).stopped, announcementsStopped);
      await controller.pause();
      await controller.resume();
      expect(profiles, [LocationProfile.precise, LocationProfile.precise]);
      expect(
        (await repository.loadRun(id)).locationProfile,
        LocationProfile.precise,
      );
      await controller.finishAfterPending();
      await controller.start(simulated: false, mode: RunMode.free);
      expect(profiles.last, LocationProfile.autonomy);
    },
  );

  test(
    'explicit recovery restores profile, manual choice and labelled points',
    () async {
      await controller.start(simulated: false, mode: RunMode.free);
      final id = controller.session!.id;
      await controller.updateTraversalControl(TraversalControl.returning);
      await emit(0, DateTime.now().toUtc(), 2);
      await controller.updateSettings(
        controller.settings.copyWith(locationProfile: LocationProfile.autonomy),
      );
      // Un nouveau contrôleur relit la sauvegarde, comme après un redémarrage.
      await controller.shutdown();
      controller.dispose();
      controller = RunController(
        repository: repository,
        voice: FakeVoice(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, profile) {
          profiles.add(profile);
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await controller.initialize();
      expect(controller.session, isNull);
      expect(sources, hasLength(1));
      expect(controller.recoverable!.id, id);
      await controller.recover();
      expect(profiles.last, LocationProfile.precise);
      expect(controller.session!.traversalControl, TraversalControl.returning);
      expect(
        controller.session!.segments.first.single.point.traversal,
        TraversalDirection.returning,
      );
      await emit(.00008, DateTime.now().toUtc(), 2);
      expect(controller.session!.segments, hasLength(2));
      expect(
        controller.session!.segments.last.single.point.traversal,
        TraversalDirection.returning,
      );
    },
  );

  test(
    'manual classification is prospective, durable, and cleared by Auto',
    () async {
      await controller.start(simulated: false, mode: RunMode.free);
      final at = DateTime.now().toUtc().subtract(const Duration(seconds: 3));
      await emit(0, at, 3);
      await controller.updateTraversalControl(TraversalControl.returning);
      await emit(.00008, at.add(const Duration(seconds: 1)), 3);
      final recordedLongitude =
          controller.session!.segments.single[1].point.longitude;
      await controller.updateTraversalControl(TraversalControl.automatic);
      await emit(.00016, at.add(const Duration(seconds: 2)), 3);
      final stored = await repository.loadRun(controller.session!.id);
      expect(
        stored.segments.single.first.point.traversal,
        TraversalDirection.outbound,
      );
      expect(
        stored.segments.single[1].point.traversal,
        TraversalDirection.returning,
      );
      expect(stored.traversalControl, TraversalControl.automatic);
      // Auto ne réécrit pas la position déjà traitée et enregistrée en manuel.
      expect(stored.segments.single[1].point.longitude, recordedLongitude);
      expect(controller.navigation, isNull);
    },
  );

  test(
    'manual setting and points roll back independently on storage failure',
    () async {
      await controller.start(simulated: false, mode: RunMode.free);
      final at = DateTime.now().toUtc().subtract(const Duration(seconds: 2));
      await emit(0, at, 3);
      repository.failWrites = true;
      await expectLater(
        controller.updateTraversalControl(TraversalControl.returning),
        throwsStateError,
      );
      expect(controller.session!.traversalControl, TraversalControl.automatic);
      await emit(.00008, at.add(const Duration(seconds: 1)), 3);
      expect(controller.session!.status, RunStatus.interrupted);
      expect(controller.session!.segments.single, hasLength(1));
      repository.failWrites = false;
      await controller.resume();
      await emit(.00016, DateTime.now().toUtc(), null);
      expect(controller.session!.segments, hasLength(2));
      expect(controller.currentSpeedMetresPerSecond, isNull);
      await controller.pause();
      expect(controller.currentSpeedMetresPerSecond, 0);
      await controller.resume();
      expect(controller.currentSpeedMetresPerSecond, isNull);
    },
  );
}
