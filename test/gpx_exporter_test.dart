import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/gpx_exporter.dart';
import 'package:mapfollow/data/route_importer.dart';
import 'package:mapfollow/domain/models.dart';

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
}
