import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/gpx_exporter.dart';
import '../data/location_source.dart';
import '../data/repository.dart';
import '../data/route_importer.dart';
import '../data/voice_service.dart';
import '../domain/geo.dart';
import '../domain/models.dart' as domain;
import '../domain/navigation.dart';

List<domain.Route> _parseRouteFile((String, String) input) =>
    RouteImporter().parse(input.$1, fileName: input.$2);
typedef LocationSourceFactory =
    LocationSource Function(PreparedRoute, bool, double);

class RunController extends ChangeNotifier {
  RunController({
    required this.repository,
    required this.voice,
    LocationSourceFactory? locationFactory,
    Future<void> Function()? requestNotifications,
  }) : _locationFactory =
           locationFactory ??
           ((route, simulated, progress) => simulated
               ? SimulatedLocationSource(route, initialProgress: progress)
               : DeviceLocationSource()),
       _requestNotifications = requestNotifications ?? _androidNotifications;
  final RunRepository repository;
  final VoiceService voice;
  final LocationSourceFactory _locationFactory;
  final Future<void> Function() _requestNotifications;
  List<domain.Route> routes = [];
  List<domain.RunSession> history = [];
  domain.Route? selectedRoute;
  PreparedRoute? prepared;
  domain.RunSession? session;
  domain.RunSession? recoverable;
  domain.GuidanceSettings settings = const domain.GuidanceSettings();
  domain.LocationFix? lastFix;
  NavigationUpdate? navigation;
  bool initialized = false, busy = false;
  String? error;
  String lastAnnouncement = 'Aucune annonce';
  NavigationEngine? _engine;
  LocationSource? _source;
  StreamSubscription<domain.LocationFix>? _subscription;
  Timer? _ticker;
  DateTime? _activeSince;
  int _baseSeconds = 0;
  Future<void> _pending = Future.value();
  bool _gapPending = false, _gpsWarning = false, _disposed = false;

  bool get running => session?.status == domain.RunStatus.running;
  Future<void> flush() => _pending;
  bool get gpsReliable =>
      navigation?.gpsReliable == true &&
      lastFix != null &&
      DateTime.now().difference(lastFix!.timestamp).inSeconds <= 10;
  int get elapsedSeconds => running && _activeSince != null
      ? _baseSeconds + DateTime.now().difference(_activeSince!).inSeconds
      : session?.activeSeconds ?? 0;

