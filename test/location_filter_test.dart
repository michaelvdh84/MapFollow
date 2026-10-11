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
  test('unusable speed uncertainty preserves the position-only fallback', () {
    for (final error in [0.0, -1.0, 2.0, double.nan, double.infinity]) {
      final reference = LocationFilter(), candidate = LocationFilter();
      for (var i = 0; i < 30; i++) {
        final raw = fix(i * 3.0, 2 * math.sin(i.toDouble()), i, accuracy: 3);
        final expected = feed(reference, raw).fix!;
        final actual = feed(
          candidate,
          LocationFix(
            point: raw.point,
            timestamp: raw.timestamp,
            accuracy: raw.accuracy,
            speed: raw.speed,
            speedAccuracy: error,
          ),
        ).fix!;
        expect(distanceBetween(actual.point, expected.point), lessThan(.0001));
      }
    }
  });
  test(
    'uncertain low speed does not anchor moving positions as stationary',
    () {
      final filter = LocationFilter();
      for (var i = 0; i < 20; i++) {
        final raw = fix(i * .7, 0, i, speed: .2);
        final result = feed(
          filter,
          LocationFix(
            point: raw.point,
            timestamp: raw.timestamp,
            accuracy: 5,
            speed: .2,
            speedAccuracy: 1,
          ),
        );
        expect(result.reason, isNot('stationary'));
      }
    },
  );

  test(
    'sustained curved motion is followed without rejecting measured corners',
    () {
      for (final millis in [500, 1000]) {
        final filter = LocationFilter();
        final points = <LocationFix>[];
        for (var t = 0; t <= 120000; t += millis) {
          final angle = t / 1000 * 3 / 30;
          final raw = LocationFix(
            point: RoutePoint(
              30 * math.sin(angle) / earthRadius * 180 / math.pi,
              30 * math.cos(angle) / earthRadius * 180 / math.pi,
            ),
            timestamp: epoch.add(Duration(milliseconds: t)),
            accuracy: 3,
            speed: 3,
            speedAccuracy: .2,
          );
          final result = feed(filter, raw);
          expect(result.fix, isNotNull);
          points.add(result.fix!);
          expect(distanceBetween(raw.point, result.fix!.point), lessThan(7));
        }
        expect(length(points), closeTo(360, 360 * .05));
      }
    },
  );
  test(
    'subsecond correlated fixes remain stable across requested cadences',
    () {
      final distances = <double>[];
      for (final millis in [1000, 500, 250]) {
        final filter = LocationFilter();
        final processed = <LocationFix>[];
        for (var t = 0; t <= 240000; t += millis) {
          final s = t / 1000;
          final raw = LocationFix(
            point: RoutePoint(
              (3 * math.sin(s * 1.7)) / earthRadius * 180 / math.pi,
              (s * 3 + 2 * math.sin(s * .8)) / earthRadius * 180 / math.pi,
            ),
            timestamp: epoch.add(Duration(milliseconds: t)),
            accuracy: 5,
            speed: 3,
            speedAccuracy: .2,
          );
          final result = feed(filter, raw);
          expect(result.fix, isNotNull);
          processed.add(result.fix!);
        }
        distances.add(length(processed));
        expect(length(processed), closeTo(720, 720 * .02));
        expect(processed.last.speedAccuracy, .2);
      }
      expect(
        distances.reduce(math.max) - distances.reduce(math.min),
        lessThan(10),
      );
    },
  );

  test(
    'subsecond stationary confirmation is time based and preserves sharp turns',
    () {
      for (final millis in [500, 250]) {
        final filter = LocationFilter();
        for (var t = 0; t < 2000; t += millis) {
          final raw = fix(0, 0, 0, speed: 0);
          final result = feed(
            filter,
            LocationFix(
              point: raw.point,
              timestamp: epoch.add(Duration(milliseconds: t)),
              accuracy: 3,
              speed: 0,
            ),
          );
          expect(result.reason, isNot('stationary'));
        }
        expect(feed(filter, fix(0, 0, 2, speed: 0)).reason, 'stationary');
        filter.reset();
        for (var t = 0; t <= 60000; t += millis) {
          final s = t / 1000;
          final x = s < 20 ? s * 3 : 60.0;
          final y = s < 20
              ? 0.0
              : s < 40
              ? (s - 20) * 3
              : (60 - s) * 3;
          final raw = LocationFix(
            point: RoutePoint(
              y / earthRadius * 180 / math.pi,
              x / earthRadius * 180 / math.pi,
            ),
            timestamp: epoch.add(Duration(milliseconds: t)),
            accuracy: 3,
            speed: 3,
          );
          final filtered = feed(filter, raw);
          expect(filtered.fix, isNotNull);
          expect(distanceBetween(raw.point, filtered.fix!.point), lessThan(9));
        }
      }
    },
  );
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
