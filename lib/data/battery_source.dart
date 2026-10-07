import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/run_diagnostics.dart';

abstract class BatterySource {
  Future<BatterySample> read({String event = 'sample'});
}

/// Reads existing Android battery data; no persistent receiver or permission.
class AndroidBatterySource implements BatterySource {
  AndroidBatterySource({
    MethodChannel? channel,
    bool? android,
    DateTime Function()? now,
  }) : _channel = channel ?? const MethodChannel('mapfollow/battery'),
       _android = android,
       _now = now ?? DateTime.now;

  final MethodChannel _channel;
  final bool? _android;
  final DateTime Function() _now;

  @override
  Future<BatterySample> read({String event = 'sample'}) async {
    final timestamp = _now().toUtc();
    if (!(_android ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))) {
      return BatterySample(timestamp: timestamp, event: event);
    }
    try {
      final value = await _channel
          .invokeMethod<Object?>('getSnapshot')
          .timeout(const Duration(seconds: 3));
      if (value is! Map) {
        return BatterySample(timestamp: timestamp, event: event);
      }
      return BatterySample.fromJson({
        ...Map<String, dynamic>.from(value),
        'timestamp': timestamp.toIso8601String(),
        'event': event,
      });
    } catch (_) {
      // Missing plugin, unsupported sensor, malformed reply or detached engine.
      // Native exception text can contain device details and is never logged.
      return BatterySample(timestamp: timestamp, event: event);
    }
  }
}
