import 'dart:math' as math;

import 'geo.dart';
import 'location_quality.dart';
import 'models.dart';

class FilteredLocation {
  const FilteredLocation(this.fix, this.reason, {this.newSegment = false});
  final LocationFix? fix;
  final String reason;
  final bool newSegment;
}

/// Filtre local 2D à vitesse constante : position et vitesse avec covariance
/// complète. La vitesse GNSS scalaire borne les mouvements aberrants ;
/// la direction vient exclusivement des positions.
/// Aucun point n'est émis sans mesure reçue. La précision Android pondère la
/// mesure ; le résultat n'est ni une garantie de précision ni un recalage OSM.
class LocationFilter {
  static const gap = Duration(seconds: 10);
  RoutePoint? _origin;
  LocationFix? _previousRaw;
  RoutePoint? _lastPoint;
  _Kalman2D? _state;
  RoutePoint? _stationaryAnchor;
  var _stationaryCount = 0;
  (double, double)? _previousInnovation;

  void reset() {
    _origin = null;
    _previousRaw = null;
    _lastPoint = null;
    _state = null;
    _stationaryAnchor = null;
    _stationaryCount = 0;
    _previousInnovation = null;
  }

  FilteredLocation process(LocationFix raw, {required DateTime now}) {
    // Valider avant de toucher à l'état : une mesure refusée ne décale ni le
    // temps du filtre ni son origine, même si son horodatage est très éloigné.
    final invalid = LocationQuality.rejectionReason(raw, now: now);
    if (invalid != null) return FilteredLocation(null, invalid);
    final previous = _previousRaw;
    if (previous != null && !raw.timestamp.isAfter(previous.timestamp)) {
      return const FilteredLocation(null, 'non_monotonic');
    }
    final newSegment =
        previous != null && raw.timestamp.difference(previous.timestamp) > gap;
    if (!newSegment) {
      final rejected = LocationQuality.rejectionReason(
        raw,
        now: now,
        previous: previous,
      );
      if (rejected != null) return FilteredLocation(null, rejected);
      final previousSpeed = previous?.speed;
      final speed = raw.speed;
      if (previous != null &&
          _validSpeed(previousSpeed) &&
          _validSpeed(speed)) {
        final seconds =
            raw.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
        // La vitesse GNSS scalaire est indépendante du cap du téléphone.
        // Autoriser 2 m/s² d'accélération et au plus 12 m d'incertitude évite
        // qu'une précision annoncée trop optimiste masque un saut important.
        final allowance =
            math.max(previousSpeed!, speed!) * seconds +
            seconds * seconds +
            (previous.accuracy + raw.accuracy).clamp(6.0, 12.0);
        if (distanceBetween(previous.point, raw.point) > allowance) {
          return const FilteredLocation(null, 'speed_inconsistent');
        }
      }
    }
    if (newSegment) reset();
    _origin ??= raw.point;
    final origin = _origin!;
    final scale = math.max(.000001, math.cos(origin.latitude * math.pi / 180));
    final x =
        angleDifference(origin.longitude, raw.point.longitude) *
        math.pi /
        180 *
        earthRadius *
        scale;
    final y =
        (raw.point.latitude - origin.latitude) * math.pi / 180 * earthRadius;
    final variance = math.pow(math.max(3, raw.accuracy), 2).toDouble();
    final dt = _previousRaw == null
        ? 0.0
        : raw.timestamp.difference(_previousRaw!.timestamp).inMilliseconds /
              1000;
    var accelerationVariance = .0625;
    (double, double)? innovation;
    if (_state != null) {
      final dx = x - _state!.predictedPosition(0, dt);
      final dy = y - _state!.predictedPosition(2, dt);
      final residual = math.sqrt(dx * dx + dy * dy);
      final allowance = math.max(
        12 * dt,
        3 *
            math.sqrt(
              variance +
                  _state!.predictedVariance(0, dt) +
                  _state!.predictedVariance(2, dt),
            ),
      );
      if (residual > allowance) {
        return const FilteredLocation(null, 'innovation_outlier');
      }
      // Deux innovations importantes et cohérentes sont nécessaires : une
      // oscillation isolée ne doit pas déclencher un suivi très réactif du bruit.
      if (residual > math.max(5, raw.accuracy * 1.5)) {
        innovation = (dx, dy);
        if (_previousInnovation case final last?) {
          final previousLength = math.sqrt(
            last.$1 * last.$1 + last.$2 * last.$2,
          );
          final displacement = previous == null
              ? 0.0
              : distanceBetween(previous.point, raw.point);
          final predictedSpeed = math.sqrt(
            _state!.values[1] * _state!.values[1] +
                _state!.values[3] * _state!.values[3],
          );
          final motionHeading = previous == null
              ? 0.0
              : bearingBetween(previous.point, raw.point);
          final predictedHeading =
              math.atan2(_state!.values[1], _state!.values[3]) * 180 / math.pi;
          final turning =
              predictedSpeed >= .5 &&
              angleDifference(predictedHeading, motionHeading).abs() >= 45;
          final scalarSpeed = raw.speed;
          final compatibleMotion =
              !_validSpeed(scalarSpeed) ||
              (displacement / dt - scalarSpeed!).abs() <= 1;
          if (turning &&
              compatibleMotion &&
              (last.$1 * dx + last.$2 * dy) / (previousLength * residual) >=
                  .85) {
            accelerationVariance = 4;
          }
        }
      }
    }

    // Une vitesse absente n'est jamais interprétée comme une immobilité.
    final speed = raw.speed;
    final stopped =
        speed != null && speed.isFinite && speed >= 0 && speed <= .5;
    final radius = math.max(3.0, math.min(8.0, raw.accuracy));
    if (stopped) {
      _stationaryAnchor ??= _lastPoint ?? raw.point;
      if (distanceBetween(_stationaryAnchor!, raw.point) <= radius) {
        _stationaryCount++;
      } else {
        _stationaryAnchor = raw.point;
        _stationaryCount = 1;
      }
    } else {
      _stationaryAnchor = null;
      _stationaryCount = 0;
    }

    _state ??= _Kalman2D(x, y, variance);
    if (dt > 0) {
      _state!.predict(dt, accelerationVariance);
      _state!.observe(x, const [1, 0, 0, 0], variance);
      _state!.observe(y, const [0, 0, 1, 0], variance);
    }
    var point = RoutePoint(
      origin.latitude + _state!.values[2] / earthRadius * 180 / math.pi,
      (origin.longitude +
                  _state!.values[0] / (earthRadius * scale) * 180 / math.pi +
                  540) %
              360 -
          180,
      elevation: raw.point.elevation,
      time: raw.point.time,
      traversal: raw.point.traversal,
    );
    final stationary = _stationaryCount >= 3;
    if (stationary) {
      final anchor = _stationaryAnchor!;
      point = RoutePoint(
        anchor.latitude,
        anchor.longitude,
        elevation: raw.point.elevation,
        time: raw.point.time,
        traversal: raw.point.traversal,
      );
      // Ne pas garder de vitesse Kalman résiduelle pendant l'arrêt.
      _state = _Kalman2D(
        angleDifference(origin.longitude, point.longitude) *
            math.pi /
            180 *
            earthRadius *
            scale,
        (point.latitude - origin.latitude) * math.pi / 180 * earthRadius,
        variance,
      );
    }
    _previousRaw = raw;
    _previousInnovation = stationary ? null : innovation;
    _lastPoint = point;
    return FilteredLocation(
      LocationFix(
        point: point,
        timestamp: raw.timestamp,
        accuracy: raw.accuracy,
        speed: raw.speed,
        heading: raw.heading,
      ),
      stationary ? 'stationary' : 'filtered',
      newSegment: newSegment,
    );
  }

