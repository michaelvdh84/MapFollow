import 'dart:async';
import 'package:mapfollow/data/location_source.dart';
import 'package:mapfollow/data/repository.dart';
import 'package:mapfollow/data/voice_service.dart';
import 'package:mapfollow/domain/models.dart';

class MemoryRepository implements RunRepository {
  final routes = <String, Route>{};
  final runs = <String, Map<String, dynamic>>{};
  final points = <String, List<(int, LocationFix)>>{};
  GuidanceSettings settings = const GuidanceSettings();
  bool failWrites = false;
  @override
  Future<void> saveRoute(Route route) async {
    routes[route.id] = route;
  }

  @override
  Future<List<Route>> listRoutes() async => routes.values.toList();
  @override
  Future<List<RunSession>> listRuns() async =>
      runs.values.map(RunSession.fromJson).toList();
  @override
  Future<RunSession> loadRun(String id) async {
    final run = RunSession.fromJson(runs[id]!);
    for (final (index, fix) in points[id] ?? <(int, LocationFix)>[]) {
      while (run.segments.length <= index) {
        run.segments.add([]);
      }
      run.segments[index].add(fix);
    }
    return run;
  }

  @override
  Future<void> createRun(RunSession session) async {
    if (runs.values.any((r) => r['status'] != 'finished')) {
      throw StateError('Une course est déjà active.');
    }
    await saveRun(session);
  }

  @override
  Future<void> saveRun(RunSession session) async {
    if (failWrites) throw StateError('Synthetic disk failure');
    runs[session.id] = session.toJson();
  }

  @override
  Future<void> appendFix(
    RunSession session,
    LocationFix fix,
    int segment,
  ) async {
    await saveRun(session);
    (points[session.id] ??= []).add((segment, fix));
  }

  @override
  Future<GuidanceSettings> loadSettings() async => settings;
  @override
  Future<void> saveSettings(GuidanceSettings value) async {
    settings = value;
  }

  @override
  Future<void> close() async {}
}

class FakeLocationSource implements LocationSource {
  final controller = StreamController<LocationFix>.broadcast();
  Exception? preparationError;
  bool stopped = false;
  @override
  Future<void> prepare() async {
    if (preparationError != null) throw preparationError!;
  }

  @override
  Stream<LocationFix> get fixes => controller.stream;
  @override
  Future<void> stop() async {
    stopped = true;
    await controller.close();
  }
}

class FakeVoice implements VoiceService {
  final announcements = <String>[];
  int stopped = 0;
  @override
  Future<void> prepare(double volume) async {}
  @override
  Future<bool> speak(String text) async {
    announcements.add(text);
    return true;
  }

  @override
  Future<void> stop() async {
    stopped++;
  }
}

Route syntheticRoute() => Route(
  id: 'synthetic',
  name: 'Test synthétique',
  segments: [
    RouteSegment([
      const RoutePoint(0, 0),
      const RoutePoint(0, .001),
      const RoutePoint(.001, .001),
    ]),
  ],
);
