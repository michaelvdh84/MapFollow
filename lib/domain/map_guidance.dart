import 'dart:math' as math;

import 'geo.dart';
import 'models.dart';
import 'navigation.dart';

/// Builds choices from shared OSM node IDs, never from geometric crossings.
/// Matching is conservative: ambiguous or unmapped sections keep the GPX line.
class OsmGuidanceBuilder {
  const OsmGuidanceBuilder();

  Route prepare(Route route, Map<String, dynamic> response, {DateTime? now}) {
    final graph = _Graph.fromJson(response);
    final prepared = PreparedRoute(route);
    final cues = <NavigationCue>[
      ...route.cues.where((cue) => cue.origin == CueOrigin.file),
    ];
    var mapped = 0, sampled = 0, ambiguous = 0;
    final candidates = <_Passage>[];
    for (final edge in prepared.edges) {
      final steps = math.max(1, (edge.length / 10).ceil());
      for (var step = 0; step <= steps; step++) {
        if (++sampled > 20000) {
          throw const FormatException(
            'Parcours trop long pour la préparation.',
          );
        }
        if (graph.match(interpolate(edge.a, edge.b, step / steps)) != null) {
          mapped++;
        }
      }
      for (final node in graph.junctionsNear(edge.a, edge.b)) {
        final projection = projectToEdge(node.point, edge.a, edge.b);
        if (projection.distance > 15) continue;
        final passage = _Passage(
          node,
          edge.start + edge.length * projection.fraction,
          projection.distance,
          edge.segment,
        );
        final existing = candidates.indexWhere(
          (p) =>
              p.node.id == node.id &&
              p.segment == edge.segment &&
              (p.distance - passage.distance).abs() < 35,
        );
        if (existing < 0) {
          candidates.add(passage);
        } else if (projection.distance < candidates[existing].offset) {
          candidates[existing] = passage;
        }
      }
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    for (final passage in candidates) {
      final before = _at(prepared, passage.distance - 20, passage.segment);
      final after = _at(prepared, passage.distance + 20, passage.segment);
      if (before == null || after == null) continue;
      final incoming = graph.branch(passage.node, before);
      final outgoing = graph.branch(passage.node, after);
      if (incoming == null || outgoing == null) {
        ambiguous++;
        continue;
      }
      final turn = angleDifference(
        bearingBetween(incoming.point, passage.node.point),
        bearingBetween(passage.node.point, outgoing.point),
      );
      final direction = incoming.id == outgoing.id
          ? CueDirection.uTurn
          : turn.abs() <= 35
          ? CueDirection.straight
          : turn > 0
          ? CueDirection.right
          : CueDirection.left;
      _add(
        cues,
        NavigationCue(
          id: 'osm-${passage.node.id}-${passage.distance.round()}',
          point: passage.node.point,
          direction: direction,
          origin: CueOrigin.openStreetMap,
          routeDistance: passage.distance,
        ),
        prepared,
      );
    }
    // Reversals can occur mid-way along a path, without an OSM junction.
    // Require map matches on both sides, on the same connected path.
    for (final estimate in prepared.cues.where(
      (c) => c.cue.estimated && c.cue.direction == CueDirection.uTurn,
    )) {
      final edge = prepared.edges
          .where(
            (e) => e.start <= estimate.distance && e.end >= estimate.distance,
          )
          .firstOrNull;
      if (edge == null) continue;
      final before = _at(prepared, estimate.distance - 20, edge.segment);
      final after = _at(prepared, estimate.distance + 20, edge.segment);
      if (before == null || after == null) continue;
      final a = graph.match(before), b = graph.match(after);
      if (a == null || b == null || !a.connectedTo(b)) continue;
      final center = graph.match(estimate.cue.point);
      if (center == null || !center.connectedTo(a)) continue;
      _add(
        cues,
        NavigationCue(
          id: 'osm-reversal-${estimate.distance.round()}',
          point: estimate.cue.point,
          direction: CueDirection.uTurn,
          origin: CueOrigin.openStreetMap,
          routeDistance: estimate.distance,
        ),
        prepared,
      );
    }
    final coverage = sampled == 0 ? 0.0 : mapped / sampled;
    final status = coverage == 0
        ? MapPreparationStatus.empty
        : coverage < .9 || ambiguous > 0
        ? MapPreparationStatus.partial
        : MapPreparationStatus.prepared;
    return route.copyWith(
      cues: cues,
      mapPreparationStatus: status,
      mapPreparedAt: now ?? DateTime.now().toUtc(),
      mapPreparationMessage: switch (status) {
        MapPreparationStatus.empty => 'Aucun chemin reconnu. Suivez le tracé.',
        MapPreparationStatus.partial =>
          'Indications partielles. Sur les portions ambiguës, suivez le tracé.',
        _ =>
          'Indications préparées avec OpenStreetMap. Suivez le tracé entre les indications.',
      },
    );
  }

  void _add(
    List<NavigationCue> cues,
    NavigationCue cue,
    PreparedRoute prepared,
  ) {
    // Explicit instructions from a file take precedence near the same passage.
    if (cues.any((existing) {
      final distance =
          existing.routeDistance ??
          prepared.cues
              .where((c) => c.cue.id == existing.id)
              .firstOrNull
              ?.distance;
      return distance != null && (distance - cue.routeDistance!).abs() < 25;
    })) {
      return;
    }
    cues.add(cue);
  }

  RoutePoint? _at(PreparedRoute route, double distance, int segment) {
    for (final edge in route.edges) {
      if (edge.segment == segment &&
          edge.start <= distance &&
          edge.end >= distance) {
        return interpolate(
          edge.a,
          edge.b,
          (distance - edge.start) / edge.length,
        );
      }
    }
    return null;
  }
}

class _Passage {
  const _Passage(this.node, this.distance, this.offset, this.segment);
  final _Node node;
  final double distance, offset;
  final int segment;
}

class _Node {
  _Node(this.id, this.point);
  final int id;
  final RoutePoint point;
  final Map<int, _Node> neighbors = {};
}

class _Edge {
  const _Edge(this.a, this.b);
  final _Node a, b;
  bool connectedTo(_Edge other) =>
      a.id == other.a.id ||
      a.id == other.b.id ||
      b.id == other.a.id ||
      b.id == other.b.id;
}

class _Graph {
  _Graph.fromJson(Map<String, dynamic> json) {
    final elements = json['elements'];
    if (elements is! List || elements.length > 100000) {
      throw const FormatException(
        'Données cartographiques invalides ou trop volumineuses.',
      );
    }
    final nodes = <int, _Node>{};
    for (final element in elements.whereType<Map>()) {
      if (element['type'] != 'node') continue;
      final id = element['id'], lat = element['lat'], lon = element['lon'];
      if (id is! int ||
          lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        continue;
      }
      nodes[id] = _Node(id, RoutePoint(lat.toDouble(), lon.toDouble()));
    }
    final seen = <String>{};
    for (final way in elements.whereType<Map>()) {
      if (way['type'] != 'way' || way['nodes'] is! List) continue;
      final tags = way['tags'];
      if (tags is! Map ||
          tags['highway'] == null ||
          {
            'motorway',
            'motorway_link',
            'trunk',
            'trunk_link',
            'construction',
            'proposed',
          }.contains(tags['highway']) ||
          tags['foot'] == 'no' ||
          (tags['access'] == 'private' && tags['foot'] != 'yes')) {
        continue;
      }
      final ids = way['nodes'] as List;
      for (var i = 1; i < ids.length; i++) {
        final a = nodes[ids[i - 1]], b = nodes[ids[i]];
        if (a == null || b == null || a.id == b.id) continue;
        final key = a.id < b.id ? '${a.id}:${b.id}' : '${b.id}:${a.id}';
        if (!seen.add(key)) continue;
        if (seen.length > 75000) {
          throw const FormatException('Trop de chemins dans la zone demandée.');
        }
        a.neighbors[b.id] = b;
        b.neighbors[a.id] = a;
        final edge = _Edge(a, b);
        for (final cell in _cells(a.point, b.point, 0)) {
          (_edges[cell] ??= []).add(edge);
        }
      }
    }
    for (final node in nodes.values.where((n) => n.neighbors.length >= 3)) {
      final cell = _cell(node.point);
      (_junctions[cell] ??= []).add(node);
    }
  }
  final _edges = <String, List<_Edge>>{};
  final _junctions = <String, List<_Node>>{};