  static bool _validSpeed(double? speed) =>
      speed != null && speed.isFinite && speed >= 0 && speed <= 12;
}

/// Covariance symétrique 4×4 pour l'état [est, vitesse est, nord, vitesse nord]. Bruit
/// d'accélération : écart type 0,25 m/s², porté à 2 m/s² après deux innovations
/// cohérentes dépassant l'incertitude. Cela limite le retard dans les virages.
class _Kalman2D {
  _Kalman2D(double x, double y, double variance)
    : values = [x, 0, y, 0],
      covariance = List.generate(
        4,
        (i) => List.generate(
          4,
          (j) => i == j ? (i.isEven ? variance : 36.0) : 0.0,
        ),
      );
  final List<double> values;
  List<List<double>> covariance;

  double predictedPosition(int i, double dt) => values[i] + dt * values[i + 1];
  double predictedVariance(int i, double dt) =>
      covariance[i][i] +
      2 * dt * covariance[i][i + 1] +
      dt * dt * covariance[i + 1][i + 1] +
      .015625 * dt * dt * dt * dt;

  void predict(double dt, double acceleration) {
    values[0] += dt * values[1];
    values[2] += dt * values[3];
    final transition = [
      [1.0, dt, 0.0, 0.0],
      [0.0, 1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0, dt],
      [0.0, 0.0, 0.0, 1.0],
    ];
    final p = List.generate(
      4,
      (i) => List.generate(4, (j) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          for (var l = 0; l < 4; l++) {
            sum += transition[i][k] * covariance[k][l] * transition[j][l];
          }
        }
        return sum;
      }),
    );
    for (final i in [0, 2]) {
      p[i][i] += acceleration * dt * dt * dt * dt / 4;
      p[i][i + 1] += acceleration * dt * dt * dt / 2;
      p[i + 1][i] += acceleration * dt * dt * dt / 2;
      p[i + 1][i + 1] += acceleration * dt * dt;
    }
    covariance = p;
  }

  void observe(
    double measured,
    List<double> direction,
    double variance, {
    double? expected,
  }) {
    final projection = List.generate(
      4,
      (i) => List.generate(
        4,
        (j) => covariance[i][j] * direction[j],
      ).reduce((a, b) => a + b),
    );
    final divisor =
        variance +
        List.generate(
          4,
          (i) => direction[i] * projection[i],
        ).reduce((a, b) => a + b);
    final innovation =
        measured -
        (expected ??
            List.generate(
              4,
              (i) => direction[i] * values[i],
            ).reduce((a, b) => a + b));
    for (var i = 0; i < 4; i++) {
      values[i] += projection[i] / divisor * innovation;
    }
    covariance = List.generate(
      4,
      (i) => List.generate(
        4,
        (j) => covariance[i][j] - projection[i] * projection[j] / divisor,
      ),
    );
  }
}
