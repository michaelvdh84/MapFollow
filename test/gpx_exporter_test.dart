import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/gpx_exporter.dart';
import 'package:mapfollow/data/route_importer.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/recorded_route.dart';

void main() {
  test(
    'exports escaped GPX, simulation marker, elevation, timestamps and paused segments',
    () {
      final start = DateTime.utc(2024);
      final session = RunSession(
        id: 'run',
        routeId: 'r',
        startedAt: start,
        simulated: true,
        segments: [
          [
            LocationFix(
              point: const RoutePoint(1, 2, elevation: 3),
              timestamp: start,
              accuracy: 4,
            ),
            LocationFix(
              point: const RoutePoint(1.1, 2.1),
              timestamp: start.add(const Duration(seconds: 1)),
              accuracy: 4,
            ),
          ],
          [
            LocationFix(
              point: const RoutePoint(1.2, 2.2),
              timestamp: start.add(const Duration(minutes: 1)),
              accuracy: 4,
            ),
            LocationFix(
              point: const RoutePoint(1.3, 2.3),
              timestamp: start.add(const Duration(minutes: 2)),
              accuracy: 4,
            ),
          ],
        ],
      );
      final xml = GpxExporter().export(session, name: 'R & D');
      expect(xml, contains('R &amp; D SIMULATION'));
      expect(
        xml,
        contains(
          'xmlns:mf="https://github.com/michaelvdh84/MapFollow/xmlns/1"',
        ),
      );
      expect(
        xml,
        contains(
          '<mf:run mode="guided" activeSeconds="0" distanceMeters="0.0" simulated="true" locationProfile="precise" traversalControl="automatic"/>',
        ),
      );
      expect(xml, contains('<mf:accuracyMeters>4.0</mf:accuracyMeters>'));
      expect(RegExp('<trkseg>').allMatches(xml), hasLength(2));
      expect(xml, contains('<ele>3.0</ele>'));
      final parsed = RouteImporter()
          .parse(xml, fileName: 'roundtrip.gpx')
          .single;
      expect(parsed.segments, hasLength(2));
      expect(parsed.segments.first.points.first.elevation, 3);
      expect(
        parsed.segments.last.points.last.time,
        start.add(const Duration(minutes: 2)),
      );
    },
  );

  test('uses the session name and exports finite extension values as UTC', () {
    final startedAt = DateTime(2024, 1, 1, 1);
    final endedAt = DateTime(2024, 1, 1, 2);
    final session = RunSession(
      id: 'run',
      routeId: 'route',
      startedAt: startedAt,
      simulated: false,
      name: 'A & B',
      activeSeconds: 12,
      distance: 45.5,
      endedAt: endedAt,
      segments: [
        [
          LocationFix(
            point: const RoutePoint(1, 2),
            timestamp: startedAt,
            accuracy: 2.5,
            speed: 3,
            heading: 90,
          ),
          LocationFix(
            point: const RoutePoint(1.1, 2.1),
            timestamp: startedAt.add(const Duration(seconds: 1)),
            accuracy: double.nan,
            speed: double.infinity,
            heading: -1,
          ),
        ],
      ],
    );
    final xml = GpxExporter().export(session);
    expect(xml, contains('<name>A &amp; B</name>'));
    expect(xml, contains('endedAt="${endedAt.toUtc().toIso8601String()}"'));
    expect(
      xml,
      contains('<time>${startedAt.toUtc().toIso8601String()}</time>'),
    );
    expect(
      xml,
      contains('<mf:speedMetersPerSecond>3.0</mf:speedMetersPerSecond>'),
    );
    expect(xml, contains('<mf:headingDegrees>90.0</mf:headingDegrees>'));
    expect(RegExp('<mf:accuracyMeters>').allMatches(xml), hasLength(1));
    expect(RegExp('<mf:speedMetersPerSecond>').allMatches(xml), hasLength(1));
    expect(RegExp('<mf:headingDegrees>').allMatches(xml), hasLength(1));
    expect(xml, isNot(contains('NaN')));
    expect(xml, isNot(contains('Infinity')));
    final parsed = RouteImporter().parse(xml, fileName: 'utc.gpx').single;
    expect(parsed.segments, hasLength(1));
    expect(parsed.segments.single.points, hasLength(2));
  });

  test('rejects empty or single-point tracks with a useful exception', () {
    final session = RunSession(
      id: 'r',
      routeId: 'x',
      startedAt: DateTime.utc(2024),
      simulated: false,
      segments: [
        [
          LocationFix(
            point: const RoutePoint(1, 2),
            timestamp: DateTime.utc(2024),
            accuracy: 1,
          ),
        ],
      ],
    );
    expect(
      () => GpxExporter().export(session),
      throwsA(isA<GpxExportException>()),
    );
  });

  test('round trips traversal across segments and omits unavailable speed', () {
    final start = DateTime.utc(2024);
    final session = RunSession(
      id: 'run',
      startedAt: start,
      simulated: true,
      mode: RunMode.free,
      locationProfile: LocationProfile.autonomy,
      traversalControl: TraversalControl.returning,
      segments: [
        [
          LocationFix(
            point: const RoutePoint(
              1,
              1,
              traversal: TraversalDirection.outbound,
            ),
            timestamp: start,
            accuracy: 3,
          ),
        ],
        [
          LocationFix(
            point: const RoutePoint(
              1,
              1.001,
              traversal: TraversalDirection.returning,
            ),
            timestamp: start.add(const Duration(seconds: 1)),
            accuracy: 3,
            speed: 0,
          ),
        ],
      ],
    );
    final xml = GpxExporter().export(session);
    expect(
      xml,
      contains('locationProfile="autonomy" traversalControl="returning"'),
    );
    expect(RegExp('<mf:speedMetersPerSecond>').allMatches(xml), hasLength(1));
    final route = RouteImporter().parse(xml, fileName: 'synthetic.gpx').single;
    expect(route.segments, hasLength(2));
    expect(
      route.segments.first.points.single.traversal,
      TraversalDirection.outbound,
    );
    expect(
      route.segments.last.points.single.traversal,
      TraversalDirection.returning,
    );
    final recorded = routeFromRun(
      RunSession(
        id: 'long',
        startedAt: start,
        simulated: true,
        segments: [session.segments.expand((segment) => segment).toList()],
      ),
    )!;
    expect(recorded.segments.single.points.map((point) => point.traversal), [
      TraversalDirection.outbound,
      TraversalDirection.returning,
    ]);
  });
}
