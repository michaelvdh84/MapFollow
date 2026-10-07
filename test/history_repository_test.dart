import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/repository.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  RunSession run(
    String id, {
    RunStatus status = RunStatus.finished,
    String? routeId,
  }) => RunSession(
    id: id,
    startedAt: DateTime.utc(2026),
    simulated: false,
    status: status,
    mode: RunMode.free,
    generatedRouteId: 'recorded-$id',
    routeId: routeId,
  );
  Route route(String id) => Route(
    id: id,
    name: 'SIMULATION',
    segments: [
      RouteSegment(const [RoutePoint(0, 0), RoutePoint(0, .001)]),
    ],
  );

  test(
    'deletion keeps generated route by default and removes all session data',
    () async {
      final repo = await SqliteRunRepository.open(
        databasePath: inMemoryDatabasePath,
      );
      final session = run('a');
      await repo.createRun(session);
      await repo.saveRoute(route('recorded-a'));
      await repo.appendFix(
        session,
        LocationFix(
          point: const RoutePoint(0, 0),
          timestamp: DateTime.utc(2026),
          accuracy: 3,
        ),
        0,
      );
      await repo.appendDiagnostic('a', {'event': 'sample'});
      await repo.deleteRun('a');
      expect(await repo.listRuns(), isEmpty);
      expect(await repo.loadDiagnostics('a'), isEmpty);
      expect(await repo.database.query('fixes'), isEmpty);
      expect((await repo.listRoutes()).single.id, 'recorded-a');
      await repo.close();
    },
  );
  test(
    'active references block route deletion and failed transaction rolls back',
    () async {
      final repo = await SqliteRunRepository.open(
        databasePath: inMemoryDatabasePath,
      );
      await repo.createRun(run('a'));
      await repo.saveRoute(route('recorded-a'));
      await repo.createRun(
        run('active', status: RunStatus.interrupted, routeId: 'recorded-a'),
      );
      await expectLater(
        repo.deleteRun('a', deleteGeneratedRoute: true),
        throwsStateError,
      );
      expect(await repo.listRuns(), hasLength(2));
      expect(await repo.listRoutes(), hasLength(1));
      await expectLater(repo.deleteRun('active'), throwsStateError);
      await repo.saveRun(run('active'));
      await repo.appendDiagnostic('a', {'event': 'sample'});
      await repo.database.execute(
        "CREATE TRIGGER refuse_delete BEFORE DELETE ON runs BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(
        repo.deleteRun('a', deleteGeneratedRoute: true),
        throwsA(isA<DatabaseException>()),
      );
      expect(await repo.listRoutes(), hasLength(1));
      expect(await repo.loadDiagnostics('a'), hasLength(1));
      await repo.database.execute('DROP TRIGGER refuse_delete');
      await repo.deleteRun('a', deleteGeneratedRoute: true);
      expect(await repo.listRoutes(), isEmpty);
      await repo.close();
    },
  );
  test(
    'v1 migration preserves runs, points and explicit balanced setting',
    () async {
      final dir = await Directory.systemTemp.createTemp('mapfollow-migration-');
      final path = '${dir.path}/test.db';
      final session = run('legacy').toJson()
        ..remove('batterySamples')
        ..remove('diagnosticsMode')
        ..remove('batteryInterrupted');
      final old = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE routes (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE runs (id TEXT PRIMARY KEY, status TEXT NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE fixes (sequence INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL REFERENCES runs(id), segment INTEGER NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.insert('runs', {
            'id': 'legacy',
            'status': 'finished',
            'data': jsonEncode(session),
          });
          await db.insert('settings', {
            'id': 1,
            'data': jsonEncode(
              const GuidanceSettings(
                locationProfile: LocationProfile.balanced,
              ).toJson(),
            ),
          });
          await db.insert('fixes', {
            'run_id': 'legacy',
            'segment': 0,
            'data': jsonEncode(
              LocationFix(
                point: const RoutePoint(0, 0),
                timestamp: DateTime.utc(2026),
                accuracy: 3,
              ).toJson(),
            ),
          });
        },
      );
      await old.close();
      final repo = await SqliteRunRepository.open(databasePath: path);
      final recovered = await repo.loadRun('legacy');
      expect(recovered.segments.single, hasLength(1));
      expect(recovered.batterySamples, isEmpty);
      expect(recovered.diagnosticsMode, DiagnosticsMode.normal);
      expect(
        (await repo.loadSettings()).locationProfile,
        LocationProfile.balanced,
      );
      await repo.appendDiagnostic('legacy', {'event': 'sample'});
      expect(await repo.loadDiagnostics('legacy'), hasLength(1));
      await repo.close();
      await dir.delete(recursive: true);
    },
  );
}
