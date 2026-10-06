import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/gnss_source.dart';
import 'package:mapfollow/domain/gnss_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  final now = DateTime.utc(2024);
  Map<String, Object?> payload({
    String availability = 'available',
    List<Object?>? counts,
  }) => {
    'availability': availability,
    'observedAt': now.millisecondsSinceEpoch,
    'constellations':
        counts ??
        [
          {'code': 'GPS', 'seen': 7, 'used': 4},
          {'code': 'Galileo', 'seen': 5, 'used': 3},
        ],
  };
  test(
    'decodes sanitized constellation groups and exact freshness boundary',
    () {
      final snapshot = AndroidGnssSource.decode(payload(), now: now);
      expect(snapshot.availability, GnssAvailability.available);
      expect(snapshot.seen, 12);
      expect(snapshot.used, 7);
      expect(snapshot.constellations.last.name, 'Galileo');
      expect(snapshot.isStale(now.add(const Duration(seconds: 10))), isFalse);
      expect(
        snapshot.isStale(now.add(const Duration(milliseconds: 10001))),
        isTrue,
      );
      expect(() => snapshot.constellations.clear(), throwsUnsupportedError);
    },
  );
  test(
    'waiting distinguishes registration from first receiver observation',
    () {
      final snapshot = AndroidGnssSource.decode(
        payload(availability: 'waiting'),
        now: now,
      );
      expect(snapshot.availability, GnssAvailability.waiting);
      expect(snapshot.constellations, isEmpty);
      expect(snapshot.seen, 0);
      expect(snapshot.used, 0);
    },
  );
  test(
    'rejects malformed payloads and contradictory or unknown count fields',
    () {
      final bad = <Object?>[
        null,
        'message',
        {},
        {'availability': 'available'},
        payload(
          counts: [
            {'code': 'GPS', 'seen': -1, 'used': 0},
          ],
        ),
        payload(
          counts: [
            {'code': 'GPS', 'seen': 1, 'used': 2},
          ],
        ),
        payload(
          counts: [
            {'code': 'Untrusted name', 'seen': 1, 'used': 1},
          ],
        ),
        payload(
          counts: [
            {'code': 'GPS', 'seen': 1, 'used': 1},
            {'code': 'GPS', 'seen': 1, 'used': 1},
          ],
        ),
        {...payload(), 'observedAt': 8640000000000001},
      ];
      for (final value in bad) {
        final result = AndroidGnssSource.decode(value, now: now);
        expect(result.availability, GnssAvailability.unavailable);
        expect(result.constellations, isEmpty);
      }
      for (final state in GnssAvailability.values.where(
        (s) => s != GnssAvailability.available,
      )) {
        final result = AndroidGnssSource.decode(
          payload(availability: state.name),
          now: now,
        );
        expect(result.availability, state);
        expect(result.constellations, isEmpty);
      }
    },
  );
  test(
    'channel listener cancel lifecycle and errors never expose native messages',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = 'mapfollow/gnssStatus';
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(const MethodChannel(channel), (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      final snapshots = <GnssSnapshot>[];
      final subscription = AndroidGnssSource().snapshots.listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      Future<void> send(ByteData data) async {
        final complete = Completer<void>();
        messenger.handlePlatformMessage(
          channel,
          data,
          (_) => complete.complete(),
        );
        await complete.future;
        await Future<void>.delayed(Duration.zero);
      }

      await send(codec.encodeSuccessEnvelope(payload()));
      await send(
        codec.encodeErrorEnvelope(
          code: 'permissionDenied',
          message: 'Raw platform detail',
        ),
      );
      await send(codec.encodeSuccessEnvelope(payload()));
      expect(snapshots.map((s) => s.availability), [
        GnssAvailability.available,
        GnssAvailability.permissionDenied,
        GnssAvailability.available,
      ]);
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['listen', 'cancel']);
      messenger.setMockMethodCallHandler(const MethodChannel(channel), null);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test(
    'unsupported platform and channel startup failure produce safe states',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        (await AndroidGnssSource().snapshots.first).availability,
        GnssAvailability.unavailable,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const channel = MethodChannel('mapfollow/gnssStatus');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'unavailable',
          message: 'Raw startup detail',
        );
      });
      expect(
        (await AndroidGnssSource().snapshots.first).availability,
        GnssAvailability.unavailable,
      );
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
