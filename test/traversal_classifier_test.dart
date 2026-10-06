import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfollow/domain/geo.dart';
import 'package:mapfollow/domain/models.dart';
import 'package:mapfollow/domain/traversal_classifier.dart';

const outbound = TraversalDirection.outbound;
const returning = TraversalDirection.returning;

LocationFix fix(double x, [double y = 0, TraversalDirection? direction]) =>
    LocationFix(
      point: RoutePoint(
        y / earthRadius * 180 / math.pi,
        x / earthRadius * 180 / math.pi,
        traversal: direction,
      ),
      timestamp: DateTime.utc(2026),
      accuracy: 3,
    );

TraversalDirection add(
  TraversalClassifier classifier,
  double x, {
  double y = 0,
  bool newSegment = false,
  TraversalControl control = TraversalControl.automatic,
}) => classifier.add(fix(x, y), newSegment: newSegment, control: control);

TraversalClassifier straightOutbound() {
  final classifier = TraversalClassifier();
  for (var x = 0; x <= 200; x += 10) {
    expect(add(classifier, x.toDouble()), outbound);
  }
  return classifier;
}

void main() {
  test('first pass is outbound, reverse is return, third pass is outbound', () {
    final classifier = straightOutbound();
    final reverse = <TraversalDirection>[];
    for (var x = 190; x >= 0; x -= 10) {
      reverse.add(add(classifier, x.toDouble()));
    }
    expect(reverse.take(2), everyElement(outbound));
    expect(reverse.skip(4), everyElement(returning));
    final third = <TraversalDirection>[];
    for (var x = 10; x <= 200; x += 10) {
      third.add(add(classifier, x.toDouble()));
    }
    expect(third.first, returning);
    expect(third.skip(4), everyElement(outbound));
  });

  test('three positions must also span at least fifteen metres', () {
    final classifier = straightOutbound();
    expect(add(classifier, 170, newSegment: true), outbound);
    expect(add(classifier, 167), outbound);
    expect(add(classifier, 164), outbound);
    expect(add(classifier, 161), outbound);
    expect(add(classifier, 158), outbound);
    expect(add(classifier, 155), outbound);
    // La première position de confirmation est à 167 m : l'écart atteint 17 m.
    expect(add(classifier, 150), returning);
  });

  test('a segment gap breaks edges and the confirmation chain', () {
    final classifier = straightOutbound();
    add(classifier, 190);
    add(classifier, 180);
    expect(add(classifier, 170, newSegment: true), outbound);
    expect(add(classifier, 160), outbound);
    expect(add(classifier, 150), outbound);
    expect(add(classifier, 140), returning);

    final disconnected = TraversalClassifier.fromSegments([
      [fix(0, 0), fix(0, 50)],
      [fix(200, 50), fix(200, 0)],
    ]);
    for (var x = 150; x >= 50; x -= 10) {
      expect(
        add(disconnected, x.toDouble(), y: 50, newSegment: x == 150),
        outbound,
      );
    }
  });

  test('same direction re-entry and orthogonal crossings remain outbound', () {
    final same = straightOutbound();
    for (var x = 20; x <= 160; x += 10) {
      expect(add(same, x.toDouble(), newSegment: x == 20), outbound);
    }
    final crossing = straightOutbound();
    for (var y = -60; y <= 60; y += 10) {
      expect(
        add(crossing, 100, y: y.toDouble(), newSegment: y == -60),
        outbound,
      );
    }
  });

  test('return follows a curved first traversal', () {
    final classifier = TraversalClassifier();
    final points = [
      for (var i = 0; i <= 30; i++)
        (
          100 * math.sin(i * math.pi / 60),
          100 * (1 - math.cos(i * math.pi / 60)),
        ),
    ];
    for (final (x, y) in points) {
      expect(add(classifier, x, y: y), outbound);
    }
    final labels = <TraversalDirection>[];
    for (final (x, y) in points.reversed.skip(1)) {
      labels.add(add(classifier, x, y: y));
    }
    expect(labels.skip(10), everyElement(returning));
  });

  test('small stationary noise cannot confirm a return', () {
    final classifier = straightOutbound();
    add(classifier, 100, newSegment: true);
    for (var i = 0; i < 50; i++) {
      expect(
        add(classifier, 100 + (i.isEven ? 1 : -1), y: i.isEven ? 1 : -1),
        outbound,
      );
    }
  });

  test('a separate parallel path outside the corridor remains outbound', () {
    final classifier = straightOutbound();
    for (var x = 180; x >= 0; x -= 10) {
      expect(
        add(classifier, x.toDouble(), y: 25, newSegment: x == 180),
        outbound,
      );
    }
  });

  test('an opposite close parallel path remains a heuristic ambiguity', () {
    final classifier = straightOutbound();
    final labels = <TraversalDirection>[];
    for (var x = 180; x >= 100; x -= 10) {
      labels.add(add(classifier, x.toDouble(), y: 10, newSegment: x == 180));
    }
    // Sans parcours source, ce chemin synthétique à moins de quinze mètres
    // reste indiscernable d'un retour bruité sur le chemin d'origine.
    expect(labels.skip(4), everyElement(returning));
  });

  test('recent thirty metres cannot serve as a return reference', () {
    final classifier = TraversalClassifier();
    for (var x = 0; x <= 20; x += 5) {
      add(classifier, x.toDouble());
    }
    for (var x = 15; x >= 0; x -= 5) {
      expect(add(classifier, x.toDouble()), outbound);
    }
  });

  test('automatic mode resumes after a manual return on an unvisited path', () {
    final classifier = TraversalClassifier();
    expect(add(classifier, 0, control: TraversalControl.returning), returning);
    expect(add(classifier, 10), returning);
    expect(add(classifier, 20), returning);
    expect(add(classifier, 30), outbound);
  });

  test('an automatic return becomes outbound on a new portion', () {
    final classifier = straightOutbound();
    for (var x = 190; x >= 100; x -= 10) {
      add(classifier, x.toDouble());
    }
    expect(add(classifier, 100, y: 10), returning);
    expect(add(classifier, 100, y: 20), returning);
    expect(add(classifier, 100, y: 30), outbound);
    expect(add(classifier, 100, y: 40), outbound);
  });

  test('manual choices apply immediately and reset automatic confirmation', () {
    final classifier = straightOutbound();
    add(classifier, 190);
    add(classifier, 180);
    expect(add(classifier, 170, control: TraversalControl.outbound), outbound);
    expect(add(classifier, 160), outbound);
    expect(add(classifier, 150), outbound);
    expect(add(classifier, 140), returning);
    expect(add(classifier, 130, control: TraversalControl.outbound), outbound);
    expect(
      add(classifier, 120, control: TraversalControl.returning),
      returning,
    );
    expect(add(classifier, 110), returning);
  });

  test('replay respects saved labels without modifying history', () {
    final history = [
      [for (var x = 0; x <= 200; x += 10) fix(x.toDouble(), 0, outbound)],
      [fix(180, 0, returning), fix(170, 0, returning)],
    ];
    final classifier = TraversalClassifier.fromSegments(history);
    expect(add(classifier, 170, newSegment: true), returning);
    expect(history.last.last.point.traversal, returning);
    expect(history.first.first.point.traversal, outbound);
    expect(history.last.length, 2);
    for (var x = 160; x >= 0; x -= 10) {
      expect(add(classifier, x.toDouble()), returning);
    }
    for (var x = 10; x <= 60; x += 10) {
      add(classifier, x.toDouble());
    }
    expect(add(classifier, 70), outbound);
  });

  test('legacy unlabelled replay infers state without rewriting points', () {
    final history = [
      [
        for (var x = 0; x <= 200; x += 10) fix(x.toDouble()),
        for (var x = 190; x >= 100; x -= 10) fix(x.toDouble()),
      ],
    ];
    final classifier = TraversalClassifier.fromSegments(history);
    expect(add(classifier, 90), returning);
    expect(history.single.last.point.traversal, isNull);
  });

  test('ten thousand points query local edges instead of the full history', () {
    final classifier = TraversalClassifier();
    for (var i = 0; i < 10000; i++) {
      add(classifier, i * 5.0);
    }
    expect(add(classifier, 49990), outbound);
    expect(classifier.lastCandidateCount, lessThan(30));
    add(classifier, 49980);
    add(classifier, 49970);
    expect(add(classifier, 49960), returning);
    expect(classifier.lastCandidateCount, lessThan(30));
  });
}
