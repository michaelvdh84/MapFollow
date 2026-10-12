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
/// complète. La vitesse GNSS scalaire borne les mouvements aberrants et peut
/// contraindre la norme de vitesse lorsqu'une incertitude exploitable existe.
/// La sortie est régularisée quand la mesure de vitesse permet de distinguer
/// déplacement cohérent et bruit important ; les directions viennent des
/// positions, jamais de l'orientation du téléphone.
/// Aucun point n'est émis sans mesure reçue. La précision Android pondère la
/// mesure ; le résultat n'est ni une garantie de précision ni un recalage OSM.
class LocationFilter {
  static const version = 'kalman-passive-3';
  static const gap = Duration(seconds: 10);
  RoutePoint? _origin;
  LocationFix? _previousRaw;
  RoutePoint? _lastPoint;
  _Kalman2D? _state;
  RoutePoint? _stationaryAnchor;
  var _stationaryCount = 0;
  DateTime? _stationarySince;
  (double, double)? _previousInnovation;
  DateTime? _reactiveUntil;
  DateTime? _curvingUntil, _lateralSince;
  final List<LocationFix> _motionWindow = [];
  var _regularizationActive = false;

  void reset() {
    _origin = null;
    _previousRaw = null;
    _lastPoint = null;
    _state = null;
    _stationaryAnchor = null;
    _stationaryCount = 0;
    _stationarySince = null;
    _previousInnovation = null;
    _reactiveUntil = null;
    _curvingUntil = null;
    _lateralSince = null;
    _motionWindow.clear();
    _regularizationActive = false;
  }

  FilteredLocation process(LocationFix raw, {required DateTime now}) {
    // Valider avant de toucher à l'état : une mesure refusée ne décale ni le
    // temps du filtre ni son origine, même si son horodatage est très éloigné.
    final invalid = LocationQuality.rejectionReason(raw, now: now);
    if (invalid != null) return FilteredLocation(null, invalid);
    final previous = _previousRaw;
    if (previous != null &&
        (!raw.timestamp.isAfter(previous.timestamp) ||
            raw.intervalSince(previous) <= Duration.zero)) {
      return const FilteredLocation(null, 'non_monotonic');
    }
    final newSegment = previous != null && raw.intervalSince(previous) > gap;
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
        final seconds = raw.intervalSince(previous).inMicroseconds / 1e6;
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
    final dt = _previousRaw == null
        ? 0.0
        : raw.intervalSince(_previousRaw!).inMicroseconds / 1e6;
    // Les mesures rapprochées partagent du bruit : deux mesures en une seconde
    // ne valent pas deux observations indépendantes. Conserver une information
    // par seconde et un bruit de mouvement par seconde, même à 250/500 ms.
    final cadenceWeight = dt > 0 ? 1 / dt.clamp(.25, 1.0) : 1.0;
    final variance =
        math.pow(math.max(3, raw.accuracy), 2).toDouble() * cadenceWeight;
    final speedUncertainty = raw.speedAccuracy;
    final reliableSpeed =
        _validSpeed(raw.speed) &&
        raw.speed! > .5 &&
        speedUncertainty != null &&
        speedUncertainty.isFinite &&
        speedUncertainty > 0 &&
        speedUncertainty <= 1;
    // Après confirmation par les innovations, deux cordes de plusieurs secondes
    // entretiennent la réponse courbe pour éviter des rattrapages périodiques.
    if (_curvingUntil != null &&
        !raw.timestamp.isAfter(_curvingUntil!) &&
        _continuesCurve(raw)) {
      _curvingUntil = raw.timestamp.add(const Duration(seconds: 2));
    }
    var accelerationVariance =
        _reactiveUntil != null && !raw.timestamp.isAfter(_reactiveUntil!)
        ? 9.0
        : _curvingUntil != null && !raw.timestamp.isAfter(_curvingUntil!)
        ? 1.0
        : reliableSpeed
        ? .01
        : .0625;
    (double, double)? innovation;
    var lateralCoherent = false;
    if (_state != null) {
      final dx = x - _state!.predictedPosition(0, dt);
      final dy = y - _state!.predictedPosition(2, dt);
      final residual = math.sqrt(dx * dx + dy * dy);
      final allowance = math.max(
        12 * dt,
        3 *
            math.sqrt(
              variance +
                  _state!.predictedVariance(
                    0,
                    dt,
                    accelerationVariance * cadenceWeight,
                  ) +
                  _state!.predictedVariance(
                    2,
                    dt,
                    accelerationVariance * cadenceWeight,
                  ),
            ),
      );
      if (residual > allowance) {
        return const FilteredLocation(null, 'innovation_outlier');
      }
      // Deux innovations importantes et cohérentes sont nécessaires : une
      // oscillation isolée ne doit pas déclencher un suivi très réactif du bruit.
      if (residual > math.max(3, raw.accuracy)) {
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
              angleDifference(predictedHeading, motionHeading).abs() >= 60;
          final scalarSpeed = raw.speed;
          final compatibleMotion =
              !_validSpeed(scalarSpeed) ||
              (displacement / dt - scalarSpeed!).abs() <= 1;
          final coherent =
              (last.$1 * dx + last.$2 * dy) / (previousLength * residual) >=
              .85;
          final baseline = _motionWindow.firstOrNull;
          final windowSeconds = baseline == null
              ? 0.0
              : raw.timestamp.difference(baseline.timestamp).inMilliseconds /
                    1000;
          final compatibleWindow =
              windowSeconds >= 2 &&
              (!_validSpeed(scalarSpeed) ||
                  (distanceBetween(baseline!.point, raw.point) / windowSeconds -
                              scalarSpeed!)
                          .abs() <=
                      1);
          final lateral = predictedSpeed < .5
              ? 0.0
              : (_state!.values[1] * dy - _state!.values[3] * dx).abs() /
                    predictedSpeed;
          lateralCoherent =
              coherent &&
              compatibleWindow &&
              lateral >= math.max(1.5, raw.accuracy * .5);
          if (lateralCoherent) {
            _lateralSince ??= previous!.timestamp;
            if (raw.timestamp.difference(_lateralSince!).inMilliseconds >=
                2000) {
              _curvingUntil = raw.timestamp.add(const Duration(seconds: 2));
              accelerationVariance = math.max(accelerationVariance, 1);
            }
          }
          if (turning && compatibleMotion && coherent) {
            accelerationVariance = 9;
            // Laisser deux secondes à la vitesse interne pour suivre le virage
            // confirmé ; une seule correction de position garde du retard.
            _reactiveUntil = raw.timestamp.add(const Duration(seconds: 2));
          }
        }
      }
    }
    if (!lateralCoherent) _lateralSince = null;

