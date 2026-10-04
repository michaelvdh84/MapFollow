import 'dart:convert';

import 'package:xml/xml.dart';

import '../domain/models.dart';

class RouteImportException implements Exception {
  const RouteImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses GPX, TCX and PWX route files without platform dependencies.
class RouteImporter {
  static const maxInputBytes = 10 * 1024 * 1024;
  static const maxPoints = 100000;
  static int _routeNumber = 0;

  List<Route> parse(String content, {required String fileName}) {
    if (utf8.encode(content).length > maxInputBytes) {
      throw const RouteImportException(
        'Le fichier dépasse la taille maximale de 10 Mo.',
      );
    }
    XmlDocument document;
    try {
      document = XmlDocument.parse(content);
    } on XmlException {
      throw const RouteImportException('Le fichier de parcours est mal formé.');
    }
    final root = _local(document.rootElement);
    final format = switch (root) {
      'gpx' => 'gpx',
      'trainingcenterdatabase' => 'tcx',
      'workout' || 'pwx' => 'pwx',
      _ => '',
    };
    if (format.isEmpty ||
        (format == 'gpx' && !_validGpxNamespace(document.rootElement))) {
      throw const RouteImportException(
        'Format de parcours non pris en charge.',
      );
    }
    final pointNames = switch (format) {
      'gpx' => {'trkpt', 'rtept'},
      'tcx' => {'trackpoint'},
      _ => {'sample'},
    };
    if (document.descendants
            .whereType<XmlElement>()
            .where((e) => pointNames.contains(_local(e)))
            .length >
        maxPoints) {
      throw const RouteImportException(
        'Le fichier contient plus de 100 000 points GPS.',
      );
    }
    final routes = switch (format) {
      'gpx' => _gpx(document),
      'tcx' => _tcx(document),
      'pwx' => _pwx(document),
      _ => <Route>[],
    };
    if (routes.isEmpty) {
      throw const RouteImportException(
        'Aucun point GPS valide trouvé dans ce fichier.',
      );
    }
    return routes;
  }

  String _local(XmlElement e) => e.name.local.toLowerCase();
  bool _validGpxNamespace(XmlElement root) {
    final uri = root.name.namespaceUri ?? '';
    return uri.isEmpty ||
        uri == 'http://www.topografix.com/GPX/1/0' ||
        uri == 'http://www.topografix.com/GPX/1/1';
  }

  Iterable<XmlElement> _children(XmlElement e, String name) =>
      e.childElements.where((c) => _local(c) == name);
  XmlElement? _child(XmlElement e, String name) =>
      _children(e, name).firstOrNull;
  String? _text(XmlElement e, String name) => _child(e, name)?.innerText.trim();
  String? _deepText(XmlElement e, String name) =>
      _text(e, name) ??
      e.descendants
          .whereType<XmlElement>()
          .where((x) => _local(x) == name.toLowerCase())
          .map((x) => x.innerText.trim())
          .firstOrNull;

  List<Route> _gpx(XmlDocument doc) {
    final result = <Route>[];
    for (final track in doc.descendants.whereType<XmlElement>().where(
      (e) => _local(e) == 'trk',
    )) {
      final segs = <RouteSegment>[];
      for (final trkseg in _children(track, 'trkseg')) {
        final pts = _children(trkseg, 'trkpt').map(_gpxPoint).toList();
        _appendSplit(segs, pts);
      }
      _addIfValid(result, _text(track, 'name') ?? 'Parcours', segs, 'gpx');
    }
    for (final rte in doc.descendants.whereType<XmlElement>().where(
      (e) => _local(e) == 'rte',
    )) {
      final segs = <RouteSegment>[];
      final points = _children(rte, 'rtept').toList();
      _appendSplit(segs, points.map(_gpxPoint).toList());
      final cues = <NavigationCue>[];
      for (var i = 0; i < points.length; i++) {
        final point = _gpxPoint(points[i]);
        final direction = _gpxTurn(points[i]);
        if (point != null && direction != null) {
          cues.add(_cue(point, direction, 'gpx-$i'));
        }
      }
      _addIfValid(
        result,
        _text(rte, 'name') ?? 'Parcours',
        segs,
        'gpx',
        cues: cues,
      );
    }
    return result;
  }

  RoutePoint? _gpxPoint(XmlElement e) => _point(
    e.getAttribute('lat'),
    e.getAttribute('lon'),
    _text(e, 'ele'),
    _text(e, 'time'),
  );
  CueDirection? _gpxTurn(XmlElement e) {
    final turns = e.descendants
        .whereType<XmlElement>()
        .where(
          (x) => const {'turn', 'turntype', 'turn_type'}.contains(_local(x)),
        )
        .map((x) => x.innerText.trim().toLowerCase());
    for (final value in turns) {
      final d = _direction(value);
      if (d != null) return d;
    }
    return null;
  }

