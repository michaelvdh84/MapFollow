import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/map_guidance_source.dart';
import 'package:mapfollow/domain/map_guidance.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/navigation.dart';

Map<String, dynamic> node(int id, double lat, double lon) => {
  'type': 'node',
  'id': id,
  'lat': lat,
  'lon': lon,
};
Map<String, dynamic> way(int id, List<int> nodes) => {
  'type': 'way',
  'id': id,
  'nodes': nodes,
  'tags': {'highway': 'path'},
};
Map<String, dynamic> junction() => {
  'elements': [
    node(1, 0, 0),
    node(2, 0, .001),
    node(3, 0, .002),
    node(4, .001, .001),
    node(5, -.001, .001),
    way(10, [1, 2, 3]),
    way(11, [4, 2, 5]),
  ],
};
Route trace(List<RoutePoint> points, {List<NavigationCue> cues = const []}) =>
    Route(
      id: 'synthetic',
      name: 'Synthétique',
      segments: [RouteSegment(points)],
      cues: cues,
    );

void main() {
  test('shared topology gives a straight instruction at an intersection', () {
    final route = trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]);
    final result = const OsmGuidanceBuilder().prepare(route, junction());
    expect(result.segments, route.segments);
    expect(result.cues.single.direction, CueDirection.straight);
    expect(result.cues.single.origin, CueOrigin.openStreetMap);
    expect(result.cues.single.routeDistance, closeTo(111.2, .1));
    expect(result.mapPreparationStatus, MapPreparationStatus.prepared);
  });

  test('left and right come from the selected graph branches', () {
    for (final (latitude, direction) in [
      (.001, CueDirection.left),
      (-.001, CueDirection.right),
    ]) {
      final result = const OsmGuidanceBuilder().prepare(
        trace([
          const RoutePoint(0, 0),
          const RoutePoint(0, .001),
          RoutePoint(latitude, .001),
        ]),
        junction(),
      );
      expect(result.cues.single.direction, direction);
    }
  });

  test('crossing ways with distinct node IDs are not intersections', () {
    final map = {
      'elements': [
        node(1, 0, 0),
        node(2, 0, .001),
        node(3, 0, .002),
        node(4, -.001, .001),
        node(5, 0, .001),
        node(6, .001, .001),
        way(10, [1, 2, 3]),
        way(11, [4, 5, 6]),
      ],
    };
    final result = const OsmGuidanceBuilder().prepare(
      trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]),
      map,
    );
    expect(result.cues, isEmpty);
  });

  test(
    'outback junction instructions retain their distinct ordered passages',
    () {
      final result = const OsmGuidanceBuilder().prepare(
        trace([
          const RoutePoint(0, 0),
          const RoutePoint(0, .002),
          const RoutePoint(0, 0),
        ]),
        junction(),
      );
      expect(result.cues.map((c) => c.direction), [
        CueDirection.straight,
        CueDirection.straight,
        CueDirection.uTurn,
      ]);
      final prepared = PreparedRoute(result);
      final mapCues = prepared.cues
          .where((c) => c.cue.origin == CueOrigin.openStreetMap)
          .toList();
      expect(mapCues.map((c) => c.cue.direction), [
        CueDirection.straight,
        CueDirection.uTurn,
        CueDirection.straight,
      ]);
      expect(mapCues[2].distance, closeTo(333.6, .2));
      expect(mapCues[0].cue.id, isNot(mapCues[2].cue.id));
    },
  );

  test('no map does not fabricate instructions and preserves file cues', () {
    final route = trace(
      [const RoutePoint(0, 0), const RoutePoint(0, .002)],
      cues: [
        const NavigationCue(
          id: 'file',
          point: RoutePoint(0, .001),
          direction: CueDirection.straight,
        ),
      ],
    );
    final result = const OsmGuidanceBuilder().prepare(route, {'elements': []});
    expect(result.mapPreparationStatus, MapPreparationStatus.empty);
    expect(result.cues.single.id, 'file');
    expect(result.mapPreparationMessage, contains('Suivez le tracé'));
    final withMap = const OsmGuidanceBuilder().prepare(route, junction());
    expect(withMap.cues.single.id, 'file');
  });

  test('nearby parallel ways remain ambiguous', () {
    final map = junction();
    (map['elements'] as List).addAll(<Map<String, dynamic>>[
      node(20, .00005, 0),
      node(21, .00005, .001),
      node(22, .00005, .002),
      way(30, [20, 21, 22]),
    ]);
    final result = const OsmGuidanceBuilder().prepare(
      trace([const RoutePoint(.000025, 0), const RoutePoint(.000025, .002)]),
      map,
    );
    expect(result.cues, isEmpty);
    expect(result.mapPreparationStatus, isNot(MapPreparationStatus.prepared));
  });

  test('dense shape nodes on the same connected path are not ambiguous', () {
    final elements = <Map<String, dynamic>>[
      for (var i = 0; i <= 100; i++) node(i + 1, 0, i * .00002),
      node(200, .001, .001),
      way(1000, [for (var i = 0; i <= 100; i++) i + 1]),
      way(1001, [51, 200]),
    ];
    final result = const OsmGuidanceBuilder().prepare(
      trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]),
      {'elements': elements},
    );
    expect(result.cues.single.direction, CueDirection.straight);
    expect(result.mapPreparationStatus, MapPreparationStatus.prepared);
  });

  test(
    'incomplete geometry and close competing branches are marked partial',
    () {
      final map = junction();
      (map['elements'] as List).addAll(<Map<String, dynamic>>[
        node(20, .00008, .002),
        way(21, [2, 20]),
      ]);
      final result = const OsmGuidanceBuilder().prepare(
        trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]),
        map,
      );
      expect(result.cues, isEmpty);
      expect(result.mapPreparationStatus, MapPreparationStatus.partial);
      final incomplete = const OsmGuidanceBuilder().prepare(
        trace([const RoutePoint(0, 0), const RoutePoint(0, .004)]),
        junction(),
      );
      expect(incomplete.mapPreparationStatus, MapPreparationStatus.partial);
    },
  );

  test(
    'metadata and cue origins round-trip, legacy estimated stays geometric',
    () {
      final result = const OsmGuidanceBuilder().prepare(
        trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]),
        junction(),
      );
      final restored = Route.fromJson(
        result.toJson(),
      ).copyWith(name: 'Renommé');
      expect(restored.mapPreparationStatus, result.mapPreparationStatus);
      expect(restored.mapPreparedAt, result.mapPreparedAt);
      expect(restored.cues.single.origin, CueOrigin.openStreetMap);
      expect(restored.cues.single.estimated, isFalse);
      expect(
        restored.cues.single.routeDistance,
        result.cues.single.routeDistance,
      );
      final legacy = result.cues.single.toJson()
        ..remove('origin')
        ..['estimated'] = true;
      expect(NavigationCue.fromJson(legacy).origin, CueOrigin.geometric);
    },
  );

  group('explicit Overpass source', () {
    late Directory cache;
    setUp(() async {
      cache = await Directory.systemTemp.createTemp('mapfollow-osm-test-');
    });
    tearDown(() async {
      await cache.delete(recursive: true);
    });
    final route = trace([const RoutePoint(0, 0), const RoutePoint(0, .002)]);

    test('one bounded corridor request and cache without network', () async {
      var downloads = 0;
      final source = OverpassMapGuidanceSource(
        cacheDirectory: cache,
        download: (uri, query) async {
          downloads++;
          expect(uri.scheme, 'https');
          expect(query, contains('[timeout:25][maxsize:33554432]'));
          expect(query, contains('around:80,'));
          return jsonEncode(junction());
        },
      );
      expect((await source.prepare(route)).cues, hasLength(1));
      expect((await source.prepare(route)).cues, hasLength(1));
      expect(downloads, 1);
      final offline = OverpassMapGuidanceSource(
        cacheDirectory: cache,
        download: (_, _) async => throw const SocketException('offline'),
      );
      expect(
        (await offline.prepare(route)).mapPreparationStatus,
        MapPreparationStatus.prepared,
      );
    });

    test('network error is sanitized and never retried', () async {
      var downloads = 0;
      final source = OverpassMapGuidanceSource(
        cacheDirectory: cache,
        download: (_, _) async {
          downloads++;
          throw const SocketException('secret coordinates in raw OS error');
        },
      );
      await expectLater(
        source.prepare(route),
        throwsA(
          isA<MapGuidanceException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(downloads, 1);
    });

    test('oversized response is rejected and not cached', () async {
      final source = OverpassMapGuidanceSource(
        cacheDirectory: cache,
        download: (_, _) async =>
            'x' * (OverpassMapGuidanceSource.maximumBytes + 1),
      );
      await expectLater(
        source.prepare(route),
        throwsA(isA<MapGuidanceException>()),
      );
      expect(await cache.list().toList(), isEmpty);
    });

    test('invalid cached response triggers one explicit fetch', () async {
      var count = 0;
      final source = OverpassMapGuidanceSource(
        cacheDirectory: cache,
        download: (_, _) async {
          count++;
          return jsonEncode(junction());
        },
      );
      await source.prepare(route);
      final file = (await cache.list().toList()).single as File;
      await file.writeAsString('invalid');
      await source.prepare(route);
      expect(count, 2);
    });

    test(
      'stale cache fetches once and excessive route is blocked before network',
      () async {
        var count = 0;
        final source = OverpassMapGuidanceSource(
          cacheDirectory: cache,
          download: (_, _) async {
            count++;
            return jsonEncode(junction());
          },
        );
        await source.prepare(route);
        final file = (await cache.list().toList()).single as File;
        await file.setLastModified(
          DateTime.now().subtract(const Duration(days: 8)),
        );
        await source.prepare(route);
        expect(count, 2);
        await expectLater(
          source.prepare(
            trace([const RoutePoint(0, 0), const RoutePoint(0, 2)]),
          ),
          throwsA(isA<MapGuidanceException>()),
        );
        expect(count, 2);
      },
    );
  });
}