  Iterable<_Node> junctionsNear(RoutePoint a, RoutePoint b) sync* {
    for (final cell in _cells(a, b, 1)) {
      yield* _junctions[cell] ?? const [];
    }
  }

  _Edge? match(RoutePoint point) {
    _Edge? best;
    var nearest = 20.0;
    final scored = <(_Edge, double)>[];
    final seen = <_Edge>{};
    for (final cell in _cells(point, point, 1)) {
      for (final edge in _edges[cell] ?? <_Edge>[]) {
        if (!seen.add(edge)) continue;
        final offset = projectToEdge(
          point,
          edge.a.point,
          edge.b.point,
        ).distance;
        if (offset > 20) continue;
        scored.add((edge, offset));
        if (offset <= nearest) {
          best = edge;
          nearest = offset;
        }
      }
    }
    if (best == null) return null;
    // Nearby parallel ways cannot be selected reliably from a GPX alone.
    if (scored.any(
      (entry) => entry.$2 - nearest < 5 && !_sameCorridor(entry.$1, best!),
    )) {
      return null;
    }
    return best;
  }

  _Node? branch(_Node node, RoutePoint target) {
    final heading = bearingBetween(node.point, target);
    final scores = <(_Node, double, Set<int>)>[];
    for (final neighbor in node.neighbors.values) {
      var previous = node, current = neighbor;
      var traveled = distanceBetween(node.point, neighbor.point);
      var offset = projectToEdge(target, node.point, neighbor.point).distance;
      final ids = <int>{node.id, neighbor.id};
      while (traveled < 30 &&
          current.neighbors.length == 2 &&
          ids.length < 100) {
        final next = current.neighbors.values
            .where((n) => n.id != previous.id)
            .single;
        if (!ids.add(next.id)) break;
        offset = math.min(
          offset,
          projectToEdge(target, current.point, next.point).distance,
        );
        traveled += distanceBetween(current.point, next.point);
        previous = current;
        current = next;
      }
      final delta = angleDifference(
        heading,
        bearingBetween(node.point, current.point),
      ).abs();
      if (delta > 50 || offset > 20) continue;
      scores.add((current, delta, ids));
    }
    scores.sort((a, b) => a.$2.compareTo(b.$2));
    if (scores.isEmpty ||
        (scores.length > 1 && scores[1].$2 - scores[0].$2 < 15)) {
      return null;
    }
    // Also reject a neighboring unconnected way near this portion.
    final edge = match(target);
    if (edge == null ||
        (!scores.first.$3.contains(edge.a.id) &&
            !scores.first.$3.contains(edge.b.id))) {
      return null;
    }
    return scores.first.$1;
  }

