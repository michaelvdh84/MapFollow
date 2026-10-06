import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/speed_window.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  LocationFix fix(DateTime at, double? speed) => LocationFix(
    point: const RoutePoint(50, 4),
    timestamp: at,
    accuracy: 3,
    speed: speed,
  );

  test('averages only the five-second window without changing raw speed', () {
    final window = SpeedWindow();
    final raw = fix(now, 3);
    window.add(fix(now.subtract(const Duration(seconds: 6)), 9));
    window.add(fix(now.subtract(const Duration(seconds: 2)), 1));
    window.add(raw);
    expect(window.average(now), 2);
    expect(raw.speed, 3);
    expect(window.average(now.add(const Duration(seconds: 4))), 3);
    expect(window.average(now.add(const Duration(seconds: 6))), isNull);
  });

  test('missing and invalid speed are unknown, while zero is a real stop', () {
    final window = SpeedWindow();
    window.add(fix(now, 3));
    for (final speed in <double?>[null, -1, double.nan, double.infinity]) {
      window.add(fix(now, speed));
      expect(window.average(now), isNull);
    }
    window.add(fix(now, 0));
    expect(window.average(now), 0);
    window.clear();
    expect(window.average(now), isNull);
  });

  test(
    'legacy metadata and unknown enum values retain compatible defaults',
    () {
      final json =
          RunSession(id: 'legacy', startedAt: now, simulated: false).toJson()
            ..remove('locationProfile')
            ..remove('traversalControl');
      final run = RunSession.fromJson(json);
      expect(run.locationProfile, LocationProfile.precise);
      expect(run.traversalControl, TraversalControl.automatic);
      expect(
        GuidanceSettings.fromJson({}).locationProfile,
        LocationProfile.balanced,
      );
      expect(RoutePoint.fromJson({'lat': 50, 'lon': 4}).traversal, isNull);
      final settings = const GuidanceSettings(
        locationProfile: LocationProfile.autonomy,
      ).copyWith(voiceVolume: .5);
      expect(
        GuidanceSettings.fromJson(settings.toJson()).locationProfile,
        LocationProfile.autonomy,
      );
      expect(settings.voiceVolume, .5);
      expect(LocationFix.fromJson(fix(now, null).toJson()).speed, isNull);
    },
  );
}
