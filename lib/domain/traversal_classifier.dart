import 'dart:math' as math;

import 'geo.dart';
import 'models.dart';

/// Compare le déplacement enregistré au premier passage voisin. Ce couloir
/// reste une heuristique : deux chemins parallèles proches peuvent ressembler
/// à un retour. Une coupure ne crée ni arête ni distance de confirmation.
class TraversalClassifier {
  TraversalClassifier();

  factory TraversalClassifier.fromSegments(List<List<LocationFix>> segments) {
    final classifier = TraversalClassifier();
    for (final segment in segments) {
      for (var i = 0; i < segment.length; i++) {
        final fix = segment[i];
        classifier.add(
          fix,
          newSegment: i == 0,
          control: TraversalControl.automatic,
        );
        // Les libellés sauvegardés incluent les choix manuels et font foi pour
        // la récupération ; la géométrie conserve le premier passage témoin.
        if (fix.point.traversal case final saved?) {
          classifier._direction = saved;
          classifier._resetConfirmation();
        }
      }
    }
    return classifier;
  }

  static const _cellSize = 25.0;
  static const _corridor = 15.0;
  static const _recentDistance = 30.0;
  final Map<(int, int), List<_Edge>> _grid = {};
  RoutePoint? _origin;
  RoutePoint? _previous;
  var _segment = 0;
  var _distance = 0.0;
  var _nextEdge = 0;
  var _direction = TraversalDirection.outbound;
  TraversalDirection? _pendingDirection;
  RoutePoint? _pendingStart;
  _Match? _pendingFirstMatch;
  _Match? _pendingLastMatch;
  var _pendingCount = 0;
  var _lastCandidateCount = 0;

  /// Nombre d'arêtes locales examinées lors de la dernière classification.
  int get lastCandidateCount => _lastCandidateCount;

  TraversalDirection add(
    LocationFix fix, {
    required bool newSegment,
    required TraversalControl control,
  }) {
    final point = fix.point;
    _origin ??= point;
    if (newSegment) {
      _segment++;
      _previous = null;
      _resetConfirmation();
    }
    _lastCandidateCount = 0;
    final previous = _previous;
    final step = previous == null ? 0.0 : distanceBetween(previous, point);
    final startDistance = _distance;
    _distance += step;

    if (control != TraversalControl.automatic) {
      _direction = control == TraversalControl.outbound
          ? TraversalDirection.outbound
          : TraversalDirection.returning;
      _resetConfirmation();
    } else if (previous != null && step >= 2) {
      final match = _match(previous, point);
      // Une portion encore inconnue redevient Aller après confirmation. Après
      // un choix manuel, Auto applique les mêmes trois positions et quinze
      // mètres, sans réinterpréter les points déjà enregistrés.
      final proposed = match?.direction ?? TraversalDirection.outbound;
      if (proposed == _direction) {
        _resetConfirmation();
      } else {
        _confirm(proposed, point, match, step);
      }
    } else {
      // Le bruit à l'arrêt ne doit pas confirmer un changement de sens.
      _resetConfirmation();
    }

    if (previous != null && step >= 2) {
      _index(
        _Edge(previous, point, startDistance, _distance, _segment, _nextEdge++),
      );
    }
    _previous = point;
    return _direction;
  }

  void _confirm(
    TraversalDirection proposed,
    RoutePoint point,
    _Match? match,
    double step,
  ) {
    final last = _pendingLastMatch;
    final continuous =
        last == null && match == null ||
        last != null &&
            match != null &&
            last.edge.segment == match.edge.segment &&
            (match.progress - last.progress).abs() <= step + 2 * _corridor &&
            (proposed == TraversalDirection.returning
                ? match.progress <= last.progress + 2
                : match.progress >= last.progress - 2);
    if (_pendingDirection != proposed || !continuous) {
      _resetConfirmation();
      _pendingDirection = proposed;
      _pendingStart = point;
      _pendingFirstMatch = match;
    }
    _pendingLastMatch = match;
    _pendingCount++;
    final first = _pendingFirstMatch;
    final span = first != null && match != null
        ? (match.progress - first.progress).abs()
        : distanceBetween(_pendingStart!, point);
    if (_pendingCount >= 3 && span >= 15) {
      _direction = proposed;
      _resetConfirmation();
    }
  }

  void _resetConfirmation() {
    _pendingDirection = null;
    _pendingStart = null;
    _pendingFirstMatch = null;
    _pendingLastMatch = null;
    _pendingCount = 0;
  }

  _Match? _match(RoutePoint previous, RoutePoint point) {
    final (x, y) = _coordinates(point);
    final candidates = <_Edge>{};
    for (
      var column = ((x - _corridor) / _cellSize).floor();
      column <= ((x + _corridor) / _cellSize).floor();
      column++
    ) {
      for (
        var row = ((y - _corridor) / _cellSize).floor();
        row <= ((y + _corridor) / _cellSize).floor();
        row++
      ) {
        candidates.addAll(_grid[(column, row)] ?? const []);
      }
    }
    _lastCandidateCount = candidates.length;
    final heading = bearingBetween(previous, point);
    _Match? earliest;
    for (final edge in candidates) {
      if (edge.endDistance > _distance - _recentDistance) continue;
      final projection = projectToEdge(point, edge.a, edge.b);
      if (projection.distance > _corridor ||
          projectToEdge(previous, edge.a, edge.b).distance > _corridor) {
        continue;
      }
      final angle = angleDifference(heading, edge.heading).abs();
      if (angle > 45 && angle < 135) continue;
      if (earliest == null || edge.order < earliest.edge.order) {
        earliest = _Match(
          edge,
          // Un point proche d'une extrémité progresse encore dans le couloir.
          // Une projection bornée bloquerait sa progression aux extrémités
          // anciennes et retarderait la confirmation après quinze mètres.
          edge.startDistance +
              distanceBetween(edge.a, point) *
                  math.cos(
                    angleDifference(
                          edge.heading,
                          bearingBetween(edge.a, point),
                        ) *
                        math.pi /
                        180,
                  ),
          angle >= 135
              ? TraversalDirection.returning
              : TraversalDirection.outbound,
        );
      }
    }
    return earliest;
  }

  (double, double) _coordinates(RoutePoint point) {
    final origin = _origin!;
    final scale = math.cos(origin.latitude * math.pi / 180);
    return (
      angleDifference(origin.longitude, point.longitude) *
          math.pi /
          180 *
          earthRadius *
          scale,
      (point.latitude - origin.latitude) * math.pi / 180 * earthRadius,
    );
  }

  void _index(_Edge edge) {
    final (ax, ay) = _coordinates(edge.a);
    final (bx, by) = _coordinates(edge.b);
    for (
      var column = (math.min(ax, bx) / _cellSize).floor();
      column <= (math.max(ax, bx) / _cellSize).floor();
      column++
    ) {
      for (
        var row = (math.min(ay, by) / _cellSize).floor();
        row <= (math.max(ay, by) / _cellSize).floor();
        row++
      ) {
        (_grid[(column, row)] ??= []).add(edge);
      }
    }
  }
}

class _Edge {
  _Edge(
    this.a,
    this.b,
    this.startDistance,
    this.endDistance,
    this.segment,
    this.order,
  ) : heading = bearingBetween(a, b);
  final RoutePoint a;
  final RoutePoint b;
  final double startDistance;
  final double endDistance;
  final int segment;
  final int order;
  final double heading;
}

class _Match {
  const _Match(this.edge, this.progress, this.direction);
  final _Edge edge;
  final double progress;
  final TraversalDirection direction;
}
