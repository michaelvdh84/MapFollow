import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapfollow/data/location_source.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/navigation.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'custom interval uses milliseconds and disables displacement suppression',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final profile in LocationProfile.values) {
        final settings =
            DeviceLocationSource(
                  profile: profile,
                  intervalMillis: 500,
                ).profileSettings
                as AndroidSettings;
        expect(settings.intervalDuration, const Duration(milliseconds: 500));
        expect(settings.distanceFilter, 0);
        expect(settings.foregroundNotificationConfig?.setOngoing, true);
      }
      expect(
        (DeviceLocationSource(
                  profile: LocationProfile.balanced,
                  intervalMillis: 0,
                ).profileSettings
                as AndroidSettings)
            .intervalDuration,
        const Duration(seconds: 2),
      );
    },
  );

  test(
    'settings and sessions round trip overrides and retain legacy profile cadence',
    () {
      const settings = GuidanceSettings(locationIntervalMillis: 500);
      expect(
        GuidanceSettings.fromJson(settings.toJson()).locationIntervalMillis,
        500,
      );
      expect(settings.copyWith(voiceVolume: .5).locationIntervalMillis, 500);
      expect(
        settings.copyWith(clearLocationInterval: true).locationIntervalMillis,
        null,
      );
      for (final invalid in [0, -1, 249, 10001, 500.1, '500']) {
        expect(
          GuidanceSettings.fromJson({
            ...settings.toJson(),
            'locationIntervalMillis': invalid,
          }).locationIntervalMillis,
          null,
        );
      }
      final run = RunSession(
        id: 'synthetic',
        startedAt: DateTime.utc(2026),
        simulated: true,
        locationProfile: LocationProfile.autonomy,
        locationIntervalMillis: 500,
      );
      expect(
        RunSession.fromJson(run.toJson()).requestedLocationIntervalMillis,
        500,
      );
      final legacy = run.toJson()..remove('locationIntervalMillis');
      expect(RunSession.fromJson(legacy).requestedLocationIntervalMillis, 5000);
      expect(RunSession.fromJson(legacy).locationFilterVersion, null);
    },
  );

  test(
    'platform absence flags prevent false stationary and perfect-accuracy fixes',
    () {
      final base = <String, dynamic>{
        'latitude': 0.0,
        'longitude': 0.0,
        'timestamp': DateTime.utc(2026).millisecondsSinceEpoch,
      };
      final missing = DeviceLocationSource.normalizePosition(
        Position.fromMap(base),
      );
      expect(missing.speed, null);
      expect(missing.heading, null);
      expect(missing.accuracy.isNaN, true);
      final stopped = DeviceLocationSource.normalizePosition(
        Position.fromMap({
          ...base,
          'speed': 0.0,
          'heading': 0.0,
          'accuracy': 3.0,
          'speed_accuracy': .2,
          'heading_accuracy': 5.0,
        }),
      );
      expect(stopped.speed, 0);
      expect(stopped.heading, 0);
      expect(stopped.speedAccuracy, .2);
      expect(stopped.headingAccuracy, 5);
    },
  );
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
