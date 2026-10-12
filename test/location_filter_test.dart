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
    'filter uses native intervals, carries clocks and rejects reordered fixes before state changes',
    () {
      final filter = LocationFilter();
      LocationFix native(int nanos, int utcSeconds) => LocationFix(
        point: RoutePoint(0, nanos / 1e9 * 2 / earthRadius * 180 / math.pi),
        timestamp: epoch.add(Duration(seconds: utcSeconds)),
        accuracy: 3,
        elapsedRealtimeNanos: nanos,
        receivedElapsedRealtimeNanos: nanos + 100000000,
        locationStreamId: 'synthetic-live-stream',
      );
      expect(feed(filter, native(1000000000, 0)).fix, isNotNull);
      final second = feed(filter, native(1500000000, 20));
      expect(second.fix, isNotNull);
      expect(second.newSegment, false);
      expect(second.fix!.elapsedRealtimeNanos, 1500000000);
      expect(second.fix!.locationStreamId, 'synthetic-live-stream');
      expect(feed(filter, native(1400000000, 21)).reason, 'non_monotonic');
      expect(feed(filter, native(2000000000, 22)).fix, isNotNull);
      final afterGap = feed(filter, native(13000000000, 23));
      expect(afterGap.newSegment, true);
    },
  );
  test(
    'missing motion fields do not switch a regularized trace back to CV',
    () {
      for (final missing in [null, 0.0, -1.0, 2.0, double.nan]) {
        final filter = LocationFilter();
        LocationFix? previous;
        final points = <LocationFix>[];
        for (var millis = 0; millis <= 120000; millis += 500) {
          final angle = millis / 1000 * 2.5 / 30;
          final raw = LocationFix(
            point: RoutePoint(
              30 * math.sin(angle) / earthRadius * 180 / math.pi,
              30 * math.cos(angle) / earthRadius * 180 / math.pi,
            ),
            timestamp: epoch.add(Duration(milliseconds: millis)),
            accuracy: 6,
            speed: millis >= 60000 && millis < 62000 ? null : 2.5,
            speedAccuracy: millis >= 60000 && millis < 70000 ? missing : .27,
          );
          final fix = feed(filter, raw).fix!;
          if (previous != null && millis >= 59000 && millis <= 74000) {
            // With coherent positions (no noisy branch), every output remains
            // between the previous output and the latest measured point.
            expect(
              distanceBetween(previous.point, fix.point) +
                  distanceBetween(fix.point, raw.point),
              lessThanOrEqualTo(
                distanceBetween(previous.point, raw.point) + .001,
              ),
            );
          }
          previous = fix;
          points.add(fix);
        }
        expect(length(points), closeTo(300, 6));
      }
    },
  );
  test('crossing the low-speed boundary does not create a position jump', () {
    final filter = LocationFilter();
    LocationFix? previous;
    for (var millis = 0; millis <= 60000; millis += 500) {
      final raw = LocationFix(
        point: RoutePoint(0, millis / 1000 * .5 / earthRadius * 180 / math.pi),
        timestamp: epoch.add(Duration(milliseconds: millis)),
        accuracy: 6,
        speed: millis % 1000 == 0 ? .51 : .49,
        speedAccuracy: .1,
      );
      final fix = feed(filter, raw).fix!;
      if (previous != null) {
        expect(distanceBetween(previous.point, fix.point), lessThan(.6));
      }
      previous = fix;
    }
  });
  test('low-accuracy curves and corners do not amplify measured distance', () {
    for (final shape in ['circle', 'rectangle']) {
      for (final accuracy in [3.0, 6.0]) {
        for (final interval in [250, 500, 673, 1000]) {
          final filter = LocationFilter();
          final processed = <LocationFix>[];
          for (var millis = 0; millis <= 240000; millis += interval) {
            final travel = millis / 1000 * 2.5;
            double x, y;
            if (shape == 'circle') {
              x = 30 * math.sin(travel / 30);
              y = 30 * math.cos(travel / 30);
            } else {
              final s = travel % 240;
              if (s < 60) {
                x = s;
                y = 0;
              } else if (s < 120) {
                x = 60;
                y = s - 60;
              } else if (s < 180) {
                x = 180 - s;
                y = 60;
              } else {
                x = 0;
                y = 240 - s;
              }
            }
            final raw = LocationFix(
              point: RoutePoint(
                y / earthRadius * 180 / math.pi,
                x / earthRadius * 180 / math.pi,
              ),
              timestamp: epoch.add(Duration(milliseconds: millis)),
              accuracy: accuracy,
              speed: 2.5,
              speedAccuracy: .27,
              heading: millis % 360.0,
            );
            final result = feed(filter, raw);
            expect(result.fix, isNotNull);
            processed.add(result.fix!);
            expect(distanceBetween(raw.point, result.fix!.point), lessThan(7));
          }
          final reference =
              processed.last.timestamp.difference(epoch).inMilliseconds /
              1000 *
              2.5;
          expect(
            length(processed),
            closeTo(reference, reference * .02),
            reason: '$shape / $accuracy m / $interval ms',
          );
        }
      }
    }
  });
  test('slow correlated bias does not gain distance through prediction', () {
    final filter = LocationFilter();
    final rawPoints = <LocationFix>[], processed = <LocationFix>[];
    for (var millis = 0; millis <= 240000; millis += 673) {
      final t = millis / 1000;
      final raw = LocationFix(
        point: RoutePoint(
          6 * math.sin(t * 2 * math.pi / 30) / earthRadius * 180 / math.pi,
          (t * 2.5 + 6 * math.sin(t * 2 * math.pi / 60)) /
              earthRadius *
              180 /
              math.pi,
        ),
        timestamp: epoch.add(Duration(milliseconds: millis)),
        accuracy: 6,
        speed: 2.5,
        speedAccuracy: .27,
      );
      rawPoints.add(raw);
      final result = feed(filter, raw);
      expect(result.fix, isNotNull);
      processed.add(result.fix!);
      final truth = RoutePoint(0, t * 2.5 / earthRadius * 180 / math.pi);
      expect(distanceBetween(truth, result.fix!.point), lessThan(12));
    }
    // This bias already inflates the raw trace; do not promise a 2% absolute
    // bound for an ambiguous signal. The filter must not amplify that bias.
    expect(length(processed), lessThan(length(rawPoints)));
  });
  test('regularization is invariant to axes and ignores device heading', () {
    final horizontal = LocationFilter(), rotated = LocationFilter();
    for (var millis = 0; millis <= 120000; millis += 673) {
      final a = millis / 1000 * 2.5 / 30;
      final x = 30 * math.sin(a), y = 30 * math.cos(a);
      LocationFix measurement(double px, double py, double heading) =>
          LocationFix(
            point: RoutePoint(
              py / earthRadius * 180 / math.pi,
              px / earthRadius * 180 / math.pi,
            ),
            timestamp: epoch.add(Duration(milliseconds: millis)),
            accuracy: 6,
            speed: 2.5,
            speedAccuracy: .27,
            heading: heading,
          );
      final left = feed(horizontal, measurement(x, y, 0)).fix!;
      final right = feed(rotated, measurement(-y, x, millis % 360.0)).fix!;
      final expected = RoutePoint(left.point.longitude, -left.point.latitude);
      expect(distanceBetween(expected, right.point), lessThan(.001));
    }
  });
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
