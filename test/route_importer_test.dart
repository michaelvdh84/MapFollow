import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/route_importer.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('RouteImporter', () {
    final importer = RouteImporter();
    test(
      'imports GPX tracks as separate segments and routes with explicit cues',
      () {
        final routes = importer.parse(
          fixture('route.gpx'),
          fileName: 'route.gpx',
        );
        expect(routes, hasLength(2));
        expect(routes.first.name, 'Sentier & crête');
        expect(routes.first.sourceFormat, 'gpx');
        expect(routes.first.segments, hasLength(2));
        expect(routes.last.cues.single.direction.name, 'left');
      },
    );

    test('imports TCX course and ignores arbitrary course point names', () {
      final route = importer
          .parse(fixture('course.tcx'), fileName: 'course.tcx')
          .single;
      expect(route.segments.single.points, hasLength(2));
      expect(route.cues.single.direction.name, 'left');
      expect(route.cues.single.label, isNull);
    });

    test('imports TCX activities preserving laps as segments', () {
      final route = importer
          .parse(fixture('activity.tcx'), fileName: 'activity.tcx')
          .single;
      expect(route.segments, hasLength(2));
    });

    test('keeps separate TCX course Track elements separated', () {
      const xml =
          '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Courses><Course><Track><Trackpoint><Position><LatitudeDegrees>1</LatitudeDegrees><LongitudeDegrees>1</LongitudeDegrees></Position></Trackpoint><Trackpoint><Position><LatitudeDegrees>1.01</LatitudeDegrees><LongitudeDegrees>1.01</LongitudeDegrees></Position></Trackpoint></Track><Track><Trackpoint><Position><LatitudeDegrees>1.02</LatitudeDegrees><LongitudeDegrees>1.02</LongitudeDegrees></Position></Trackpoint><Trackpoint><Position><LatitudeDegrees>1.03</LatitudeDegrees><LongitudeDegrees>1.03</LongitudeDegrees></Position></Trackpoint></Track></Course></Courses></TrainingCenterDatabase>';
      expect(
        importer.parse(xml, fileName: 'course.tcx').single.segments,
        hasLength(2),
      );
    });

    test('imports PWX sample offsets', () {
      final route = importer
          .parse(fixture('workout.pwx'), fileName: 'workout.pwx')
          .single;
      expect(route.sourceFormat, 'pwx');
      expect(
        route.segments.single.points.last.time,
        DateTime.utc(2024, 1, 1, 0, 0, 30),
      );
    });

    test(
      'imports each PWX workout and leaves invalid or unanchored offsets untimed',
      () {
        const xml =
            '<pwx><workout><title>First</title><sample><timeoffset>NaN</timeoffset><lat>1</lat><lon>1</lon></sample><sample><timeoffset>Infinity</timeoffset><lat>1.01</lat><lon>1.01</lon></sample></workout><workout><title>Second</title><sample><timeoffset>0</timeoffset><lat>2</lat><lon>2</lon></sample><sample><timeoffset>1</timeoffset><lat>2.01</lat><lon>2.01</lon></sample></workout></pwx>';
        final routes = importer.parse(xml, fileName: 'multi.pwx');
        expect(routes.map((route) => route.name), ['First', 'Second']);
        expect(
          routes
              .expand((route) => route.segments)
              .expand((segment) => segment.points)
              .every((point) => point.time == null),
          isTrue,
        );
      },
    );

    test('accepts namespaced GPX and a PWX wrapper', () {
      const gpx =
          '<g:gpx xmlns:g="http://www.topografix.com/GPX/1/1"><g:trk><g:trkseg><g:trkpt lat="1" lon="1"/><g:trkpt lat="1.1" lon="1.1"/></g:trkseg></g:trk></g:gpx>';
      const pwx =
          '<pwx><workout><title>Wrapped</title><time>2024-01-01T00:00:00Z</time><sample><timeoffset>0</timeoffset><lat>1</lat><lon>1</lon></sample><sample><timeoffset>1</timeoffset><lat>1.1</lat><lon>1.1</lon></sample></workout></pwx>';
      expect(
        importer.parse(gpx, fileName: 'track.gpx').single.sourceFormat,
        'gpx',
      );
      expect(importer.parse(pwx, fileName: 'track.pwx').single.name, 'Wrapped');
    });

    test('splits at malformed or absent GPS positions', () {
      const xml =
          '<gpx version="1.1"><trk><trkseg><trkpt lat="1" lon="1"/><trkpt/><trkpt lat="1.1" lon="1.1"/></trkseg></trk></gpx>';
      expect(
        importer.parse(xml, fileName: 'a.gpx').single.segments,
        hasLength(2),
      );
    });

    test('reports malformed XML and files without enough GPS points', () {
      expect(
        () => importer.parse('<gpx>', fileName: 'a.gpx'),
        throwsA(isA<RouteImportException>()),
      );
      expect(
        () => importer.parse(
          '<gpx><trk><trkseg><trkpt lat="1" lon="1"/></trkseg></trk></gpx>',
          fileName: 'a.gpx',
        ),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('rejects unsupported roots, even when the filename ends in .gpx', () {
      expect(
        () => importer.parse('<notgpx/>', fileName: 'track.gpx'),
        throwsA(isA<RouteImportException>()),
      );
      expect(
        () => importer.parse('<gpx xmlns="urn:wrong"/>', fileName: 'track.gpx'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('rejects more than 100,000 XML point records', () {
      final xml = StringBuffer('<gpx><trk><trkseg>');
      for (var i = 0; i < RouteImporter.maxPoints + 1; i++) {
        xml.write('<trkpt lat="0" lon="0"/>');
      }
      xml.write('</trkseg></trk></gpx>');
      expect(
        () => importer.parse(xml.toString(), fileName: 'many.gpx'),
        throwsA(isA<RouteImportException>()),
      );
    });
  });
}
