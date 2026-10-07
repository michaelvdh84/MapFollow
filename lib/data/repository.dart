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

  /// Enregistre ensemble la session et, si elle existe, sa route générée.
  /// Une erreur annule les deux écritures pour éviter une course incohérente.
  Future<void> saveRunWithRoute(RunSession session, {Route? route});
  Future<void> appendFix(RunSession session, LocationFix fix, int segment);
  Future<void> appendDiagnostic(String runId, Map<String, dynamic> event);
  Future<List<Map<String, dynamic>>> loadDiagnostics(String runId);
  Future<void> deleteRun(String id, {bool deleteGeneratedRoute = false});
  Future<GuidanceSettings> loadSettings();
  Future<void> saveSettings(GuidanceSettings settings);
  Future<void> close();
}

/// Métadonnées et position acceptée sont écrites ensemble : après un arrêt du
/// processus, la progression récupérée doit correspondre aux points sauvegardés.
class SqliteRunRepository implements RunRepository {
  SqliteRunRepository(this.database);
  final Database database;

  static Future<SqliteRunRepository> open({String? databasePath}) async {
    final db = await openDatabase(
      databasePath ?? path.join(await getDatabasesPath(), 'mapfollow.db'),
      version: 2,
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
        await _createDiagnostics(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createDiagnostics(db);
      },
    );
    return SqliteRunRepository(db);
  }

  static Future<void> _createDiagnostics(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE run_diagnostics (sequence INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL REFERENCES runs(id), data TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX diagnostics_run ON run_diagnostics(run_id, sequence)',
    );
  }

  @override
  Future<void> appendDiagnostic(
    String runId,
    Map<String, dynamic> event,
  ) async {
    await database.insert('run_diagnostics', {
      'run_id': runId,
      'data': jsonEncode(event),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> loadDiagnostics(String runId) async =>
      (await database.query(
            'run_diagnostics',
            where: 'run_id = ?',
            whereArgs: [runId],
            orderBy: 'sequence',
          ))
          .map(
            (r) => Map<String, dynamic>.from(
              jsonDecode(r['data'] as String) as Map,
            ),
          )
          .toList();

  @override
  Future<void> deleteRun(String id, {bool deleteGeneratedRoute = false}) async {
    await database.transaction((txn) async {
      final rows = await txn.query('runs', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Course introuvable.');
      final run = RunSession.fromJson(
        jsonDecode(rows.single['data'] as String) as Map<String, dynamic>,
      );
      if (run.status != RunStatus.finished) {
        throw StateError('Terminez la course avant de la supprimer.');
      }
      final routeId = run.generatedRouteId;
      if (deleteGeneratedRoute && routeId != null) {
        if (routeId != 'recorded-${run.id}') {
          throw StateError(
            'Ce parcours ne peut pas être supprimé avec cette course.',
          );
        }
        final active = await txn.query('runs', where: "status != 'finished'");
        if (active.any(
          (row) =>
              (jsonDecode(row['data'] as String) as Map)['routeId'] == routeId,
        )) {
          throw StateError(
            'Ce parcours est utilisé par une course active ou récupérable.',
          );
        }
        await txn.delete('routes', where: 'id = ?', whereArgs: [routeId]);
      }
      await txn.delete('run_diagnostics', where: 'run_id = ?', whereArgs: [id]);
      await txn.delete('fixes', where: 'run_id = ?', whereArgs: [id]);
      await txn.delete('runs', where: 'id = ?', whereArgs: [id]);
    });
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
  Future<void> saveRunWithRoute(RunSession session, {Route? route}) async {
    // Le même identifiant de parcours permet de réessayer sans créer de doublon.
    await database.transaction((txn) async {
      final updated = await txn.update(
        'runs',
        _row(session),
        where: 'id = ?',
        whereArgs: [session.id],
      );
      if (updated != 1) throw StateError('Course introuvable.');
      if (route != null) {
        await txn.insert('routes', {
          'id': route.id,
          'data': jsonEncode(route.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
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