    // Une vitesse absente n'est jamais interprétée comme une immobilité.
    final speed = raw.speed;
    final speedAccuracy = raw.speedAccuracy;
    final stopped =
        speed != null &&
        speed.isFinite &&
        speed >= 0 &&
        speed <= .5 &&
        (speedAccuracy == null ||
            (speedAccuracy.isFinite &&
                speedAccuracy >= 0 &&
                speed + 2 * speedAccuracy <= .5));
    final radius = math.max(3.0, math.min(8.0, raw.accuracy));
    if (stopped) {
      _stationaryAnchor ??= _lastPoint ?? raw.point;
      if (distanceBetween(_stationaryAnchor!, raw.point) <= radius) {
        _stationarySince ??= raw.timestamp;
        _stationaryCount++;
      } else {
        _stationaryAnchor = raw.point;
        _stationaryCount = 1;
        _stationarySince = raw.timestamp;
      }
    } else {
      _stationaryAnchor = null;
      _stationaryCount = 0;
      _stationarySince = null;
    }

    _state ??= _Kalman2D(x, y, variance);
    var measurementGain = 1.0;
    if (dt > 0) {
      _state!.predict(dt, accelerationVariance * cadenceWeight);
      measurementGain = _state!.positionMeasurementGain(variance);
      _state!.observe(x, const [1, 0, 0, 0], variance);
      _state!.observe(y, const [0, 0, 1, 0], variance);
      // Une vitesse GNSS avec incertitude mesurée apporte une contrainte de
      // norme ; sa direction reste celle estimée depuis les positions. Éviter
      // de traiter l'ancien champ sans incertitude comme une vitesse exacte.
      final speed = raw.speed;
      final speedAccuracy = raw.speedAccuracy;
      final vx = _state!.values[1], vy = _state!.values[3];
      final norm = math.sqrt(vx * vx + vy * vy);
      if (reliableSpeed && norm > .5) {
        _state!.observe(
          speed!,
          [0, vx / norm, 0, vy / norm],
          (speedAccuracy! * speedAccuracy + .09) * cadenceWeight,
          expected: norm,
        );
      }
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
    if (_lastPoint != null &&
        dt > 0 &&
        (reliableSpeed || _regularizationActive)) {
      point = _regularizeOutput(
        raw,
        point,
        x: x,
        y: y,
        dt: dt,
        scale: scale,
        measurementGain: measurementGain,
      );
    }
    final stationary =
        _stationaryCount >= 3 &&
        _stationarySince != null &&
        raw.timestamp.difference(_stationarySince!).inMilliseconds >= 2000;
    if (stationary) {
      _reactiveUntil = null;
      _curvingUntil = null;
      _lateralSince = null;
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
    _motionWindow.add(raw);
    while (_motionWindow.length > 64 ||
        (_motionWindow.length > 1 &&
            raw.timestamp
                    .difference(_motionWindow.first.timestamp)
                    .inMilliseconds >
                8000)) {
      _motionWindow.removeAt(0);
    }
    _previousInnovation = stationary ? null : innovation;
    _lastPoint = point;
    return FilteredLocation(
      LocationFix(
        point: point,
        timestamp: raw.timestamp,
        accuracy: raw.accuracy,
        speed: raw.speed,
        heading: raw.heading,
        speedAccuracy: raw.speedAccuracy,
        headingAccuracy: raw.headingAccuracy,
        elapsedRealtimeNanos: raw.elapsedRealtimeNanos,
        receivedElapsedRealtimeNanos: raw.receivedElapsedRealtimeNanos,
        locationStreamId: raw.locationStreamId,
      ),
      stationary ? 'stationary' : 'filtered',
      newSegment: newSegment,
    );
  }

  static bool _validSpeed(double? speed) =>
      speed != null && speed.isFinite && speed >= 0 && speed <= 12;

  static bool _usableMotionMeasurement(LocationFix fix) {
    final uncertainty = fix.speedAccuracy;
    return _validSpeed(fix.speed) &&
        uncertainty != null &&
        uncertainty.isFinite &&
        uncertainty > 0 &&
        uncertainty <= 1;
  }

  RoutePoint _regularizeOutput(
    LocationFix raw,
    RoutePoint candidate, {
    required double x,
    required double y,
    required double dt,
    required double scale,
    required double measurementGain,
  }) {
    // Comparer sur plusieurs secondes, pas sur une arête à cadence GPS : le
    // bruit de position peut être beaucoup plus grand que le mouvement reçu.
    final window = [..._motionWindow, raw];
    var rawDistance = 0.0, speedDistance = 0.0;
    var seconds = 0.0, uncertainty = 0.0;
    for (var i = window.length - 1; i >= 1; i--) {
      final a = window[i - 1], b = window[i];
      if (!_usableMotionMeasurement(a) || !_usableMotionMeasurement(b)) {
        // La cohérence doit porter sur des paires récentes et contiguës : ne
        // pas réutiliser une vitesse ancienne à travers un champ manquant.
        break;
      }
      final span = b.timestamp.difference(a.timestamp).inMicroseconds / 1e6;
      rawDistance += distanceBetween(a.point, b.point);
      speedDistance += (a.speed! + b.speed!) * .5 * span;
      seconds += span;
      uncertainty += (a.speedAccuracy! + b.speedAccuracy!) * .5 * span;
    }
    final motionObserved = seconds >= 2;
    if (!motionObserved && !_regularizationActive) return candidate;
    _regularizationActive = true;
    final mismatch = motionObserved
        ? (rawDistance - speedDistance).abs() / seconds
        : 0.0;
    final allowance = motionObserved
        ? math.max(.15, uncertainty / seconds)
        : .15;
    final trust = motionObserved
        ? (2 - mismatch / allowance).clamp(0.0, 1.0)
        : 0.0;
    final origin = _origin!, last = _lastPoint!;
    final px =
        angleDifference(origin.longitude, last.longitude) *
        math.pi /
        180 *
        earthRadius *
        scale;
    final py = (last.latitude - origin.latitude) * math.pi / 180 * earthRadius;
    final dx = x - px, dy = y - py;
    final squared = dx * dx + dy * dy;
    // Le point le plus proche de l'estimation Kalman sur le segment entre la
    // dernière sortie et la mesure. Cette branche n'extrapole pas au-delà de
    // la mesure et ne renormalise pas une distance au compteur Garmin.
    final projectedGain = squared < .000001
        ? 0.0
        : (((_state!.values[0] - px) * dx + (_state!.values[2] - py) * dy) /
                  squared)
              .clamp(0.0, 1.0);
    var gain =
        trust * projectedGain + (1 - trust) * measurementGain.clamp(.02, 1.0);
    // Éviter un retard arbitrairement grand lorsque le gain est faible ; le
    // budget spatial dépend de l'incertitude et du mouvement, pas du parcours.
    final remaining = math.sqrt(squared);
    final motionSpeed = _validSpeed(raw.speed)
        ? raw.speed!
        : math
              .sqrt(
                _state!.values[1] * _state!.values[1] +
                    _state!.values[3] * _state!.values[3],
              )
              .clamp(0.0, 12.0);
    final lagBudget = math.max(2 * raw.accuracy, 2 * motionSpeed);
    if (remaining > lagBudget) {
      gain = math.max(gain, 1 - lagBudget / remaining);
    }
    final sx = px + gain * dx, sy = py + gain * dy;
    // Un bruit très supérieur à l'incertitude de vitesse conserve le filtrage
    // Kalman existant, avec un léger lissage temporel supplémentaire. Le score
    // 3–4 est heuristique, pas une probabilité ni un test d'indépendance GPS.
    final noisyWeight = motionObserved
        ? (mismatch / allowance - 3).clamp(0.0, 1.0)
        : 0.0;
    final noiseGain = 1 - math.exp(-dt / .5);
    final nx = px + noiseGain * (_state!.values[0] - px);
    final ny = py + noiseGain * (_state!.values[2] - py);
    final fx = (1 - noisyWeight) * sx + noisyWeight * nx;
    final fy = (1 - noisyWeight) * sy + noisyWeight * ny;
    return RoutePoint(
      origin.latitude + fy / earthRadius * 180 / math.pi,
      (origin.longitude + fx / (earthRadius * scale) * 180 / math.pi + 540) %
              360 -
          180,
      elevation: raw.point.elevation,
      time: raw.point.time,
      traversal: raw.point.traversal,
    );
  }

  bool _continuesCurve(LocationFix raw) {
    if (_motionWindow.length < 2) return false;
    final first = _motionWindow.first;
    final span =
        raw.timestamp.difference(first.timestamp).inMilliseconds / 1000;
    if (span < 3) return false;
    final midpoint = first.timestamp.add(
      Duration(milliseconds: (span * 500).round()),
    );
    final middle = _motionWindow.firstWhere(
      (f) => !f.timestamp.isBefore(midpoint),
      orElse: () => _motionWindow.last,
    );
    final before =
        middle.timestamp.difference(first.timestamp).inMilliseconds / 1000;
    final after =
        raw.timestamp.difference(middle.timestamp).inMilliseconds / 1000;
    if (before < 1.5 || after < 1.5) return false;
    final a = distanceBetween(first.point, middle.point);
    final b = distanceBetween(middle.point, raw.point);
    final minimum = raw.accuracy.clamp(3.0, 6.0);
    if (a < minimum || b < minimum) return false;
    final speed = raw.speed;
    if (_validSpeed(speed) &&
        ((a / before - speed!).abs() > 1 || (b / after - speed).abs() > 1)) {
      return false;
    }
    final angle = angleDifference(
      bearingBetween(first.point, middle.point),
      bearingBetween(middle.point, raw.point),
    ).abs();
    return angle >= 8 && angle <= 60;
  }
}

/// Covariance symétrique 4×4 pour l'état [est, vitesse est, nord, vitesse nord]. Bruit
/// d'accélération : écart type 0,10 m/s² avec vitesse GNSS fiable, 0,25 m/s²
/// sinon ; 1 m/s² en courbe confirmée et 3 m/s² en virage brusque confirmé.
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

  /// Trace moyenne du gain de position conjoint, avant les deux observations
  /// cartésiennes : le choix d'axe ne doit pas modifier le lissage de sortie.
  double positionMeasurementGain(double variance) {
    final a = covariance[0][0], b = covariance[0][2];
    final c = covariance[2][2];
    final divisor = (a + variance) * (c + variance) - b * b;
    return ((a * (c + variance) + c * (a + variance) - 2 * b * b) /
            (2 * divisor))
        .clamp(0.0, 1.0);
  }

  double predictedPosition(int i, double dt) => values[i] + dt * values[i + 1];
  double predictedVariance(int i, double dt, double acceleration) =>
      covariance[i][i] +
      2 * dt * covariance[i][i + 1] +
      dt * dt * covariance[i + 1][i + 1] +
      acceleration * dt * dt * dt * dt / 4;

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
