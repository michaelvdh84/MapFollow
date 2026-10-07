import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapfollow/data/location_source.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/navigation.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'Android profiles retain foreground recording with requested cadence',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const profiles = [
        LocationProfile.precise,
        LocationProfile.balanced,
        LocationProfile.autonomy,
      ];
      const seconds = [1, 2, 5];
      const distances = [0, 3, 5];
      for (var i = 0; i < profiles.length; i++) {
        final settings =
            DeviceLocationSource(profile: profiles[i]).profileSettings
                as AndroidSettings;
        expect(settings.intervalDuration, Duration(seconds: seconds[i]));
        expect(settings.distanceFilter, distances[i]);
        expect(
          settings.accuracy,
          i == 0 ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
        );
        expect(settings.foregroundNotificationConfig?.enableWakeLock, isTrue);
        expect(settings.foregroundNotificationConfig?.setOngoing, isTrue);
      }
      expect(DeviceLocationSource().profile, LocationProfile.precise);
    },
  );
  test('unavailable speed differs from stopped and raw measured speed', () {
    for (final speed in [
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(DeviceLocationSource.normalizeSpeed(speed), isNull);
    }
    expect(DeviceLocationSource.normalizeSpeed(0), 0);
    expect(DeviceLocationSource.normalizeSpeed(3.123456), 3.123456);
  });
  test(
    'free demo reverses original edges without interpolating across gaps',
    () {
      final prepared = PreparedRoute(
        Route(
          id: 'synthetic',
          name: 'SIMULATION',
          segments: [
            RouteSegment(const [RoutePoint(1, 1), RoutePoint(1, 1.001)]),
            RouteSegment(const [RoutePoint(1, 1.01), RoutePoint(1, 1.011)]),
          ],
        ),
      );
      final source = SimulatedLocationSource(prepared, returnToStart: true);
      final timestamp = DateTime.utc(2024);
      expect(source.totalLength, prepared.length * 2);
      final outbound = source.fixAt(
        prepared.length * .25,
        timestamp: timestamp,
      );
      final returning = source.fixAt(
        prepared.length * 1.75,
        timestamp: timestamp,
      );
      expect(
        returning.point.longitude,
        closeTo(outbound.point.longitude, 1e-10),
      );
      expect(outbound.point.traversal, TraversalDirection.outbound);
      expect(returning.point.traversal, TraversalDirection.returning);
      expect(
        source.fixAt(source.totalLength, timestamp: timestamp).point.longitude,
        1,
      );
      for (var i = 0; i <= 100; i++) {
        final p = source
            .fixAt(source.totalLength * i / 100, timestamp: timestamp)
            .point;
        expect(p.longitude <= 1.001 || p.longitude >= 1.01, isTrue);
      }
      final guided = SimulatedLocationSource(prepared);
      expect(guided.totalLength, prepared.length);
      expect(guided.fixAt(0, timestamp: timestamp).point.traversal, isNull);
    },
  );
  test('resuming demo uses complete journey progress including return', () {
    final prepared = PreparedRoute(
      Route(
        id: 'synthetic',
        name: 'SIMULATION',
        segments: [
          RouteSegment(const [RoutePoint(1, 1), RoutePoint(1, 1.001)]),
        ],
      ),
    );
    final progress = prepared.length * 1.4;
    final resumed = SimulatedLocationSource(
      prepared,
      initialProgress: progress,
      returnToStart: true,
    );
    expect(
      resumed
          .fixAt(resumed.initialProgress, timestamp: DateTime.utc(2024))
          .point
          .traversal,
      TraversalDirection.returning,
    );
  });
}
