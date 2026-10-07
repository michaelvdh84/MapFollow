import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/battery_source.dart';
import 'package:mapfollow/domain/run_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 1, 1);
  const channel = MethodChannel('test/battery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'battery keeps zero distinct from unavailable and negative discharge current',
    () {
      final sample = BatterySample.fromJson({
        'timestamp': now.toIso8601String(),
        'levelPercent': 0,
        'charging': false,
        'currentMicroAmps': -300000,
        'chargeMicroAh': 0,
        'voltageMv': 3700,
        'temperatureC': 24.5,
        'event': 'finish',
      });
      expect(sample.levelPercent, 0);
      expect(sample.charging, false);
      expect(sample.currentMicroAmps, -300000);
      expect(sample.chargeMicroAh, 0);
      expect(BatterySample.fromJson(sample.toJson()).toJson(), sample.toJson());
    },
  );

  test('invalid and unsupported battery readings remain absent', () {
    final sample = BatterySample.fromJson({
      'timestamp': now.toIso8601String(),
      'levelPercent': 101,
      'charging': 'false',
      'currentMicroAmps': -2147483648,
      'chargeMicroAh': -1,
      'voltageMv': 0,
      'temperatureC': double.nan,
    });
    expect(sample.levelPercent, isNull);
    expect(sample.charging, isNull);
    expect(sample.currentMicroAmps, isNull);
    expect(sample.chargeMicroAh, isNull);
    expect(sample.voltageMv, isNull);
    expect(sample.temperatureC, isNull);
  });

  test(
    'native read is a single snapshot without listener or permission',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {'levelPercent': 93, 'charging': false};
      });
      final sample = await AndroidBatterySource(
        channel: channel,
        android: true,
        now: () => now,
      ).read(event: 'finish');
      expect(calls, ['getSnapshot']);
      expect(sample.timestamp, now);
      expect(sample.levelPercent, 93);
      expect(sample.event, 'finish');
    },
  );

  test(
    'unsupported platform, failed plugin and malformed reply degrade safely',
    () async {
      final unsupported = await AndroidBatterySource(
        channel: channel,
        android: false,
        now: () => now,
      ).read();
      expect(unsupported.levelPercent, isNull);
      for (final payload in [
        null,
        'invalid',
        {'levelPercent': 100.5},
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async => payload);
        final sample = await AndroidBatterySource(
          channel: channel,
          android: true,
          now: () => now,
        ).read();
        expect(sample.levelPercent, isNull);
      }
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'unavailable',
          message: 'private native detail',
        );
      });
      final failure = await AndroidBatterySource(
        channel: channel,
        android: true,
        now: () => now,
      ).read(event: 'start');
      expect(failure.levelPercent, isNull);
      expect(failure.event, 'start');
    },
  );
}
