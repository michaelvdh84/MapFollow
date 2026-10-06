import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/models.dart' as domain;
import 'package:mapfollow/presentation/route_map.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  testWidgets(
    'classified imported layers preserve transitions, segments and painter order',
    (tester) async {
      final route = domain.Route(
        id: 'classified',
        name: 'Synthétique',
        segments: [
          domain.RouteSegment(const [
            domain.RoutePoint(
              50,
              4,
              traversal: domain.TraversalDirection.outbound,
            ),
            domain.RoutePoint(
              50,
              4.001,
              traversal: domain.TraversalDirection.outbound,
            ),
            domain.RoutePoint(
              50,
              4,
              traversal: domain.TraversalDirection.returning,
            ),
            domain.RoutePoint(
              50,
              4.001,
              traversal: domain.TraversalDirection.outbound,
            ),
          ]),
          domain.RouteSegment(const [
            domain.RoutePoint(
              50.01,
              4.01,
              traversal: domain.TraversalDirection.returning,
            ),
            domain.RoutePoint(
              50.01,
              4.011,
              traversal: domain.TraversalDirection.returning,
            ),
          ]),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(
              route: route,
              fix: null,
              recorded: const [],
              active: false,
            ),
          ),
        ),
      );
      await tester.pump();
      List<Polyline> lines() =>
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
      expect(lines().length, 4);
      expect(lines().map((p) => p.color), [
        Colors.blue,
        Colors.blue,
        Colors.orange,
        Colors.orange,
      ]);
      expect(lines()[0].strokeWidth, 6);
      expect(lines()[2].strokeWidth, 3);
      expect(lines()[2].pattern.segments, [8, 6]);
      expect(lines()[2].points.first.longitude, 4.001);
      expect(lines()[2].points.last.longitude, 4);
      expect(lines()[3].points.first.latitude, 50.01);
      expect(lines().every((p) => p.points.length == 2), isTrue);
      await tester.tap(find.text('Retour'));
      await tester.pump();
      expect(lines().map((p) => p.color), [Colors.blue, Colors.blue]);
      await tester.tap(find.text('Aller'));
      await tester.pump();
      expect(lines(), isEmpty);
      expect(find.text('© OpenStreetMap contributors · ODbL'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'guided classified route stays green while recorded directions have independent layers',
    (tester) async {
      final route = domain.Route(
        id: 'generated',
        name: 'Synthétique',
        segments: [
          domain.RouteSegment(const [
            domain.RoutePoint(
              50,
              4,
              traversal: domain.TraversalDirection.outbound,
            ),
            domain.RoutePoint(
              50,
              4.001,
              traversal: domain.TraversalDirection.returning,
            ),
          ]),
        ],
      );
      domain.LocationFix fix(double lon, domain.TraversalDirection direction) =>
          domain.LocationFix(
            point: domain.RoutePoint(50, lon, traversal: direction),
            timestamp: DateTime.utc(2026),
            accuracy: 3,
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(
              route: route,
              fix: null,
              recorded: [
                [
                  fix(4, domain.TraversalDirection.outbound),
                  fix(4.001, domain.TraversalDirection.outbound),
                  fix(4, domain.TraversalDirection.returning),
                ],
              ],
              active: false,
              plannedRoute: true,
            ),
          ),
        ),
      );
      await tester.pump();
      List<Polyline> lines() =>
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
      expect(lines().map((p) => p.color), [
        const Color(0xff315d47),
        Colors.blue,
        Colors.orange,
      ]);
      await tester.tap(find.text('Aller'));
      await tester.pump();
      await tester.tap(find.text('Retour'));
      await tester.pump();
      expect(lines().single.color, const Color(0xff315d47));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'legacy planned green and unclassified recording orange stay unchanged',
    (tester) async {
      final route = domain.Route(
        id: 'old',
        name: 'Synthétique',
        segments: [
          domain.RouteSegment(const [
            domain.RoutePoint(50, 4),
            domain.RoutePoint(50, 4.001),
          ]),
        ],
      );
      domain.LocationFix fix(double lon) => domain.LocationFix(
        point: domain.RoutePoint(50, lon),
        timestamp: DateTime.utc(2026),
        accuracy: 3,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(
              route: route,
              fix: null,
              recorded: [
                [fix(4), fix(4.0005)],
                [fix(4.001), fix(4.002)],
              ],
              active: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final lines = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines;
      expect(lines.length, 3);
      expect(lines.first.color, const Color(0xff315d47));
      expect(lines.skip(1).every((p) => p.color == Colors.deepOrange), isTrue);
      expect(find.byType(FilterChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
