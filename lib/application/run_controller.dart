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
import '../domain/location_quality.dart';
import '../domain/recorded_route.dart';
import '../domain/traversal_classifier.dart';
import '../domain/speed_window.dart';

List<domain.Route> _parseRouteFile((String, String) input) =>
    RouteImporter().parse(input.$1, fileName: input.$2);
typedef LocationSourceFactory =
    LocationSource Function(
      PreparedRoute?,
      bool,
      double,
      domain.LocationProfile,
    );

class RunController extends ChangeNotifier {
  RunController({
    required this.repository,
    required this.voice,
    LocationSourceFactory? locationFactory,
    Future<void> Function()? requestNotifications,
  }) : _locationFactory = locationFactory,
       _requestNotifications = requestNotifications ?? _androidNotifications;
  final RunRepository repository;
  final VoiceService voice;
  final LocationSourceFactory? _locationFactory;
  final Future<void> Function() _requestNotifications;
  List<domain.Route> routes = [];
  List<domain.RunSession> history = [];
  domain.Route? selectedRoute;
  PreparedRoute? prepared;
  domain.RunSession? session;
  domain.RunSession? recoverable;
  domain.RunSession? lastFinished;
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
  bool _fixReliable = false;
  domain.LocationFix? _lastQualityFix;
  TraversalClassifier? _traversal;
  final SpeedWindow _speedWindow = SpeedWindow();

  double? get currentSpeedMetresPerSecond {
    if (session?.status == domain.RunStatus.paused) return 0;
    if (!running || !gpsReliable) return null;
    return _speedWindow.average(DateTime.now().toUtc());
  }

  LocationSource _makeSource(
    PreparedRoute? route,
    bool simulated,
    double progress,
    domain.LocationProfile profile,
    domain.RunMode mode,
  ) =>
      _locationFactory?.call(route, simulated, progress, profile) ??
      (simulated
          ? SimulatedLocationSource(
              route!,
              initialProgress: progress,
              returnToStart: mode == domain.RunMode.free,
            )
          : DeviceLocationSource(profile: profile));

  bool get running => session?.status == domain.RunStatus.running;
  domain.LocationFix? get mapFix => _lastQualityFix;
  Future<void> flush() => _pending;
  bool get gpsReliable =>
      _fixReliable &&
      lastFix != null &&
      DateTime.now().difference(lastFix!.timestamp).inMilliseconds <= 10000;
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

