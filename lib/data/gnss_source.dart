import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/gnss_status.dart';

abstract interface class GnssSource {
  Stream<GnssSnapshot> get snapshots;
}

/// Le canal écoute le récepteur actif sans démarrer de GPS ni demander de droit.
class AndroidGnssSource implements GnssSource {
  AndroidGnssSource({EventChannel? channel})
    : _channel = channel ?? const EventChannel('mapfollow/gnssStatus');
  final EventChannel _channel;
  Stream<GnssSnapshot>? _snapshots;

  @override
  Stream<GnssSnapshot> get snapshots => _snapshots ??= _createStream();

  Stream<GnssSnapshot> _createStream() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Stream.value(_unavailable(DateTime.now().toUtc()));
    }
    final methods = MethodChannel(
      _channel.name,
      _channel.codec,
      _channel.binaryMessenger,
    );
    late StreamController<GnssSnapshot> controller;
    // Adaptation du protocole EventChannel : même les échecs de listen/cancel
    // restent des états publics, sans journaliser de message natif brut.
    controller = StreamController<GnssSnapshot>.broadcast(
      onListen: () async {
        _channel.binaryMessenger.setMessageHandler(_channel.name, (
          reply,
        ) async {
          if (reply == null) {
            controller.add(_unavailable(DateTime.now().toUtc()));
          } else {
            try {
              controller.add(decode(_channel.codec.decodeEnvelope(reply)));
            } catch (error) {
              controller.add(_errorSnapshot(error));
            }
          }
          return null;
        });
        try {
          await methods.invokeMethod<void>('listen');
        } catch (error) {
          if (controller.hasListener) controller.add(_errorSnapshot(error));
        }
      },
      onCancel: () async {
        _channel.binaryMessenger.setMessageHandler(_channel.name, null);
        try {
          await methods.invokeMethod<void>('cancel');
        } catch (_) {
          // Annulation locale effective même si le moteur natif est déjà détruit.
        }
      },
    );
    return controller.stream;
  }

  static GnssSnapshot _errorSnapshot(Object error) => GnssSnapshot(
    observedAt: DateTime.now().toUtc(),
    availability: error is PlatformException && error.code == 'permissionDenied'
        ? GnssAvailability.permissionDenied
        : GnssAvailability.unavailable,
  );

  static GnssSnapshot _unavailable(DateTime now) =>
      GnssSnapshot(observedAt: now, availability: GnssAvailability.unavailable);

  /// Les données natives mal formées restent un état indisponible explicite.
  static GnssSnapshot decode(Object? value, {DateTime? now}) {
    final observedNow = now ?? DateTime.now().toUtc();
    if (value is! Map) return _unavailable(observedNow);
    final availability = GnssAvailability.values
        .where((state) => state.name == value['availability'])
        .firstOrNull;
    if (availability == null) return _unavailable(observedNow);
    final milliseconds = value['observedAt'];
    DateTime? timestamp;
    if (milliseconds is int) {
      try {
        timestamp = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
      } on ArgumentError {
        timestamp = null;
      }
    }
    if (timestamp == null ||
        timestamp.isAfter(observedNow.add(const Duration(seconds: 10)))) {
      return _unavailable(observedNow);
    }
    if (availability != GnssAvailability.available) {
      return GnssSnapshot(observedAt: timestamp, availability: availability);
    }
    final rawCounts = value['constellations'];
    if (rawCounts is! List) return _unavailable(observedNow);
    const names = {
      'GPS': 'GPS',
      'GLONASS': 'GLONASS',
      'Galileo': 'Galileo',
      'BeiDou': 'BeiDou',
      'QZSS': 'QZSS',
      'SBAS': 'SBAS',
      'IRNSS': 'IRNSS',
      'Unknown': 'Inconnue',
    };
    final counts = <GnssConstellationCount>[];
    final seenCodes = <String>{};
    for (final row in rawCounts) {
      if (row is! Map) return _unavailable(observedNow);
      final code = row['code'], seen = row['seen'], used = row['used'];
      if (code is! String ||
          !names.containsKey(code) ||
          !seenCodes.add(code) ||
          seen is! int ||
          used is! int ||
          seen < 0 ||
          used < 0 ||
          used > seen ||
          seen > 1000) {
        return _unavailable(observedNow);
      }
      counts.add(
        GnssConstellationCount(
          code: code,
          name: names[code]!,
          seen: seen,
          used: used,
        ),
      );
    }
    return GnssSnapshot(
      observedAt: timestamp,
      availability: availability,
      constellations: counts,
    );
  }
}
