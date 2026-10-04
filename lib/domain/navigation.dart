import 'dart:math' as math;
import 'geo.dart';
import 'models.dart';

class RouteEdge {
  RouteEdge(this.a, this.b, this.start, this.segment)
    : length = distanceBetween(a, b);
  final RoutePoint a, b;
  final double start, length;
  final int segment;
  double get end => start + length;
}

class PositionedCue {
  const PositionedCue(this.cue, this.distance);
  final NavigationCue cue;
  final double distance;
}

class PreparedRoute {
  PreparedRoute(this.route) {
    var total = 0.0;
    for (var s = 0; s < route.segments.length; s++) {
      final points = route.segments[s].points;
      final distances = <double>[total];
      for (var i = 1; i < points.length; i++) {
        final edge = RouteEdge(points[i - 1], points[i], total, s);
        if (edge.length > 0) edges.add(edge);
        total += edge.length;
        distances.add(total);
      }
      // Compare bearings over 20 m on each side, rather than individual noisy
      // GPS edges. Keep only the strongest candidate within a 25 m cluster.
      PositionedCue? candidate;
      for (var i = 1; i + 1 < points.length; i++) {
        if (distances[i] - distances.first < 15 ||
            distances.last - distances[i] < 15) {
          continue;
        }
        final before = _pointAt(
          points,
          distances,
          math.max(distances.first, distances[i] - 20),
        );
        final after = _pointAt(
          points,
          distances,
          math.min(distances.last, distances[i] + 20),
        );
        final turn = angleDifference(
          bearingBetween(before, points[i]),
          bearingBetween(points[i], after),
        );
        if (turn.abs() < 45) continue;
        final cue = PositionedCue(
          NavigationCue(
            id: 'estimated-$s-$i',
            point: points[i],
            estimated: true,
            direction: turn.abs() >= 150
                ? CueDirection.uTurn
                : turn > 0
                ? CueDirection.right
                : CueDirection.left,
            label: turn.abs().toString(),
          ),
          distances[i],
        );
        if (candidate != null && cue.distance - candidate.distance < 25) {
          if (turn.abs() > double.parse(candidate.cue.label!)) candidate = cue;
        } else {
          if (candidate != null) cues.add(candidate);
          candidate = cue;
        }
      }
      if (candidate != null) cues.add(candidate);
    }
    length = total;
    for (final cue in route.cues) {
      RouteEdge? best;
      var closest = double.infinity;
      var fraction = 0.0;
      for (final edge in edges) {
        final projection = projectToEdge(cue.point, edge.a, edge.b);
        if (projection.distance < closest) {
          closest = projection.distance;
          fraction = projection.fraction;
          best = edge;
        }
      }
      if (best != null && closest <= 50) {
        final distance = best.start + best.length * fraction;
        cues.removeWhere(
          (c) => c.cue.estimated && (c.distance - distance).abs() < 25,
        );
        cues.add(PositionedCue(cue, distance));
      }
    }
    cues.sort((a, b) => a.distance.compareTo(b.distance));
  }
  final Route route;
  final List<RouteEdge> edges = [];
  final List<PositionedCue> cues = [];
  late final double length;

  static RoutePoint _pointAt(
    List<RoutePoint> points,
    List<double> distances,
    double target,
  ) {
    var low = 0, high = distances.length - 1;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (distances[middle] <= target) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final length = distances[high] - distances[low];
    return interpolate(
      points[low],
      points[high],
      length == 0 ? 0 : ((target - distances[low]) / length).clamp(0, 1),
    );
  }
}

class NavigationUpdate {
  const NavigationUpdate({
    required this.progress,
    required this.remaining,
    required this.distanceFromRoute,
    required this.gpsReliable,
    this.offRoute = false,
    this.nextCue,
    this.distanceToCue,
    this.announcement,
    this.accepted = true,
  });
  final double progress, remaining, distanceFromRoute;
  final bool gpsReliable, offRoute, accepted;
  final PositionedCue? nextCue;
  final double? distanceToCue;
  final String? announcement;
}

String directionText(CueDirection direction) => switch (direction) {
  CueDirection.left => 'tournez à gauche',
  CueDirection.right => 'tournez à droite',
  CueDirection.straight => 'continuez tout droit',
  CueDirection.uTurn => 'faites demi-tour',
};

/// Tracks an ordered corridor around progress. Global nearest-point matching
/// would jump to a later lap at self-intersections; this deliberately does not
/// reacquire distant sections automatically. Recovery preserves consumed cues.
class NavigationEngine {
  NavigationEngine(
    this.prepared, {
    this.settings = const GuidanceSettings(),
    double initialProgress = 0,
    Set<String>? announcedCueIds,
  }) : progress = initialProgress,
       announcedCueIds = announcedCueIds ?? {};
  final PreparedRoute prepared;
  GuidanceSettings settings;
  final Set<String> announcedCueIds;
  double progress;
  LocationFix? _previous;
  int _outsideCount = 0, _insideCount = 0;
  bool _offRoute = false;
  DateTime? _lastOffRouteWarning;

