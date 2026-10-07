import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/geo.dart';
import 'package:mapfollow/domain/location_filter.dart';
import 'package:mapfollow/domain/models.dart';

final epoch = DateTime.utc(2026, 1, 1);
LocationFix fix(
  double x,
  double y,
  int seconds, {
  double accuracy = 8,
  double? speed = 3,
  double? heading = 90,
}) => LocationFix(
  point: RoutePoint(
    y / earthRadius * 180 / math.pi,
    x / earthRadius * 180 / math.pi,
    elevation: 42,
  ),
  timestamp: epoch.add(Duration(seconds: seconds)),
  accuracy: accuracy,
  speed: speed,
  heading: heading,
);
FilteredLocation feed(LocationFilter filter, LocationFix raw) =>
    filter.process(raw, now: raw.timestamp);
double length(List<LocationFix> points) => [
  for (var i = 1; i < points.length; i++)
    distanceBetween(points[i - 1].point, points[i].point),
].fold(0, (a, b) => a + b);

void main() {
  test(
    'weighted Kalman reduces synthetic straight line noise and distance',
    () {
      final filter = LocationFilter();
      final raw = [
        for (var i = 0; i <= 240; i++) fix(i * 3.0, 5 * math.sin(i * 1.7), i),
      ];
      final processed = raw.map((p) => feed(filter, p).fix!).toList();
      double error(List<LocationFix> list) => list.fold(
        0.0,
        (sum, p) => sum + p.point.latitude.abs() * earthRadius * math.pi / 180,
      );
      expect(error(processed), lessThan(error(raw) * .75));
      expect(length(processed), lessThan(length(raw) * .8));
      expect(length(processed), closeTo(720, 35));
      expect(processed.last.speed, raw.last.speed);
      expect(processed.last.heading, raw.last.heading);
      expect(processed.last.point.elevation, 42);
    },
  );

  test('invalid fixes and jumps do not corrupt time or state', () {
    final filter = LocationFilter();
    final reference = LocationFilter();
    feed(filter, fix(0, 0, 0));
    feed(reference, fix(0, 0, 0));
    expect(feed(filter, fix(1000, 0, 1)).reason, 'implausible_jump');
    expect(feed(filter, fix(1, 0, 0)).reason, 'non_monotonic');
    expect(feed(filter, fix(1, 0, 30, accuracy: 100)).fix, isNull);
    final filtered = feed(filter, fix(6, 0, 2));
    final expected = feed(reference, fix(6, 0, 2));
    expect(filtered.fix!.point.longitude, expected.fix!.point.longitude);
    expect(filtered.newSegment, isFalse);
  });

  test(
    'stationary speed suppresses drift without treating missing speed as zero',
    () {
      final filter = LocationFilter();
      final list = [
        for (var i = 0; i < 60; i++)
          feed(
            filter,
            fix(
              2 * math.sin(i.toDouble()),
              2 * math.cos(i.toDouble()),
              i,
              speed: 0,
            ),
          ).fix!,
      ];
      expect(length(list.skip(3).toList()), closeTo(0, .001));
      final moving = feed(filter, fix(10, 2, 60, speed: 3)).fix!;
      expect(distanceBetween(list.last.point, moving.point), greaterThan(4));
      final unknown = LocationFilter();
      final last = feed(unknown, fix(0, 0, 0, speed: null)).fix!;
      final next = feed(unknown, fix(3, 0, 1, speed: null)).fix!;
      expect(next.speed, isNull);
      expect(distanceBetween(last.point, next.point), greaterThan(1));
    },
  );

  test(
    'sharp corners and U-turns follow measurements without extrapolated fixes',
    () {
      final filter = LocationFilter();
      for (var i = 0; i < 20; i++) {
        expect(feed(filter, fix(i * 3.0, 0, i, accuracy: 3)).fix, isNotNull);
      }
      for (var i = 20; i < 40; i++) {
        final raw = fix(57, (i - 19) * 3.0, i, accuracy: 3);
        final result = feed(filter, raw);
        expect(result.fix, isNotNull);
        expect(distanceBetween(raw.point, result.fix!.point), lessThan(7));
      }
      for (var i = 40; i < 60; i++) {
        final raw = fix(57, (59 - i) * 3.0, i, accuracy: 3);
        final result = feed(filter, raw);
        expect(result.fix, isNotNull);
        expect(distanceBetween(raw.point, result.fix!.point), lessThan(7));
      }
    },
  );

  test(
    'GPS gaps and explicit reset start fresh segments without joining space',
    () {
      final filter = LocationFilter();
      feed(filter, fix(0, 0, 0));
      feed(filter, fix(3, 0, 1));
      final afterGap = feed(filter, fix(1000, 1000, 12));
      expect(afterGap.newSegment, isTrue);
      expect(
        distanceBetween(afterGap.fix!.point, fix(1000, 1000, 12).point),
        lessThan(.001),
      );
      filter.reset();
      final resumed = feed(filter, fix(2000, 0, 13));
      expect(resumed.newSegment, isFalse);
      expect(
        distanceBetween(resumed.fix!.point, fix(2000, 0, 13).point),
        lessThan(.001),
      );
    },
  );

  test('different accuracies change measurement influence', () {
    final good = LocationFilter();
    final uncertain = LocationFilter();
    for (var i = 0; i < 20; i++) {
      feed(good, fix(i * 3.0, 0, i));
      feed(uncertain, fix(i * 3.0, 0, i));
    }
    final a = feed(good, fix(60, 10, 20, accuracy: 3)).fix!;
    final b = feed(uncertain, fix(60, 10, 20, accuracy: 25)).fix!;
    expect(a.point.latitude, greaterThan(b.point.latitude));
  });

  test(
    'GNSS speed rejects an underreported position jump without corrupting state',
    () {
      final filter = LocationFilter();
      final reference = LocationFilter();
      for (var i = 0; i < 20; i++) {
        final raw = fix(i * 2.3, 0, i * 2, accuracy: 10, speed: 2.3);
        feed(filter, raw);
        feed(reference, raw);
      }
      final rawJump = fix(79.7, 0, 40, accuracy: 10, speed: 2.3);
      final jump = LocationFix(
        point: rawJump.point,
        timestamp: epoch.add(const Duration(milliseconds: 39900)),
        accuracy: 10,
        speed: 2.3,
      );
      expect(feed(filter, jump).reason, 'speed_inconsistent');
      final recovery = fix(48.3, 0, 42, accuracy: 10, speed: 2.3);
      final a = feed(filter, recovery);
      final b = feed(reference, recovery);
      expect(a.fix!.point.longitude, b.fix!.point.longitude);
      expect(a.newSegment, isFalse);
    },
  );

  test(
    'correlated offsets and isolated noise do not inflate distance above raw',
    () {
      final filter = LocationFilter();
      final raw = [
        for (var i = 0; i <= 240; i++)
          fix(
            i * 3.0,
            8 * math.sin(i / 8) + 3 * math.sin(i * 1.7),
            i,
            accuracy: 3,
          ),
      ];
      final filtered = [for (final p in raw) ?feed(filter, p).fix];
      expect(filtered.length, greaterThan(raw.length * .95));
      expect(length(filtered), lessThan(length(raw) * .9));
      expect(length(filtered), closeTo(720, 70));
    },
  );
}
