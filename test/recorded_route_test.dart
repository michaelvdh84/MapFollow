import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/recorded_route.dart';

void main() {
  LocationFix fix(double lat, double lon, int second, {double? elevation}) =>
      LocationFix(
        point: RoutePoint(lat, lon, elevation: elevation),
        timestamp: DateTime.utc(2026, 10, 6, 12, 0, second),
        accuracy: 3,
      );

  test(
    'builds stable navigable route while retaining gaps and GPS metadata',
    () {
      final run = RunSession(
        id: 'synthetic-run',
        routeId: null,
        mode: RunMode.free,
        name: 'Sortie synthétique',
        startedAt: DateTime.utc(2026),
        simulated: false,
        segments: [
          [fix(50, 4, 0, elevation: 12), fix(50, 4.0001, 1, elevation: 13)],
          [fix(50.001, 4.001, 2)],
        ],
      );

      final route = routeFromRun(run)!;
      expect(route.id, 'recorded-synthetic-run');
      expect(route.name, run.name);
      expect(route.segments, hasLength(2));
      expect(route.segments[0].points, hasLength(2));
      expect(route.segments[1].points, hasLength(1));
      expect(route.segments.first.points.first.elevation, 12);
      expect(
        route.segments.first.points.first.time,
        run.segments.first.first.timestamp,
      );
      expect(route.sourceFormat, 'gpx');
    },
  );

  test(
    'keeps singleton segments when another segment makes route navigable',
    () {
      final run = RunSession(
        id: 'mixed',
        startedAt: DateTime.utc(2026),
        simulated: false,
        segments: [
          [fix(50, 4, 0)],
          [fix(50, 4.1, 1), fix(50, 4.2, 2)],
        ],
      );
      expect(
        routeFromRun(run)!.segments.map((segment) => segment.points.length),
        [1, 2],
      );
    },
  );

  test('does not create a route from a too-short or non-navigable run', () {
    final run = RunSession(
      id: 'short',
      startedAt: DateTime.utc(2026),
      simulated: false,
      segments: [
        [fix(50, 4, 0)],
      ],
    );
    expect(routeFromRun(run), isNull);
    expect(
      routeFromRun(
        RunSession(
          id: 'invalid',
          startedAt: DateTime.utc(2026),
          simulated: false,
          segments: [
            [fix(91, 4, 0), fix(92, 4, 1)],
          ],
        ),
      ),
      isNull,
    );
  });

  test('old persisted sessions default to guided with an empty name', () {
    final json =
        RunSession(
            id: 'old',
            routeId: 'source',
            startedAt: DateTime.utc(2026),
            simulated: true,
          ).toJson()
          ..remove('mode')
          ..remove('name')
          ..remove('generatedRouteId');
    final restored = RunSession.fromJson(json);
    expect(restored.mode, RunMode.guided);
    expect(restored.routeId, 'source');
    expect(restored.name, isEmpty);
    expect(restored.generatedRouteId, isNull);
  });
}
