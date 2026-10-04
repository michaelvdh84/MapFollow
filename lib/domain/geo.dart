import 'dart:math' as math;
import 'models.dart';

const earthRadius = 6371000.0;
double _radians(double value) => value * math.pi / 180;

double distanceBetween(RoutePoint a, RoutePoint b) {
  final lat = _radians(b.latitude - a.latitude);
  final lon = _radians(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(_radians(a.latitude)) *
          math.cos(_radians(b.latitude)) *
          math.pow(math.sin(lon / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0, 1)));
}

double bearingBetween(RoutePoint a, RoutePoint b) {
  final lon = _radians(b.longitude - a.longitude);
  final latA = _radians(a.latitude);
  final latB = _radians(b.latitude);
  return math.atan2(
        math.sin(lon) * math.cos(latB),
        math.cos(latA) * math.sin(latB) -
            math.sin(latA) * math.cos(latB) * math.cos(lon),
      ) *
      180 /
      math.pi;
}

double angleDifference(double a, double b) => (b - a + 540) % 360 - 180;

class Projection {
  const Projection(this.fraction, this.distance);
  final double fraction;
  final double distance;
}

/// Local tangent-plane projection: suitable for short trail edges, including
/// longitude wrap-around. Distances along the route remain geodesic.
Projection projectToEdge(RoutePoint point, RoutePoint a, RoutePoint b) {
  final scale = math.cos(_radians((a.latitude + b.latitude) / 2));
  double x(RoutePoint p) =>
      _radians(angleDifference(a.longitude, p.longitude)) * earthRadius * scale;
  double y(RoutePoint p) => _radians(p.latitude - a.latitude) * earthRadius;
  final bx = x(b), by = y(b), px = x(point), py = y(point);
  final lengthSquared = bx * bx + by * by;
  final t = lengthSquared == 0
      ? 0.0
      : ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
  return Projection(
    t,
    math.sqrt(math.pow(px - t * bx, 2) + math.pow(py - t * by, 2)),
  );
}

double routeDistance(Route route) => route.segments.fold(0.0, (total, segment) {
  for (var i = 1; i < segment.points.length; i++) {
    total += distanceBetween(segment.points[i - 1], segment.points[i]);
  }
  return total;
});

RoutePoint interpolate(RoutePoint a, RoutePoint b, double t) => RoutePoint(
  a.latitude + (b.latitude - a.latitude) * t,
  (a.longitude + angleDifference(a.longitude, b.longitude) * t + 540) % 360 -
      180,
  elevation: a.elevation == null || b.elevation == null
      ? null
      : a.elevation! + (b.elevation! - a.elevation!) * t,
);
