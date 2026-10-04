import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../domain/models.dart';

abstract interface class RunRepository {
  Future<List<Route>> listRoutes();
  Future<void> saveRoute(Route route);
  Future<List<RunSession>> listRuns();
  Future<RunSession> loadRun(String id);
  Future<void> createRun(RunSession session);
  Future<void> saveRun(RunSession session);
  Future<void> appendFix(RunSession session, LocationFix fix, int segment);
  Future<GuidanceSettings> loadSettings();
  Future<void> saveSettings(GuidanceSettings settings);
  Future<void> close();
}

/// Metadata and each accepted fix are committed together: a crash must not
/// advance guidance without retaining the corresponding recorded position.
class SqliteRunRepository implements RunRepository {
  SqliteRunRepository(this.database);
  final Database database;

  static Future<SqliteRunRepository> open({String? databasePath}) async {
    final db = await openDatabase(
      databasePath ?? path.join(await getDatabasesPath(), 'mapfollow.db'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE routes (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE runs (id TEXT PRIMARY KEY, status TEXT NOT NULL, data TEXT NOT NULL)',
        );
        await db.execute(
          "CREATE UNIQUE INDEX one_active_run ON runs ((1)) WHERE status != 'finished'",
        );
        await db.execute(
          'CREATE TABLE fixes (sequence INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL REFERENCES runs(id), segment INTEGER NOT NULL, data TEXT NOT NULL)',
        );
        await db.execute('CREATE INDEX fixes_run ON fixes(run_id, sequence)');
        await db.execute(
          'CREATE TABLE settings (id INTEGER PRIMARY KEY, data TEXT NOT NULL)',
        );
      },
    );
    return SqliteRunRepository(db);
  }

  @override
  Future<List<Route>> listRoutes() async =>
      (await database.query('routes', orderBy: 'rowid DESC'))
          .map(
            (row) => Route.fromJson(
              jsonDecode(row['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  @override
  Future<void> saveRoute(Route route) async {
    await database.insert('routes', {
      'id': route.id,
      'data': jsonEncode(route.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<RunSession>> listRuns() async =>
      (await database.query('runs', orderBy: 'rowid DESC'))
          .map(
            (row) => RunSession.fromJson(
              jsonDecode(row['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  @override
  Future<RunSession> loadRun(String id) async {
    final rows = await database.query('runs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Course introuvable.');
    final run = RunSession.fromJson(
      jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
    );
    for (final row in await database.query(
      'fixes',
      where: 'run_id = ?',
      whereArgs: [id],
      orderBy: 'sequence',
    )) {
      final segment = row['segment'] as int;
      while (run.segments.length <= segment) {
        run.segments.add([]);
      }
      run.segments[segment].add(
        LocationFix.fromJson(
          jsonDecode(row['data'] as String) as Map<String, dynamic>,
        ),
      );
    }
    return run;
  }

  Map<String, Object?> _row(RunSession run) => {
    'id': run.id,
    'status': run.status.name,
    'data': jsonEncode(run.toJson()),
  };
  @override
  Future<void> createRun(RunSession session) async {
    await database.insert('runs', _row(session));
  }

  @override
  Future<void> saveRun(RunSession session) async {
    await database.update(
      'runs',
      _row(session),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  @override
  Future<void> appendFix(
    RunSession session,
    LocationFix fix,
    int segment,
  ) async {
    await database.transaction((txn) async {
      await txn.insert('fixes', {
        'run_id': session.id,
        'segment': segment,
        'data': jsonEncode(fix.toJson()),
      });
      await txn.update(
        'runs',
        _row(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
    });
  }

  @override
  Future<GuidanceSettings> loadSettings() async {
    final rows = await database.query('settings', where: 'id = 1');
    return rows.isEmpty
        ? const GuidanceSettings()
        : GuidanceSettings.fromJson(
            jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
          );
  }

  @override
  Future<void> saveSettings(GuidanceSettings settings) async {
    await database.insert('settings', {
      'id': 1,
      'data': jsonEncode(settings.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() => database.close();
}