  bool _sameCorridor(_Edge a, _Edge b) {
    if (a.connectedTo(b)) return true;
    // Dense OSM shape points along one path are not competing parallel ways.
    final queue = <(_Node, double)>[(a.a, 0), (a.b, 0)];
    final visited = <int>{};
    for (var i = 0; i < queue.length && i < 100; i++) {
      final (node, traveled) = queue[i];
      if (!visited.add(node.id)) continue;
      if (node.id == b.a.id || node.id == b.b.id) return true;
      for (final neighbor in node.neighbors.values) {
        final next = traveled + distanceBetween(node.point, neighbor.point);
        if (next <= 10) queue.add((neighbor, next));
      }
    }
    return false;
  }

  String _cell(RoutePoint point) =>
      '${(point.latitude / .001).floor()}:${(point.longitude / .001).floor()}';
  Iterable<String> _cells(RoutePoint a, RoutePoint b, int padding) sync* {
    final south = (math.min(a.latitude, b.latitude) / .001).floor() - padding;
    final north = (math.max(a.latitude, b.latitude) / .001).floor() + padding;
    final west = (math.min(a.longitude, b.longitude) / .001).floor() - padding;
    final east = (math.max(a.longitude, b.longitude) / .001).floor() + padding;
    if ((north - south + 1) * (east - west + 1) > 10000) {
      throw const FormatException('Zone de préparation trop étendue.');
    }
    for (var lat = south; lat <= north; lat++) {
      for (var lon = west; lon <= east; lon++) {
        yield '$lat:$lon';
      }
    }
  }
}
