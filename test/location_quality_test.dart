import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/location_quality.dart';
import 'package:mapfollow/domain/models.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);

  LocationFix fix(
    double latitude,
    double longitude, {
    DateTime? at,
    double accuracy = 5,
  }) => LocationFix(
    point: RoutePoint(latitude, longitude),
    timestamp: at ?? now,
    accuracy: accuracy,
  );

  test('accepts a recent accurate synthetic fix', () {
    expect(LocationQuality.accepts(fix(50, 4), now: now), isTrue);
  });

  test(
    'rejects invalid coordinates, poor accuracy, and stale/future fixes',
    () {
      expect(LocationQuality.accepts(fix(91, 4), now: now), isFalse);
      expect(LocationQuality.accepts(fix(50, 181), now: now), isFalse);
      expect(
        LocationQuality.accepts(fix(50, 4, accuracy: 25.01), now: now),
        isFalse,
      );
      expect(
        LocationQuality.accepts(
          fix(50, 4, at: now.subtract(const Duration(seconds: 11))),
          now: now,
        ),
        isFalse,
      );
      expect(
        LocationQuality.accepts(
          fix(50, 4, at: now.add(const Duration(seconds: 3))),
          now: now,
        ),
        isFalse,
      );
    },
  );

  test('requires monotonic timestamps and rejects implausible jumps', () {
    final previous = fix(50, 4);
    expect(
      LocationQuality.accepts(
        fix(50, 4, at: now),
        now: now,
        previous: previous,
      ),
      isFalse,
    );
    expect(
      LocationQuality.accepts(
        fix(50, 4.01, at: now.add(const Duration(seconds: 1))),
        now: now.add(const Duration(seconds: 1)),
        previous: previous,
      ),
      isFalse,
    );
  });
}