  static Future<void> _androidNotifications() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await const MethodChannel(
        'mapfollow/permissions',
      ).invokeMethod<bool>('requestNotifications');
      if (granted != true) {
        throw StateError(
          'Autorisez les notifications de MapFollow pour afficher le suivi pendant la course.',
        );
      }
    }
  }

  /// Errors displayed to the runner never contain SQL payloads or coordinates.
  Future<void> perform(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      error = switch (e) {
        RouteImportException() => e.message,
        GpxExportException() => e.message,
        LocationAccessException() => e.message,
        StateError() => e.message.toString(),
        _ =>
          'L’opération a échoué. Vérifiez les autorisations, le fichier et l’espace de stockage.',
      };
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> initialize() async {
    routes = await repository.listRoutes();
    settings = await repository.loadSettings();
    history = await repository.listRuns();
    for (final run in history) {
      if (run.status != domain.RunStatus.finished) {
        recoverable = await repository.loadRun(run.id);
        recoverable!.status = domain.RunStatus.interrupted;
        await repository.saveRun(recoverable!);
        break;
      }
    }
    if (routes.isNotEmpty) selectRoute(routes.first);
    initialized = true;
    notifyListeners();
  }

  void selectRoute(domain.Route route) {
    if (session != null) return;
    selectedRoute = route;
    prepared = PreparedRoute(route);
    lastFix = null;
    navigation = null;
    notifyListeners();
  }

  Future<List<domain.Route>> pickRoutes() async {
    final file = await FilePicker.pickFile(
      type: FileType.any,
      dialogTitle: 'Choisir un GPX, TCX ou PWX',
    );
    if (file == null) return [];
    if ((await file.length() ?? 0) > RouteImporter.maxInputBytes) {
      throw const RouteImportException(
        'Le fichier dépasse la taille maximale de 10 Mo.',
      );
    }
    final bytes = await file.readAsBytes();
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      throw const RouteImportException(
        'Le fichier doit être un document XML encodé en UTF-8.',
      );
    }
    return compute(_parseRouteFile, (content, file.name));
  }

  Future<void> saveRoute(domain.Route route) async {
    await repository.saveRoute(route);
    routes = await repository.listRoutes();
    selectRoute(route);
  }

  Future<void> loadDemo() async {
    final content = await rootBundle.loadString('assets/demo.gpx');
    final route = RouteImporter().parse(content, fileName: 'demo.gpx').first;
    await saveRoute(route);
  }

  Future<void> updateSettings(domain.GuidanceSettings value) async {
    await repository.saveSettings(value);
    settings = value;
    _engine?.settings = value;
    await voice.stop();
    notifyListeners();
  }

  Future<void> testVoice() async {
    await voice.prepare(settings.voiceVolume);
    await voice.speak('Dans vingt mètres, tournez à gauche.');
  }

  Future<void> start({required bool simulated}) async {
    if (session != null || recoverable != null) {
      throw StateError(
        'Terminez ou reprenez la course en attente avant d’en commencer une autre.',
      );
    }
    if (prepared == null || prepared!.edges.isEmpty) {
      throw StateError('Importez d’abord un parcours.');
    }
    final source = _locationFactory(prepared!, simulated, 0);
    // Permissions and TTS readiness are checked before creating durable state.
    try {
      await source.prepare();
      if (!simulated) await _requestNotifications();
      await voice.prepare(settings.voiceVolume);
    } catch (_) {
      await source.stop();
      rethrow;
    }
    final run = domain.RunSession(
      id: 'run-${DateTime.now().microsecondsSinceEpoch}',
      routeId: selectedRoute!.id,
      startedAt: DateTime.now().toUtc(),
      simulated: simulated,
    );
    try {
      await repository.createRun(run);
    } catch (_) {
      await source.stop();
      rethrow;
    }
    session = run;
    _startEngine(source);
  }

  void _startEngine(LocationSource source) {
    final run = session!;
    _source = source;
    _engine = NavigationEngine(
      prepared!,
      settings: settings,
      initialProgress: run.progress,
      announcedCueIds: run.announcedCueIds,
    );
    _baseSeconds = run.activeSeconds;
    _activeSince = DateTime.now();
    _gpsWarning = false;
    lastFix = null;
    navigation = null;
    run.status = domain.RunStatus.running;
    _subscription = source.fixes.listen(
      (fix) {
        _pending = _pending.then((_) => _consume(fix)).catchError((
          Object _,
        ) async {
          await _interrupt(
            'Enregistrement interrompu. Vérifiez le GPS et l’espace de stockage, puis reprenez la course.',
          );
        });
      },
      onError: (Object _) {
        _pending = _pending.then(
          (_) => _interrupt(
            'Le GPS ne fournit plus de positions. Vérifiez les autorisations puis reprenez la course.',
          ),
        );
      },
      onDone: () {
        if (run.simulated && running) {
          // Completion of the synthetic stream is explicit in the history.
          unawaited(_pending.then((_) => finish()));
        }
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!running) return;
      if (!gpsReliable && lastFix != null && !_gpsWarning) {
        _gpsWarning = true;
        _gapPending = true;
        _say('Signal GPS insuffisant. Guidage suspendu.');
      }
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _consume(domain.LocationFix fix) async {
    if (!running) return;
    final run = session!;
    final previous = domain.RunSession.fromJson(run.toJson());
    final segmentLengths = run.segments.map((s) => s.length).toList();
    try {
      await _applyFix(fix);
    } catch (_) {
      // A failed transaction must not leave unsaved points/progress in memory.
      run.distance = previous.distance;
      run.progress = previous.progress;
      run.announcedCueIds
        ..clear()
        ..addAll(previous.announcedCueIds);
      while (run.segments.length > segmentLengths.length) {
        run.segments.removeLast();
      }
      for (var i = 0; i < segmentLengths.length; i++) {
        run.segments[i].length = segmentLengths[i];
      }
      _engine = NavigationEngine(
        prepared!,
        settings: settings,
        initialProgress: run.progress,
        announcedCueIds: run.announcedCueIds,
      );
      rethrow;
    }
  }

  Future<void> _applyFix(domain.LocationFix fix) async {
    if (!running) return;
    final run = session!;
    final update = _engine!.update(fix, now: DateTime.now().toUtc());
    navigation = update;
    lastFix = fix;
    run.activeSeconds = elapsedSeconds;
    run.progress = update.progress;
    if (!update.gpsReliable || !update.accepted) {
      _gapPending = true;
      if (!_gpsWarning) {
        _gpsWarning = true;
        _say('Signal GPS insuffisant. Guidage suspendu.');
      }
      await repository.saveRun(run);
      notifyListeners();
      return;
    }
    _gpsWarning = false;
    if (_gapPending && run.segments.last.isNotEmpty) run.segments.add([]);
    _gapPending = false;
    final segment = run.segments.last;
    final previous = segment.isEmpty ? null : segment.last;
    final moved = previous == null
        ? 0.0
        : distanceBetween(previous.point, fix.point);
    // Avoid accumulating stationary GPS jitter as running distance.
    if (previous == null || moved >= mathRecordingThreshold(fix.accuracy)) {
      if (previous != null &&
          fix.timestamp.difference(previous.timestamp).inSeconds > 10) {
        run.segments.add([]);
      } else {
        run.distance += moved;
      }
      run.segments.last.add(fix);
      await repository.appendFix(run, fix, run.segments.length - 1);
    } else {
      await repository.saveRun(run);
    }
    if (update.announcement != null) _say(update.announcement!);
    if (!_disposed) notifyListeners();
  }

  static double mathRecordingThreshold(double accuracy) =>
      (accuracy * .3).clamp(3, 8);
  void _say(String text) {
    lastAnnouncement = text;
    unawaited(
      voice.speak(text).catchError((Object _) {
        error =
            'Annonce vocale indisponible. Vérifiez le moteur de synthèse vocale.';
        if (!_disposed) notifyListeners();
        return false;
      }),
    );
  }

  Future<void> _stopTracking() async {
    _ticker?.cancel();
    _ticker = null;
    await _subscription?.cancel();
    _subscription = null;
    await _source?.stop();
    _source = null;
    await voice.stop();
  }

  Future<void> _interrupt(String message) async {
    if (!running) return;
    session!.activeSeconds = elapsedSeconds;
    session!.status = domain.RunStatus.interrupted;
    _activeSince = null;
    _gapPending = true;
    error = message;
    await _stopTracking();
    try {
      await repository.saveRun(session!);
    } catch (_) {
      /* Preserve in-memory data for retry. */
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> pause() async {
    if (!running) return;
    session!.activeSeconds = elapsedSeconds;
    session!.status = domain.RunStatus.paused;
    _activeSince = null;
    await _stopTracking();
    await _pending;
    await repository.saveRun(session!);
    notifyListeners();
  }

  Future<void> resume() async {
    if (session == null || running) return;
    final source = _locationFactory(
      prepared!,
      session!.simulated,
      session!.progress,
    );
    try {
      await source.prepare();
      if (!session!.simulated) await _requestNotifications();
      await voice.prepare(settings.voiceVolume);
    } catch (_) {
      await source.stop();
      rethrow;
    }
    if (session!.segments.last.isNotEmpty) session!.segments.add([]);
    _startEngine(source);
    await repository.saveRun(session!);
  }

  Future<void> recover() async {
    if (recoverable == null) return;
    final route = routes.where((r) => r.id == recoverable!.routeId).firstOrNull;
    if (route == null) {
      throw StateError('Le parcours de cette course est introuvable.');
    }
    selectRoute(route);
    session = recoverable;
    recoverable = null;
    session!.status = domain.RunStatus.interrupted;
    try {
      await resume();
    } catch (_) {
      notifyListeners();
      rethrow;
    }
  }

  Future<void> closeRecovery() async {
    if (recoverable == null) return;
    recoverable!.status = domain.RunStatus.finished;
    recoverable!.endedAt = DateTime.now().toUtc();
    await repository.saveRun(recoverable!);
    recoverable = null;
    history = await repository.listRuns();
    notifyListeners();
  }

  Future<void> finish() async {
    if (session == null) return;
    final run = session!;
    run.activeSeconds = elapsedSeconds;
    run.status = domain.RunStatus.finished;
    run.endedAt = DateTime.now().toUtc();
    _activeSince = null;
    await _stopTracking();
    // The caller/UI drains _pending before finish. A simulator onDone runs
    // finish after that queue itself, so finish must not await the same queue.
    await repository.saveRun(run);
    session = null;
    history = await repository.listRuns();
    notifyListeners();
  }

  Future<void> finishAfterPending() async {
    await _pending;
    await finish();
  }

  Future<void> exportRun(String id) async {
    final run = await repository.loadRun(id);
    final route = routes.where((r) => r.id == run.routeId).firstOrNull;
    final content = GpxExporter().export(
      run,
      name: route?.name ?? 'Course MapFollow',
    );
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/mapfollow-${run.id}.gpx');
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/gpx+xml')],
        title: 'Exporter la course GPX',
      ),
    );
  }

  void dismissError() {
    error = null;
    notifyListeners();
  }

  Future<void> shutdown() async {
    if (running) {
      await pause();
    } else {
      await _stopTracking();
    }
    await _pending;
    await repository.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_source?.stop());
    unawaited(voice.stop());
    super.dispose();
  }
}
