import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/data/gnss_source.dart';
import 'package:mapfollow/domain/gnss_status.dart';
import 'package:mapfollow/presentation/gnss_panel.dart';

class _Source implements GnssSource {
  _Source() {
    controller = StreamController<GnssSnapshot>.broadcast(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }
  late final StreamController<GnssSnapshot> controller;
  int listens = 0, cancels = 0;
  @override
  Stream<GnssSnapshot> get snapshots => controller.stream;
}

void main() {
  testWidgets('GNSS panel recovers after a temporary stream error', (
    tester,
  ) async {
    final source = _Source();
    final now = DateTime.utc(2026);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GnssPanel(
            running: true,
            simulated: false,
            source: source,
            now: () => now,
          ),
        ),
      ),
    );
    source.controller.addError(StateError('synthetic temporary error'));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('indisponibles sur cet appareil'),
      findsOneWidget,
    );
    source.controller.add(
      GnssSnapshot(
        observedAt: now,
        availability: GnssAvailability.available,
        constellations: const [
          GnssConstellationCount(code: 'GPS', name: 'GPS', seen: 7, used: 4),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Satellites vus : 7 · utilisés : 4'), findsOneWidget);
    expect(find.textContaining('indisponibles sur cet appareil'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await source.controller.close();
  });

  testWidgets(
    'GNSS panel subscribes only to real active run and releases on pause/close',
    (tester) async {
      final source = _Source();
      var now = DateTime.utc(2026);
      Future<void> show({bool running = true, bool simulated = false}) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: GnssPanel(
                  running: running,
                  simulated: simulated,
                  source: source,
                  now: () => now,
                ),
              ),
            ),
          );
      await show(simulated: true);
      expect(source.listens, 0);
      expect(
        find.textContaining('indisponibles en simulation'),
        findsOneWidget,
      );
      await show(running: false);
      expect(source.listens, 0);
      expect(find.textContaining('inactifs'), findsOneWidget);
      await show();
      expect(source.listens, 1);
      source.controller.add(
        GnssSnapshot(
          observedAt: now,
          availability: GnssAvailability.available,
          constellations: const [
            GnssConstellationCount(code: 'GPS', name: 'GPS', seen: 9, used: 5),
            GnssConstellationCount(
              code: 'Galileo',
              name: 'Galileo',
              seen: 4,
              used: 3,
            ),
          ],
        ),
      );
      await tester.pump();
      expect(find.text('Satellites vus : 13 · utilisés : 8'), findsOneWidget);
      expect(find.text('Galileo : 4 vus · 3 utilisés'), findsOneWidget);
      now = now.add(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('périmés'), findsOneWidget);
      await show(running: false);
      await tester.pump();
      expect(source.cancels, 1);
      await show();
      expect(source.listens, 2);
      await tester.pumpWidget(const SizedBox());
      expect(source.cancels, 2);
      await source.controller.close();
    },
  );

  testWidgets(
    'GNSS waiting unavailable permission and inactive states have explicit messages',
    (tester) async {
      final source = _Source();
      final now = DateTime.utc(2026);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GnssPanel(
              running: true,
              simulated: false,
              source: source,
              now: () => now,
            ),
          ),
        ),
      );
      for (final state in [
        GnssAvailability.waiting,
        GnssAvailability.unavailable,
        GnssAvailability.permissionDenied,
        GnssAvailability.inactive,
      ]) {
        source.controller.add(
          GnssSnapshot(observedAt: now, availability: state),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining(switch (state) {
            GnssAvailability.waiting =>
              'En attente de la première observation GNSS',
            GnssAvailability.unavailable => 'indisponibles sur cet appareil',
            GnssAvailability.permissionDenied => 'Permission de localisation',
            _ => 'inactifs',
          }),
          findsOneWidget,
        );
        expect(find.textContaining('Satellites vus'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await source.controller.close();
    },
  );
}
