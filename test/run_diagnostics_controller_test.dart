import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/application/run_controller.dart';
import 'package:mapfollow/data/battery_source.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';
import 'fakes.dart';

class TestBattery implements BatterySource {
  int reads = 0;
  @override
  Future<BatterySample> read({String event = 'sample'}) async => BatterySample(
    timestamp: DateTime.now().toUtc(),
    levelPercent: 100 - reads++,
    charging: false,
    event: event,
  );
}

class FailingDiagnosticsRepository extends MemoryRepository {
  @override
  Future<void> appendDiagnostic(
    String runId,
    Map<String, dynamic> event,
  ) async {
    throw StateError('Synthetic diagnostic failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'recovery keeps pinned diagnostic mode and marks the missing interval',
    () async {
      final repo = MemoryRepository();
      final battery = TestBattery();
      final first = RunController(
        repository: repo,
        voice: FakeVoice(),
        batterySource: battery,
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) => FakeLocationSource(),
      );
      await first.initialize();
      await first.updateSettings(
        const GuidanceSettings(diagnosticsMode: DiagnosticsMode.diagnostic),
      );
      await first.start(simulated: false, mode: RunMode.free);
      final id = first.session!.id;
      await first.pause();
      await first.updateSettings(const GuidanceSettings());
      await first.shutdown();
      first.dispose();
      final recovered = RunController(
        repository: repo,
        voice: FakeVoice(),
        batterySource: battery,
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) => FakeLocationSource(),
      );
      await recovered.initialize();
      expect(recovered.recoverable!.batteryInterrupted, true);
      await recovered.recover();
      expect(recovered.session!.diagnosticsMode, DiagnosticsMode.diagnostic);
      await recovered.finishAfterPending();
      final run = await repo.loadRun(id);
      expect(run.batteryInterrupted, true);
      expect(run.batterySamples.map((s) => s.event), [
        'start',
        'pause',
        'resume',
        'finish',
      ]);
      expect(await repo.loadDiagnostics(id), isNotEmpty);
      await recovered.shutdown();
      recovered.dispose();
    },
  );
  test(
    'failed telemetry never rolls back an already committed GPS point',
    () async {
      final repo = FailingDiagnosticsRepository()
        ..settings = const GuidanceSettings(
          diagnosticsMode: DiagnosticsMode.diagnostic,
        );
      final source = FakeLocationSource();
      final c = RunController(
        repository: repo,
        voice: FakeVoice(),
        batterySource: TestBattery(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) => source,
      );
      await c.initialize();
      await c.start(simulated: false, mode: RunMode.free);
      source.controller.add(
        LocationFix(
          point: const RoutePoint(0, 0),
          timestamp: DateTime.now().toUtc(),
          accuracy: 3,
          speed: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await c.flush();
      expect(c.session!.status, RunStatus.interrupted);
      final stored = await repo.loadRun(c.session!.id);
      expect(stored.segments.single, hasLength(1));
      expect(c.session!.segments.single, hasLength(1));
      expect(stored.distance, c.session!.distance);
      await c.shutdown();
      c.dispose();
    },
  );
  test(
    'isolated position spike preserves continuous distance and buffered pause fixes',
    () async {
      final repo = MemoryRepository();
      final source = FakeLocationSource();
      final c = RunController(
        repository: repo,
        voice: FakeVoice(),
        batterySource: TestBattery(),
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) => source,
      );
      await c.initialize();
      await c.start(simulated: false, mode: RunMode.free);
      final at = DateTime.now().toUtc().subtract(const Duration(seconds: 3));
      for (final (lon, seconds) in [
        (0.0, 0),
        (.00002, 1),
        (.001, 2),
        (.00006, 3),
      ]) {
        source.controller.add(
          LocationFix(
            point: RoutePoint(0, lon),
            timestamp: at.add(Duration(seconds: seconds)),
            accuracy: 3,
            speed: 2.2,
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.pause();
      final stored = await repo.loadRun(c.session!.id);
      expect(stored.segments, hasLength(1));
      expect(stored.segments.single, hasLength(3));
      expect(stored.distance, greaterThan(5));
      expect(stored.segments.single.last.point.longitude, lessThan(.000065));
      await c.shutdown();
      c.dispose();
    },
  );
  for (final mode in DiagnosticsMode.values) {
    test('$mode persists battery and prospective diagnostic mode', () async {
      final repo = MemoryRepository()
        ..settings = GuidanceSettings(diagnosticsMode: mode);
      final battery = TestBattery();
      final sources = <FakeLocationSource>[];
      final c = RunController(
        repository: repo,
        voice: FakeVoice(),
        batterySource: battery,
        requestNotifications: () async {},
        locationFactory: (_, _, _, _) {
          final source = FakeLocationSource();
          sources.add(source);
          return source;
        },
      );
      await c.initialize();
      await c.start(simulated: false, mode: RunMode.free);
      final id = c.session!.id;
      await c.updateSettings(
        c.settings.copyWith(
          diagnosticsMode: mode == DiagnosticsMode.normal
              ? DiagnosticsMode.diagnostic
              : DiagnosticsMode.normal,
        ),
      );
      final at = DateTime.now().toUtc();
      sources.last.controller.add(
        LocationFix(
          point: const RoutePoint(0, 0),
          timestamp: at,
          accuracy: 5,
          speed: 2,
        ),
      );
      sources.last.controller.add(
        LocationFix(
          point: const RoutePoint(91, 0),
          timestamp: at.add(const Duration(milliseconds: 1)),
          accuracy: double.nan,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await c.flush();
      await c.pause();
      await c.resume();
      await c.finishAfterPending();
      final saved = await repo.loadRun(id);
      expect(saved.diagnosticsMode, mode);
      expect(saved.batterySamples.first.event, 'start');
      expect(saved.batterySamples.last.event, 'finish');
      if (mode == DiagnosticsMode.normal) {
        expect(saved.batterySamples, hasLength(2));
        expect(await repo.loadDiagnostics(id), isEmpty);
      } else {
        expect(saved.batterySamples.map((s) => s.event), [
          'start',
          'pause',
          'resume',
          'finish',
        ]);
        final fixes = (await repo.loadDiagnostics(
          id,
        )).where((d) => d['event'] == 'location').toList();
        expect(fixes, hasLength(2));
        expect(fixes.last['accepted'], false);
        expect((fixes.last['raw'] as Map)['accuracy'], isNull);
      }
      await c.deleteRun(id);
      expect(c.history, isEmpty);
      expect(c.lastFinished, isNull);
      expect(await repo.loadDiagnostics(id), isEmpty);
      await c.shutdown();
      c.dispose();
    });
  }
}
