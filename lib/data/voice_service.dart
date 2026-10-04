import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

abstract interface class VoiceService {
  Future<void> prepare(double volume);
  Future<bool> speak(String message);
  Future<void> stop();
}

/// One utterance at a time; obsolete announcements are discarded, not queued.
/// Native focus is explicitly checked; a denied request never plays speech.
class DeviceVoiceService implements VoiceService {
  final FlutterTts _tts = FlutterTts();
  static const _audio = MethodChannel('mapfollow/audio');
  bool _speaking = false;
  int _generation = 0;
  @override
  Future<void> prepare(double volume) async {
    _audio.setMethodCallHandler((call) async {
      if (call.method == 'interrupted') await stop();
    });
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(.48);
    await _tts.setVolume(volume);
    final voices = await _tts.getVoices;
    Map<String, dynamic>? selected;
    if (voices is List) {
      for (final entry in voices) {
        final voice = Map<String, dynamic>.from(entry as Map);
        final locale = (voice['locale'] as String? ?? '').replaceAll('_', '-');
        final network = voice['network_required'];
        final features = (voice['features'] as String? ?? '').split('\t');
        if (locale.startsWith('fr') &&
            !features.contains('notInstalled') &&
            (network == false ||
                network == 'false' ||
                network == 0 ||
                network == '0')) {
          selected = voice;
          break;
        }
      }
    }
    if (selected == null) {
      throw StateError(
        'Installez une voix française hors connexion dans les réglages de synthèse vocale Android, puis réessayez.',
      );
    }
    await _tts.setLanguage(selected['locale'] as String);
    await _tts.setVoice({
      'name': selected['name'] as String,
      'locale': selected['locale'] as String,
    });
    await _tts.setAudioAttributesForNavigation();
  }

  @override
  Future<bool> speak(String message) async {
    if (_speaking) return false;
    _speaking = true;
    final generation = ++_generation;
    try {
      if (defaultTargetPlatform == TargetPlatform.android &&
          await _audio.invokeMethod<bool>('requestFocus') != true) {
        return false;
      }
      if (generation != _generation) return false;
      return await _tts.speak(message).timeout(const Duration(seconds: 15)) ==
          1;
    } finally {
      if (generation == _generation) {
        try {
          await _tts.stop();
        } finally {
          if (defaultTargetPlatform == TargetPlatform.android) {
            await _audio.invokeMethod<void>('abandonFocus');
          }
          _speaking = false;
        }
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _tts.stop();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _audio.invokeMethod<void>('abandonFocus');
    }
    _speaking = false;
  }
}