  List<Route> _tcx(XmlDocument doc) {
    final result = <Route>[];
    final course = doc.descendants.whereType<XmlElement>().where(
      (e) => _local(e) == 'course',
    );
    for (final c in course) {
      final cues = <NavigationCue>[];
      final segments = <RouteSegment>[];
      for (final track in _children(c, 'track')) {
        final pts = track.descendants
            .whereType<XmlElement>()
            .where((e) => _local(e) == 'trackpoint')
            .map(
              (tp) => _point(
                _deepText(tp, 'latitudeDegrees'),
                _deepText(tp, 'longitudeDegrees'),
                _deepText(tp, 'altitudeMeters'),
                _deepText(tp, 'time'),
              ),
            )
            .toList();
        _appendSplit(segments, pts);
      }
      for (final cp in c.descendants.whereType<XmlElement>().where(
        (e) => _local(e) == 'coursepoint',
      )) {
        final p = _point(
          _deepText(cp, 'latitudeDegrees'),
          _deepText(cp, 'longitudeDegrees'),
          null,
          null,
        );
        final dir = _direction(_text(cp, 'pointtype')?.toLowerCase() ?? '');
        if (p != null && dir != null) {
          cues.add(_cue(p, dir, 'tcx-course-${cues.length}'));
        }
      }
      _addIfValid(
        result,
        _text(c, 'name') ?? 'Parcours',
        segments,
        'tcx',
        cues: cues,
      );
    }
    if (result.isNotEmpty) return result;
    // Activities may contain multiple laps and tracks; retain each Track as a segment.
    for (final activity in doc.descendants.whereType<XmlElement>().where(
      (e) => _local(e) == 'activity',
    )) {
      final segments = <RouteSegment>[];
      for (final track in activity.descendants.whereType<XmlElement>().where(
        (e) => _local(e) == 'track',
      )) {
        final pts = track.descendants
            .whereType<XmlElement>()
            .where((e) => _local(e) == 'trackpoint')
            .map(
              (tp) => _point(
                _deepText(tp, 'latitudeDegrees'),
                _deepText(tp, 'longitudeDegrees'),
                _deepText(tp, 'altitudeMeters'),
                _deepText(tp, 'time'),
              ),
            )
            .toList();
        _appendSplit(segments, pts);
      }
      _addIfValid(result, _text(activity, 'id') ?? 'Activité', segments, 'tcx');
    }
    return result;
  }

  List<Route> _pwx(XmlDocument doc) {
    final workouts = _local(doc.rootElement) == 'workout'
        ? [doc.rootElement]
        : doc.descendants
              .whereType<XmlElement>()
              .where((e) => _local(e) == 'workout')
              .toList();
    final routes = <Route>[];
    for (final workout in workouts) {
      final segments = <RouteSegment>[];
      final start = DateTime.tryParse(_text(workout, 'time') ?? '');
      final points = workout.descendants
          .whereType<XmlElement>()
          .where((e) => _local(e) == 'sample')
          .map((sample) {
            final date = _pwxSampleTime(start, _text(sample, 'timeoffset'));
            return _point(
              _text(sample, 'lat'),
              _text(sample, 'lon'),
              _text(sample, 'altitude'),
              date?.toIso8601String(),
            );
          })
          .toList();
      _appendSplit(segments, points);
      _addIfValid(
        routes,
        _text(workout, 'title') ?? 'Parcours',
        segments,
        'pwx',
      );
    }
    return routes;
  }

  DateTime? _pwxSampleTime(DateTime? start, String? offsetText) {
    final offsetSeconds = num.tryParse(offsetText ?? '')?.toDouble();
    if (start == null || offsetSeconds == null || !offsetSeconds.isFinite) {
      return null;
    }
    final milliseconds = offsetSeconds * 1000;
    if (!milliseconds.isFinite || milliseconds.abs() > 8640000000000000) {
      return null;
    }
    try {
      return start.add(Duration(milliseconds: milliseconds.round()));
    } on ArgumentError {
      return null;
    }
  }

  RoutePoint? _point(
    String? latText,
    String? lonText,
    String? eleText,
    String? timeText,
  ) {
    final lat = num.tryParse(latText?.trim() ?? '')?.toDouble();
    final lon = num.tryParse(lonText?.trim() ?? '')?.toDouble();
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }
    final ele = num.tryParse(eleText ?? '')?.toDouble();
    DateTime? time;
    try {
      if (timeText != null) time = DateTime.parse(timeText);
    } on FormatException {
      time = null;
    }
    return RoutePoint(
      lat,
      lon,
      elevation: ele?.isFinite == true ? ele : null,
      time: time,
    );
  }

  void _appendSplit(List<RouteSegment> output, List<RoutePoint?> points) {
    var current = <RoutePoint>[];
    void flush() {
      if (current.isNotEmpty) output.add(RouteSegment(current));
      current = [];
    }

    for (final point in points) {
      if (point == null) {
        flush();
        continue;
      }
      current.add(point);
      if (current.length > maxPoints) {
        throw const RouteImportException(
          'Le fichier contient plus de 100 000 points GPS.',
        );
      }
    }
    flush();
  }

  void _addIfValid(
    List<Route> output,
    String name,
    List<RouteSegment> segments,
    String format, {
    List<NavigationCue> cues = const [],
  }) {
    final pointCount = segments.fold<int>(0, (n, s) => n + s.points.length);
    if (pointCount > maxPoints) {
      throw const RouteImportException(
        'Le fichier contient plus de 100 000 points GPS.',
      );
    }
    final unique = <String>{};
    for (final s in segments) {
      for (final p in s.points) {
        unique.add('${p.latitude},${p.longitude}');
      }
    }
    if (unique.length < 2) return;
    final index = _routeNumber++;
    output.add(
      Route(
        id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
        name: name,
        segments: segments,
        cues: cues,
        sourceFormat: format,
      ),
    );
  }

  NavigationCue _cue(RoutePoint p, CueDirection d, String id) =>
      NavigationCue(id: id, point: p, direction: d);
  CueDirection? _direction(String value) {
    final v = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (v.contains('uturn') || v == 'u') return CueDirection.uTurn;
    if (v.contains('sharpleft') || v == 'left') return CueDirection.left;
    if (v.contains('sharpright') || v == 'right') return CueDirection.right;
    if (v == 'straight') return CueDirection.straight;
    return null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
