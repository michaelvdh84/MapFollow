import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/geo.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/navigation.dart';

void main() {
  final clock = DateTime.utc(2026, 1, 1);
  Route route(List<RoutePoint> points, {List<NavigationCue> cues = const []}) =>
      Route(
        id: 'test',
        name: 'Synthétique',
        segments: [RouteSegment(points)],
        cues: cues,
      );
  LocationFix fix(
    double lat,
    double lon, {
    int second = 0,
    double accuracy = 3,
  }) => LocationFix(
    point: RoutePoint(lat, lon),
    timestamp: clock.add(Duration(seconds: second)),
    accuracy: accuracy,
    speed: 3,
  );

  test('geodesic lengths and projection use metres', () {
    expect(
      distanceBetween(const RoutePoint(0, 0), const RoutePoint(0, .001)),
      closeTo(111.195, .1),
    );
    final projection = projectToEdge(
      const RoutePoint(.0001, .0005),
      const RoutePoint(0, 0),
      const RoutePoint(0, .001),
    );
    expect(projection.fraction, closeTo(.5, .001));
    expect(projection.distance, closeTo(11.12, .1));
  });
  test('route discontinuities do not add artificial distance or turn cues', () {
    final r = Route(
      id: 'gap',
      name: 'Gap',
      segments: [
        RouteSegment([const RoutePoint(0, 0), const RoutePoint(0, .001)]),
        RouteSegment([const RoutePoint(1, 1), const RoutePoint(1, 1.001)]),
      ],
    );
    expect(PreparedRoute(r).length, closeTo(222.4, .2));
    expect(PreparedRoute(r).cues, isEmpty);
  });
  test('infers left and right and ignores straight lines', () {
    final right = PreparedRoute(
      route([
        const RoutePoint(0, 0),
        const RoutePoint(0, .001),
        const RoutePoint(-.001, .001),
      ]),
    );
    expect(right.cues.single.cue.direction, CueDirection.right);
    final left = PreparedRoute(
      route([
        const RoutePoint(0, 0),
        const RoutePoint(0, .001),
        const RoutePoint(.001, .001),
      ]),
    );
    expect(left.cues.single.cue.direction, CueDirection.left);
    expect(
      PreparedRoute(
        route([
          const RoutePoint(0, 0),
          const RoutePoint(0, .001),
          const RoutePoint(0, .002),
        ]),
      ).cues,
      isEmpty,
    );
  });
  test('explicit cue replaces the nearby geometric estimate', () {
    final r = route(
      [
        const RoutePoint(0, 0),
        const RoutePoint(0, .001),
        const RoutePoint(.001, .001),
      ],
      cues: [
        const NavigationCue(
          id: 'explicit',
          point: RoutePoint(0, .001),
          direction: CueDirection.left,
        ),
      ],
    );
    expect(PreparedRoute(r).cues.single.cue.id, 'explicit');
  });
  test(
    'announces by along-track distance, once, and respects configured distance',
    () {
      final r = PreparedRoute(
        route([
          const RoutePoint(0, 0),
          const RoutePoint(0, .001),
          const RoutePoint(.001, .001),
        ]),
      );
      final consumed = <String>{};
      final engine = NavigationEngine(r, announcedCueIds: consumed);
      expect(engine.update(fix(0, .0007), now: clock).announcement, isNull);
      final warning = engine.update(
        fix(0, .00085, second: 2),
        now: clock.add(const Duration(seconds: 2)),
      );
      expect(warning.announcement, contains('gauche'));
      expect(warning.distanceToCue, closeTo(16.68, .2));
      expect(
        engine
            .update(
              fix(0, .0009, second: 3),
              now: clock.add(const Duration(seconds: 3)),
            )
            .announcement,
        isNull,
      );
      final resumed = NavigationEngine(
        r,
        initialProgress: engine.progress,
        announcedCueIds: consumed,
      );
      expect(
        resumed
            .update(
              fix(0, .0009, second: 4),
              now: clock.add(const Duration(seconds: 4)),
            )
            .announcement,
        isNull,
      );
      final earlier = NavigationEngine(
        r,
        settings: const GuidanceSettings(warningDistance: 50),
      );
      expect(earlier.update(fix(0, .0006), now: clock).announcement, isNotNull);
    },
  );
  test('rejects stale, imprecise, repeated and implausible fixes', () {
    final r = PreparedRoute(
      route([const RoutePoint(0, 0), const RoutePoint(0, .005)]),
    );
    final engine = NavigationEngine(r);
    expect(
      engine.update(fix(0, 0, accuracy: 26), now: clock).accepted,
      isFalse,
    );
    expect(
      engine
          .update(fix(0, 0), now: clock.add(const Duration(seconds: 11)))
          .accepted,
      isFalse,
    );
    expect(engine.update(fix(0, 0), now: clock).gpsReliable, isTrue);
    expect(engine.update(fix(0, 0), now: clock).accepted, isFalse);
    expect(
      engine
          .update(
            fix(0, .003, second: 1),
            now: clock.add(const Duration(seconds: 1)),
          )
          .accepted,
      isFalse,
    );
  });
  test('confirms deviation and return; throttles reminders for 60 seconds', () {
    final engine = NavigationEngine(
      PreparedRoute(route([const RoutePoint(0, 0), const RoutePoint(.005, 0)])),
    );
    final a = engine.update(fix(.0002, .0005), now: clock);
    final b = engine.update(
      fix(.0002, .0005, second: 1),
      now: clock.add(const Duration(seconds: 1)),
    );
    final c = engine.update(
      fix(.0002, .0005, second: 2),
      now: clock.add(const Duration(seconds: 2)),
    );
    expect(a.offRoute, isFalse);
    expect(b.offRoute, isFalse);
    expect(c.offRoute, isTrue);
    expect(c.announcement, contains('hors'));
    expect(
      engine
          .update(
            fix(.0002, .0005, second: 20),
            now: clock.add(const Duration(seconds: 20)),
          )
          .announcement,
      isNull,
    );
    expect(
      engine
          .update(
            fix(.0002, .0005, second: 63),
            now: clock.add(const Duration(seconds: 63)),
          )
          .announcement,
      contains('hors'),
    );
    engine.update(
      fix(.0002, 0, second: 70),
      now: clock.add(const Duration(seconds: 70)),
    );
    final back = engine.update(
      fix(.0002, 0, second: 71),
      now: clock.add(const Duration(seconds: 71)),
    );
    expect(back.offRoute, isFalse);
    expect(back.announcement, contains('retour'));
  });
  test('does not jump to the end of a loop sharing the start point', () {
    final engine = NavigationEngine(
      PreparedRoute(
        route([
          const RoutePoint(0, 0),
          const RoutePoint(.003, 0),
          const RoutePoint(.003, .003),
          const RoutePoint(0, .003),
          const RoutePoint(0, 0),
        ]),
      ),
    );
    expect(engine.update(fix(.0001, 0), now: clock).progress, lessThan(20));
  });
}
