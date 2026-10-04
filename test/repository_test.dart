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
    'round trips routes, settings, fixes and progress through real SQLite',
    () async {
      await repository.saveRoute(syntheticRoute());
      expect(
        (await repository.listRoutes()).single.segments.single.points.length,
        3,
      );
      await repository.saveSettings(
        const GuidanceSettings(warningDistance: 50, voiceVolume: .6),
      );
      expect((await repository.loadSettings()).warningDistance, 50);
      final run = RunSession(
        id: 'real-db',
        routeId: 'synthetic',
        startedAt: DateTime.utc(2026),
        simulated: false,
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
        point: const RoutePoint(0, .0001),
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
