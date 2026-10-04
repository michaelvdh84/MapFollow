import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../domain/geo.dart';
import '../domain/models.dart';
import '../domain/navigation.dart';

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
  StreamSubscription<Position>? _subscription;
  StreamController<LocationFix>? _controller;
  @override
  Future<void> prepare() async {
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
        'Le guidage nécessite votre autorisation de localisation précise.',
      );
    }
    if (await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced) {
      throw const LocationAccessException(
        'Activez la position précise pour annoncer les virages.',
      );
    }
  }

  @override
  Stream<LocationFix> get fixes {
    if (_controller != null) return _controller!.stream;
    _controller = StreamController<LocationFix>();
    final LocationSettings settings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 2,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'MapFollow — course en cours',
              notificationText:
                  'GPS et guidage actifs. Touchez pour revenir à la course.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.fitness,
            distanceFilter: 2,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          );
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
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
                speed: position.speed.isFinite
                    ? math.max(0, position.speed)
                    : 0,
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

/// Constant-speed playback over each original segment. Segment gaps are never
/// interpolated. No Android location permission is needed in simulation.
class SimulatedLocationSource implements LocationSource {
  SimulatedLocationSource(
    this.route, {
    this.initialProgress = 0,
    this.metresPerSecond = 3,
  });
  final PreparedRoute route;
  final double initialProgress, metresPerSecond;
  Timer? _timer;
  StreamController<LocationFix>? _controller;
  @override
  Future<void> prepare() async {}
  @override
  Stream<LocationFix> get fixes {
    if (_controller != null) return _controller!.stream;
    _controller = StreamController<LocationFix>();
    var progress = initialProgress;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (route.edges.isEmpty) return;
      final edge = route.edges.firstWhere(
        (e) => e.end >= progress,
        orElse: () => route.edges.last,
      );
      final fraction = ((progress - edge.start) / edge.length)
          .clamp(0, 1)
          .toDouble();
      _controller?.add(
        LocationFix(
          point: interpolate(edge.a, edge.b, fraction),
          timestamp: DateTime.now().toUtc(),
          accuracy: 3,
          speed: metresPerSecond,
          heading: bearingBetween(edge.a, edge.b),
        ),
      );
      if (progress >= route.length) {
        _timer?.cancel();
        _controller?.close();
      } else {
        progress = math.min(route.length, progress + metresPerSecond);
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