  /// Les messages publics ne divulguent ni requêtes SQL ni coordonnées privées.
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
    // Aucun redémarrage automatique du GPS : la reprise reste un choix visible.
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
    _lastQualityFix = null;
    _fixReliable = false;
    _speedWindow.clear();
    navigation = null;
    lastFinished = null;
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
    final changesGuidance =
        value.warningDistance != settings.warningDistance ||
        value.offRouteDistance != settings.offRouteDistance ||
        value.voiceVolume != settings.voiceVolume;
    settings = value;
    _engine?.settings = value;
    // Le profil du prochain départ ne doit pas interrompre l'annonce en cours.
    if (changesGuidance) await voice.stop();
    notifyListeners();
  }

  Future<void> testVoice() async {
    await voice.prepare(settings.voiceVolume);
    await voice.speak('Dans vingt mètres, tournez à gauche.');
  }

  /// Les permissions précèdent l'écriture durable. Un Run libre ne prépare pas la voix.
  Future<void> start({
    required bool simulated,
    domain.RunMode mode = domain.RunMode.guided,
  }) async {
    if (session != null || recoverable != null) {
      throw StateError(
        'Terminez ou reprenez la course en attente avant d’en commencer une autre.',
      );
    }
    if (mode == domain.RunMode.guided &&
        (prepared == null || prepared!.edges.isEmpty)) {
      throw StateError('Importez d’abord un parcours.');
    }
    final sourceRoute = await _routeForSource(mode, simulated);
    final source = _makeSource(
      sourceRoute,
      simulated,
      0,
      settings.locationProfile,
      mode,
    );
    // Refus de permission ou voix manquante : aucune course fantôme en base.
    try {
      await source.prepare();
      if (!simulated) await _requestNotifications();
      if (mode == domain.RunMode.guided) {
        await voice.prepare(settings.voiceVolume);
      }
    } catch (_) {
      await source.stop();
      rethrow;
    }
    final startTime = DateTime.now().toUtc();
    final local = startTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final name = mode == domain.RunMode.free
        ? 'Run libre — ${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}'
        : selectedRoute!.name;
    final run = domain.RunSession(
      id: 'run-${DateTime.now().microsecondsSinceEpoch}',
      routeId: mode == domain.RunMode.guided ? selectedRoute!.id : null,
      mode: mode,
      locationProfile: settings.locationProfile,
      name: simulated ? 'SIMULATION · $name' : name,
      startedAt: startTime,
      simulated: simulated,
    );
    try {
      await repository.createRun(run);
    } catch (_) {
      await source.stop();
      rethrow;
    }
    session = run;
    lastFinished = null;
    _startEngine(source);
  }

  Future<PreparedRoute?> _routeForSource(
    domain.RunMode mode,
    bool simulated,
  ) async {
    if (mode == domain.RunMode.guided) return prepared;
    if (!simulated) return null;
    // La géométrie sert uniquement au faux GPS : ce n'est pas un itinéraire guidé.
    final content = await rootBundle.loadString('assets/demo.gpx');
    return PreparedRoute(
      RouteImporter().parse(content, fileName: 'demo.gpx').first,
    );
  }

  void _startEngine(LocationSource source) {
    final run = session!;
    _source = source;
    _traversal = TraversalClassifier.fromSegments(run.segments);
    _speedWindow.clear();
    _engine = run.mode == domain.RunMode.free
        ? null
        : NavigationEngine(
            prepared!,
            settings: settings,
            initialProgress: run.progress,
            announcedCueIds: run.announcedCueIds,
          );
    _baseSeconds = run.activeSeconds;
    _activeSince = DateTime.now();
    _gpsWarning = false;
    _fixReliable = false;
    _lastQualityFix = null;
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
          // La fin du faux GPS termine aussi la course, après les écritures en attente.
          unawaited(_pending.then((_) => perform(finish)));
        }
      },
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!running) return;
      if (!gpsReliable && lastFix != null && !_gpsWarning) {
        _gpsWarning = true;
        _gapPending = true;
        if (run.mode == domain.RunMode.guided) {
          _say('Signal GPS insuffisant. Guidage suspendu.');
        }
      }
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _consume(domain.LocationFix fix) async {
    if (!running) return;
    final run = session!;
    final previous = domain.RunSession.fromJson(run.toJson());
    final previousQualityFix = _lastQualityFix;
    final segmentLengths = run.segments.map((s) => s.length).toList();
    try {
      await _applyFix(fix);
    } catch (_) {
      // Une écriture échouée ne doit pas laisser de points non sauvegardés sur la carte.
      _lastQualityFix = previousQualityFix;
      _fixReliable = false;
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
      _traversal = TraversalClassifier.fromSegments(run.segments);
      _speedWindow.clear();
      _engine = run.mode == domain.RunMode.free
          ? null
          : NavigationEngine(
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
    final previousQualityFix = _lastQualityFix;
    // Une reprise ouvre un nouveau segment, mais ne remonte jamais dans le temps.
    final previousTimestamp =
        previousQualityFix?.timestamp ??
        run.segments.expand((segment) => segment).lastOrNull?.timestamp;
    final qualityAccepted =
        LocationQuality.accepts(
          fix,
          now: DateTime.now().toUtc(),
          previous: previousQualityFix,
        ) &&
        (previousTimestamp == null || fix.timestamp.isAfter(previousTimestamp));
    // Une position rejetée ne peut pas faire avancer le guidage ni consommer un virage.
    final update = qualityAccepted
        ? _engine?.update(fix, now: DateTime.now().toUtc())
        : null;
    navigation = update;
    lastFix = fix;
    run.activeSeconds = elapsedSeconds;
    _fixReliable =
        qualityAccepted &&
        (update == null || (update.gpsReliable && update.accepted));
    if (update != null) run.progress = update.progress;
    if (!_fixReliable) {
      _gapPending = true;
      if (!_gpsWarning) {
        _gpsWarning = true;
        if (run.mode == domain.RunMode.guided) {
          _say('Signal GPS insuffisant. Guidage suspendu.');
        }
      }
      await repository.saveRun(run);
      notifyListeners();
      return;
    }
    _gpsWarning = false;
    _lastQualityFix = fix;
    _speedWindow.add(fix);
    if (run.mode == domain.RunMode.free &&
        run.simulated &&
        previousQualityFix != null) {
      run.progress += distanceBetween(previousQualityFix.point, fix.point);
    }
    if (_gapPending && run.segments.last.isNotEmpty) run.segments.add([]);
    _gapPending = false;
    final segment = run.segments.last;
    final previous = segment.isEmpty ? null : segment.last;
    final moved = previous == null
        ? 0.0
        : distanceBetween(previous.point, fix.point);
    // Ignorer les petites oscillations à l'arrêt, sans compter les interruptions.
    if (previous == null || moved >= mathRecordingThreshold(fix.accuracy)) {
      if (previous != null &&
          fix.timestamp.difference(previous.timestamp).inMilliseconds > 10000) {
        run.segments.add([]);
      } else {
        run.distance += moved;
      }
      final direction = _traversal!.add(
        fix,
        newSegment: run.segments.last.isEmpty,
        control: run.traversalControl,
      );
      final recordedFix = domain.LocationFix(
        point: fix.point.withTraversal(direction),
        timestamp: fix.timestamp,
        accuracy: fix.accuracy,
        speed: fix.speed,
        heading: fix.heading,
      );
      run.segments.last.add(recordedFix);
      await repository.appendFix(run, recordedFix, run.segments.length - 1);
    } else {
      await repository.saveRun(run);
    }
    if (update?.announcement != null) _say(update!.announcement!);
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
    if (session?.mode != domain.RunMode.free) {
      await voice.stop();
    }
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
      /* Conserver les données en mémoire pour permettre une nouvelle tentative. */
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> pause() async {
    if (!running) return;
    // Arrêter le flux, puis enregistrer les positions déjà reçues avant la pause.
    await _stopTracking();
    await _pending;
    if (!running) return;
    session!.activeSeconds = elapsedSeconds;
    session!.status = domain.RunStatus.paused;
    _activeSince = null;
    await repository.saveRun(session!);
    notifyListeners();
  }

  Future<void> resume() async {
    if (session == null || running) return;
    final source = _makeSource(
      await _routeForSource(session!.mode, session!.simulated),
      session!.simulated,
      session!.progress,
      session!.locationProfile,
      session!.mode,
    );
    try {
      await source.prepare();
      if (!session!.simulated) await _requestNotifications();
      if (session!.mode == domain.RunMode.guided) {
        await voice.prepare(settings.voiceVolume);
      }
    } catch (_) {
      await source.stop();
      rethrow;
    }
    if (session!.segments.last.isNotEmpty) session!.segments.add([]);
    try {
      _startEngine(source);
      await repository.saveRun(session!);
    } catch (_) {
      await _interrupt(
        'Reprise interrompue. Vérifiez l’espace de stockage puis réessayez.',
      );
      rethrow;
    }
  }

  Future<void> recover() async {
    if (recoverable == null) return;
    if (recoverable!.mode == domain.RunMode.guided) {
      final route = routes
          .where((r) => r.id == recoverable!.routeId)
          .firstOrNull;
      if (route == null) {
        throw StateError('Le parcours de cette course est introuvable.');
      }
      selectRoute(route);
    }
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
    await _finalize(recoverable!);
    recoverable = null;
    history = await repository.listRuns();
    notifyListeners();
  }

  /// Sérialiser le choix avec les positions évite de sauvegarder un classement
  /// qui ne correspondrait pas au réglage durable après une panne de stockage.
  Future<void> updateTraversalControl(domain.TraversalControl value) async {
    final run = session;
    if (run == null) return;
    final operation = _pending.then((_) async {
      if (session != run) return;
      final previous = run.traversalControl;
      run.traversalControl = value;
      try {
        await repository.saveRun(run);
      } catch (_) {
        run.traversalControl = previous;
        rethrow;
      }
      if (!_disposed) notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    await operation;
  }

  Future<void> finish() async {
    if (session == null) return;
    final run = session!;
    run.activeSeconds = elapsedSeconds;
    run.status = domain.RunStatus.interrupted;
    _activeSince = null;
    await _stopTracking();
    // L'interface et la fin de simulation ont déjà vidé la file d'écriture.
    // Attendre cette même file ici bloquerait la finalisation de la simulation.
    await _finalize(run);
    session = null;
    history = await repository.listRuns();
    notifyListeners();
  }

  /// Course et parcours sont validés dans une seule transaction. En cas d'échec,
  /// la session reste récupérable et les points restent disponibles pour réessayer.
  Future<void> _finalize(domain.RunSession run) async {
    final previousStatus = run.status;
    final previousEnd = run.endedAt;
    final previousRouteId = run.generatedRouteId;
    run.status = domain.RunStatus.finished;
    run.endedAt ??= DateTime.now().toUtc();
    final route = run.mode == domain.RunMode.free ? routeFromRun(run) : null;
    run.generatedRouteId = route?.id;
    try {
      await repository.saveRunWithRoute(run, route: route);
    } catch (_) {
      run.status = previousStatus;
      run.endedAt = previousEnd;
      run.generatedRouteId = previousRouteId;
      rethrow;
    }
    routes = await repository.listRoutes();
    lastFinished = run;
  }

  String runName(domain.RunSession run) => run.name.isNotEmpty
      ? run.name
      : routes.where((r) => r.id == run.routeId).firstOrNull?.name ??
            'Course MapFollow';

  domain.Route? generatedRoute(domain.RunSession run) =>
      routes.where((route) => route.id == run.generatedRouteId).firstOrNull;

  Future<void> renameRun(String id, String value) async {
    var name = value.trim();
    if (name.isEmpty || name.length > 120) {
      throw StateError('Choisissez un nom de 1 à 120 caractères.');
    }
    final run = await repository.loadRun(id);
    if (run.status != domain.RunStatus.finished) {
      throw StateError('Terminez la course avant de la renommer.');
    }
    if (run.simulated && !name.startsWith('SIMULATION')) {
      name = 'SIMULATION · $name';
    }
    if (name.length > 120) {
      throw StateError(
        'Le nom, préfixe SIMULATION compris, doit tenir sur 120 caractères.',
      );
    }
    run.name = name;
    final oldRoute = generatedRoute(run);
    final route = oldRoute == null
        ? null
        : domain.Route(
            id: oldRoute.id,
            name: name,
            segments: oldRoute.segments,
            cues: oldRoute.cues,
            sourceFormat: oldRoute.sourceFormat,
          );
    await repository.saveRunWithRoute(run, route: route);
    routes = await repository.listRoutes();
    history = await repository.listRuns();
    if (lastFinished?.id == id) lastFinished = run;
    if (selectedRoute?.id == route?.id && route != null) {
      selectedRoute = route;
      prepared = PreparedRoute(route);
    }
    notifyListeners();
  }

  Future<void> finishAfterPending() async {
    // Couper l'arrivée de nouvelles positions avant de vider la file d'écriture.
    await _stopTracking();
    await _pending;
    await finish();
  }

  Future<void> exportRun(String id) async {
    final run = await repository.loadRun(id);
    final content = GpxExporter().export(run, name: runName(run));
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
