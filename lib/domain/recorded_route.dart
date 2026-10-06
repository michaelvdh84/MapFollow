import 'location_quality.dart';
import 'models.dart';

/// Transforme une course terminée en parcours sans inventer de liaison aux pauses.
/// Un identifiant déterministe rend une nouvelle tentative de sauvegarde idempotente.
Route? routeFromRun(RunSession run) {
  final segments = run.segments
      .map(
        (segment) => RouteSegment(
          segment
              .where((fix) => LocationQuality.hasValidCoordinates(fix.point))
              .map(
                (fix) => RoutePoint(
                  fix.point.latitude,
                  fix.point.longitude,
                  elevation: fix.point.elevation,
                  time: fix.timestamp,
                  traversal: fix.point.traversal,
                ),
              ),
        ),
      )
      .where((segment) => segment.points.isNotEmpty)
      .toList();
  final navigable = segments.any(
    (segment) =>
        segment.points
            .map((point) => '${point.latitude},${point.longitude}')
            .toSet()
            .length >=
        2,
  );
  if (!navigable) return null;
  return Route(
    id: 'recorded-${run.id}',
    name: run.name,
    segments: segments,
    sourceFormat: 'gpx',
  );
}