  NavigationUpdate update(LocationFix fix, {required DateTime now}) {
    final age = now.difference(fix.timestamp);
    final reliable =
        fix.accuracy.isFinite &&
        fix.accuracy >= 0 &&
        fix.accuracy <= 25 &&
        age.inMilliseconds >= -2000 &&
        age.inSeconds <= 10;
    if (!reliable || prepared.edges.isEmpty) {
      _outsideCount = 0;
      _insideCount = 0;
      return _result(false, double.infinity, accepted: false);
    }
    if (_previous != null && !fix.timestamp.isAfter(_previous!.timestamp)) {
      return _result(false, double.infinity, accepted: false);
    }
    final elapsed = _previous == null
        ? 1.0
        : fix.timestamp.difference(_previous!.timestamp).inMilliseconds / 1000;
    final moved = _previous == null
        ? 0.0
        : distanceBetween(_previous!.point, fix.point);
    if (_previous != null &&
        moved > 12 * elapsed + fix.accuracy + _previous!.accuracy) {
      return _result(false, double.infinity, accepted: false);
    }
    // Heading from movement is more stable than compass/GPS heading at rest.
    final heading = _previous != null && moved > 5
        ? bearingBetween(_previous!.point, fix.point)
        : null;
    final forward = math.min(
      500.0,
      math.max(150.0, elapsed * math.max(fix.speed, 3) * 2 + 50),
    );
    RouteEdge? best;
    var offset = double.infinity, matched = progress, score = double.infinity;
    for (final edge in prepared.edges) {
      if (edge.end < progress - 50 || edge.start > progress + forward) continue;
      final projection = projectToEdge(fix.point, edge.a, edge.b);
      final candidateProgress = edge.start + edge.length * projection.fraction;
      final directionPenalty = heading == null
          ? 0.0
          : math.max(
                  0.0,
                  angleDifference(
                        heading,
                        bearingBetween(edge.a, edge.b),
                      ).abs() -
                      60,
                ) *
                .15;
      // Prefer continuity when parallel/crossing edges have comparable offsets.
      final candidateScore =
          projection.distance +
          directionPenalty +
          (candidateProgress - progress).abs() * .03;
      if (candidateScore < score) {
        score = candidateScore;
        best = edge;
        offset = projection.distance;
        matched = candidateProgress;
      }
    }
    _previous = fix;
    if (best == null) return _result(false, double.infinity, accepted: true);
    String? announcement;
    if (offset > settings.offRouteDistance) {
      _outsideCount++;
      _insideCount = 0;
      if (_outsideCount >= 3) {
        _offRoute = true;
        if (_lastOffRouteWarning == null ||
            now.difference(_lastOffRouteWarning!).inSeconds >= 60) {
          announcement = 'Vous êtes hors du parcours. Vérifiez le tracé.';
          _lastOffRouteWarning = now;
        }
      }
    } else {
      _outsideCount = 0;
      if (offset < settings.offRouteDistance * .7) {
        _insideCount++;
        if (_offRoute && _insideCount >= 2) {
          _offRoute = false;
          announcement = 'Vous êtes de retour sur le parcours.';
        }
      } else {
        _insideCount = 0;
      }
      if (!_offRoute) {
        progress = math.max(progress, matched).clamp(0, prepared.length);
      }
    }
    if (!_offRoute && offset <= settings.offRouteDistance) {
      for (final cue in prepared.cues) {
        if (announcedCueIds.contains(cue.cue.id)) continue;
        final ahead = cue.distance - progress;
        if (ahead < -5) {
          announcedCueIds.add(cue.cue.id);
          continue;
        }
        if (ahead <= settings.warningDistance) {
          announcedCueIds.add(cue.cue.id);
          announcement ??= ahead < 5
              ? 'Maintenant, ${directionText(cue.cue.direction)}.'
              : 'Dans ${ahead.round()} mètres, ${directionText(cue.cue.direction)}.';
          break;
        }
        break;
      }
    }
    return _result(true, offset, announcement: announcement);
  }

  NavigationUpdate _result(
    bool reliable,
    double offset, {
    String? announcement,
    bool accepted = true,
  }) {
    PositionedCue? next;
    for (final cue in prepared.cues) {
      if (cue.distance >= progress - 5) {
        next = cue;
        break;
      }
    }
    return NavigationUpdate(
      progress: progress,
      remaining: math.max(0, prepared.length - progress),
      distanceFromRoute: offset,
      gpsReliable: reliable,
      offRoute: _offRoute,
      nextCue: next,
      distanceToCue: next == null
          ? null
          : math.max(0, next.distance - progress),
      announcement: announcement,
      accepted: accepted,
    );
  }
}
