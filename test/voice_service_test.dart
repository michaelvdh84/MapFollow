import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audio = MethodChannel('mapfollow/audio');
  const tts = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late List<Map<String, dynamic>> voices;
  late bool granted;
  Completer<int>? speech;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    granted = true;
    speech = null;
    voices = [
      {
        'name': 'Synthetic French',
        'locale': 'fr-FR',
        'network_required': '0',
        'features': '',
      },
    ];
    messenger.setMockMethodCallHandler(audio, (call) async {
      calls.add(call.method);
      return call.method == 'requestFocus' ? granted : null;
    });
    messenger.setMockMethodCallHandler(tts, (call) async {
      calls.add(call.method);
      if (call.method == 'getVoices') return voices;
      if (call.method == 'speak' && speech != null) return speech!.future;
      return 1;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(audio, null);
    messenger.setMockMethodCallHandler(tts, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'recognizes actual Android offline voice representation and releases focus',
    () async {
      final service = DeviceVoiceService();
      await service.prepare(.7);
      expect(calls, contains('setVoice'));
      calls.clear();
      expect(await service.speak('Test'), isTrue);
      expect(
        calls,
        orderedEquals(['requestFocus', 'speak', 'stop', 'abandonFocus']),
      );
    },
  );
  test('network-only or not installed voice blocks preparation', () async {
    final service = DeviceVoiceService();
    voices.single['network_required'] = '1';
    await expectLater(service.prepare(1), throwsStateError);
    voices.single['network_required'] = '0';
    voices.single['features'] = 'notInstalled';
    await expectLater(service.prepare(1), throwsStateError);
  });
  test('denied focus does not speak', () async {
    final service = DeviceVoiceService();
    await service.prepare(1);
    calls.clear();
    granted = false;
    expect(await service.speak('Test'), isFalse);
    expect(calls, isNot(contains('speak')));
    expect(calls.last, 'abandonFocus');
  });
  test(
    'discards concurrent utterances rather than stacking obsolete turns',
    () async {
      final service = DeviceVoiceService();
      await service.prepare(1);
      speech = Completer<int>();
      final first = service.speak('First');
      await Future<void>.delayed(Duration.zero);
      expect(await service.speak('Obsolete'), isFalse);
      speech!.complete(1);
      await first;
      expect(calls.where((c) => c == 'speak'), hasLength(1));
    },
  );
}
