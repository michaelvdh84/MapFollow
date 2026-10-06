import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/repository.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'fakes.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late SqliteRunRepository repository;
  setUp(() async {
    repository = await SqliteRunRepository.open(
      databasePath: inMemoryDatabasePath,
    );
  });
  tearDown(() => repository.close());
  test(
    'reads legacy run JSON as guided with empty name and no generated route',
    () {
      final run = RunSession.fromJson({
        'id': 'legacy',
        'routeId': 'route',
        'startedAt': '2024-01-01T00:00:00.000Z',
        'simulated': false,
        'status': 'finished',
        'endedAt': null,
        'activeSeconds': 5,
        'distance': 12.0,
        'progress': 50.0,
        'announcedCueIds': <String>[],
      });
      expect(run.mode, RunMode.guided);
      expect(run.name, isEmpty);
      expect(run.generatedRouteId, isNull);
      expect(run.locationProfile, LocationProfile.precise);
      expect(run.traversalControl, TraversalControl.automatic);
    },
  );
  test(
    'round trips routes, settings, fixes and progress through real SQLite',
    () async {
      await repository.saveRoute(syntheticRoute());
      expect(
        (await repository.listRoutes()).single.segments.single.points.length,
        3,
      );
      await repository.saveSettings(
        const GuidanceSettings(
          warningDistance: 50,
          voiceVolume: .6,
          locationProfile: LocationProfile.autonomy,
        ),
      );
      expect((await repository.loadSettings()).warningDistance, 50);
      expect(
        (await repository.loadSettings()).locationProfile,
        LocationProfile.autonomy,
      );
      final run = RunSession(
        id: 'real-db',
        routeId: 'synthetic',
        startedAt: DateTime.utc(2026),
        simulated: false,
        locationProfile: LocationProfile.balanced,
        traversalControl: TraversalControl.returning,
      );
      await repository.createRun(run);
      run.progress = 30;
      run.announcedCueIds.add('cue');
      run.distance = 10;
      final first = LocationFix(
        point: const RoutePoint(0, 0),
        timestamp: DateTime.utc(2026),
        accuracy: 3,
      );
      await repository.appendFix(run, first, 0);
      final second = LocationFix(
        point: const RoutePoint(
          0,
          .0001,
          traversal: TraversalDirection.returning,
        ),
        timestamp: DateTime.utc(2026, 1, 1, 0, 0, 10),
        accuracy: 3,
      );
      await repository.appendFix(run, second, 1);
      final recovered = await repository.loadRun(run.id);
      expect(recovered.segments, hasLength(2));
      expect(recovered.segments.first.single.point.latitude, 0);
      expect(recovered.segments.last.single.timestamp, second.timestamp);
      expect(recovered.progress, 30);
      expect(recovered.announcedCueIds, contains('cue'));
      expect(recovered.locationProfile, LocationProfile.balanced);
      expect(recovered.traversalControl, TraversalControl.returning);
      expect(
        recovered.segments.last.single.point.traversal,
        TraversalDirection.returning,
      );
      expect(recovered.segments.last.single.speed, isNull);
    },
  );
  test(
    'saves a run and generated route atomically and replaces the route',
    () async {
      final run = RunSession(
        id: 'free-atomic',
        routeId: null,
        startedAt: DateTime.utc(2026),
        simulated: false,
        mode: RunMode.free,
        name: 'Balade',
        generatedRouteId: 'generated',
      );
      await repository.createRun(run);
      final route = syntheticRoute();
      final generated = Route(
        id: 'generated',
        name: 'Balade',
        segments: route.segments,
      );
      await repository.saveRunWithRoute(run, route: generated);
      await repository.saveRunWithRoute(run, route: generated);
      expect(
        (await repository.listRoutes()).where((r) => r.id == 'generated'),
        hasLength(1),
      );

      await repository.database.execute(
        "CREATE TRIGGER reject_route BEFORE INSERT ON routes WHEN NEW.id = 'reject' BEGIN SELECT RAISE(ABORT, 'route rejected'); END",
      );
      final rejected = Route(
        id: 'reject',
        name: 'Échec',
        segments: route.segments,
      );
      run.name = 'Ne doit pas être sauvegardé';
      await expectLater(
        repository.saveRunWithRoute(run, route: rejected),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repository.loadRun(run.id)).name, 'Balade');
      await expectLater(
        repository.saveRunWithRoute(
          RunSession(
            id: 'missing',
            routeId: null,
            startedAt: DateTime.utc(2026),
            simulated: false,
            mode: RunMode.free,
          ),
          route: rejected,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
  test(
    'database prevents a second active run, including interrupted sessions',
    () async {
      final first = RunSession(
        id: 'a',
        routeId: 'r',
        startedAt: DateTime.utc(2026),
        simulated: true,
        status: RunStatus.interrupted,
      );
      final second = RunSession(
        id: 'b',
        routeId: 'r',
        startedAt: DateTime.utc(2026),
        simulated: true,
      );
      await repository.createRun(first);
      await expectLater(
        repository.createRun(second),
        throwsA(isA<DatabaseException>()),
      );
      first.status = RunStatus.finished;
      await repository.saveRun(first);
      await repository.createRun(second);
      expect(await repository.listRuns(), hasLength(2));
    },
  );
}
