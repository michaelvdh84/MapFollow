import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/geo.dart';
import '../domain/models.dart';
import '../domain/navigation.dart';

/// GPS réel et démonstration partagent ce contrat : permissions, flux, arrêt.
abstract interface class LocationSource {
  Future<void> prepare();
  Stream<LocationFix> get fixes;
  Future<void> stop();
}

class LocationAccessException implements Exception {
  const LocationAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DeviceLocationSource implements LocationSource {
  DeviceLocationSource({this.profile = LocationProfile.precise});
  final LocationProfile profile;
  StreamSubscription<Position>? _subscription;
  StreamController<LocationFix>? _controller;

  /// Cadences demandées à Android ; le système reste maître des livraisons.
  LocationSettings get profileSettings {
    final distance = switch (profile) {
      LocationProfile.precise => 0,
      LocationProfile.balanced => 3,
      LocationProfile.autonomy => 5,
    };
    final accuracy = profile == LocationProfile.precise
        ? LocationAccuracy.bestForNavigation
        : LocationAccuracy.high;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distance,
        intervalDuration: Duration(
          seconds: switch (profile) {
            LocationProfile.precise => 1,
            LocationProfile.balanced => 2,
            LocationProfile.autonomy => 5,
          },
        ),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MapFollow — course en cours',
          notificationText:
              'GPS et enregistrement actifs. Touchez pour revenir à la course.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    // iOS reste à valider ; aucune cadence périodique n'est promise ici.
    return AppleSettings(
      accuracy: LocationAccuracy.best,
      activityType: ActivityType.fitness,
      distanceFilter: distance,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }

  static double? normalizeSpeed(double speed) =>
      speed.isFinite && speed >= 0 ? speed : null;
  @override
  Future<void> prepare() async {
    // À appeler depuis un bouton visible, avant de lancer le service Android.
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationAccessException(
        'Le GPS est désactivé. Activez la localisation dans les réglages du téléphone.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationAccessException(
        'Localisation refusée. Autorisez MapFollow dans les paramètres des applications.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationAccessException(
        'La course nécessite votre autorisation de localisation précise.',
      );
    }
    if (await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced) {
      throw const LocationAccessException(
        'Activez la position précise pour enregistrer la course et guider les virages.',
      );
    }
  }

  @override
  Stream<LocationFix> get fixes {
    if (_controller != null) return _controller!.stream;
    _controller = StreamController<LocationFix>();
    _subscription =
        Geolocator.getPositionStream(locationSettings: profileSettings).listen(
          (position) {
            _controller?.add(
              LocationFix(
                point: RoutePoint(
                  position.latitude,
                  position.longitude,
                  elevation: position.altitudeAccuracy > 0
                      ? position.altitude
                      : null,
                ),
                timestamp: position.timestamp,
                accuracy: position.accuracy,
                speed: normalizeSpeed(position.speed),
                heading: position.heading >= 0 ? position.heading : null,
              ),
            );
          },
          onError: (Object error, StackTrace stack) {
            _controller?.addError(error, stack);
          },
        );
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }
}

/// Lecture à vitesse constante du tracé synthétique, sans permissions Android.
/// Les segments de la source ne sont jamais reliés par une interpolation.
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource(
    this.route, {
    this.initialProgress = 0,
    this.metresPerSecond = 3,
    this.returnToStart = false,
  });
  final PreparedRoute route;
  final double initialProgress, metresPerSecond;
  final bool returnToStart;
  double get totalLength => route.length * (returnToStart ? 2 : 1);

  /// L'aller-retour inverse les arêtes existantes, jamais les vides entre segments.
  LocationFix fixAt(double progress, {required DateTime timestamp}) {
    final returning = returnToStart && progress > route.length;
    final sourceProgress = returning ? totalLength - progress : progress;
    final edge = route.edges.firstWhere(
      (edge) => edge.end >= sourceProgress,
      orElse: () => route.edges.last,
    );
    final fraction = ((sourceProgress - edge.start) / edge.length)
        .clamp(0, 1)
        .toDouble();
    var point = interpolate(edge.a, edge.b, fraction);
    if (returnToStart) {
      point = point.withTraversal(
        returning ? TraversalDirection.returning : TraversalDirection.outbound,
      );
    }
    return LocationFix(
      point: point,
      timestamp: timestamp,
      accuracy: 3,
      speed: metresPerSecond,
      heading: returning
          ? bearingBetween(edge.b, edge.a)
          : bearingBetween(edge.a, edge.b),
    );
  }

  Timer? _timer;
  StreamController<LocationFix>? _controller;
  @override
  Future<void> prepare() async {}
  @override
  Stream<LocationFix> get fixes {
    if (_controller != null) return _controller!.stream;
    _controller = StreamController<LocationFix>();
    var progress = initialProgress.clamp(0, totalLength).toDouble();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (route.edges.isEmpty) return;
      _controller?.add(fixAt(progress, timestamp: DateTime.now().toUtc()));
      if (progress >= totalLength) {
        _timer?.cancel();
        _controller?.close();
      } else {
        progress = math.min(totalLength, progress + metresPerSecond);
      }
    });
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _controller?.close();
    _controller = null;
  }
}
