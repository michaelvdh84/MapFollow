/// Platform-independent values. Coordinates use WGS84; lengths use metres.
library;

enum CueDirection { left, right, straight, uTurn }

enum RunStatus { running, paused, interrupted, finished }

/// Une course guidée suit un itinéraire ; une course libre produit son itinéraire.
enum RunMode { guided, free }

/// Le téléphone choisit les constellations ; ce profil règle uniquement les demandes GPS.
enum LocationProfile { precise, balanced, autonomy }

enum TraversalDirection { outbound, returning }

/// Le choix manuel concerne les prochains points, jamais les points déjà sauvegardés.
enum TraversalControl { automatic, outbound, returning }

class RoutePoint {
  const RoutePoint(
    this.latitude,
    this.longitude, {
    this.elevation,
    this.time,
    this.traversal,
  });
  final double latitude;
  final double longitude;
  final double? elevation;
  final DateTime? time;
  final TraversalDirection? traversal;
  RoutePoint withTraversal(TraversalDirection? value) => RoutePoint(
    latitude,
    longitude,
    elevation: elevation,
    time: time,
    traversal: value,
  );
  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'ele': elevation,
    'time': time?.toUtc().toIso8601String(),
    if (traversal != null) 'traversal': traversal!.name,
  };
  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
    (json['lat'] as num).toDouble(),
    (json['lon'] as num).toDouble(),
    elevation: (json['ele'] as num?)?.toDouble(),
    time: json['time'] == null ? null : DateTime.parse(json['time'] as String),
    traversal: TraversalDirection.values
        .where((value) => value.name == json['traversal'])
        .firstOrNull,
  );
}

class RouteSegment {
  RouteSegment(Iterable<RoutePoint> points)
    : points = List.unmodifiable(points);
  final List<RoutePoint> points;
  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
  };
  factory RouteSegment.fromJson(Map<String, dynamic> json) => RouteSegment(
    (json['points'] as List).map(
      (p) => RoutePoint.fromJson(Map<String, dynamic>.from(p as Map)),
    ),
  );
}

class NavigationCue {
  const NavigationCue({
    required this.id,
    required this.point,
    required this.direction,
    this.label,
    this.estimated = false,
  });
  final String id;
  final RoutePoint point;
  final CueDirection direction;
  final String? label;
  final bool estimated;
  Map<String, dynamic> toJson() => {
    'id': id,
    'point': point.toJson(),
    'direction': direction.name,
    'label': label,
    'estimated': estimated,
  };
  factory NavigationCue.fromJson(Map<String, dynamic> json) => NavigationCue(
    id: json['id'] as String,
    point: RoutePoint.fromJson(Map<String, dynamic>.from(json['point'] as Map)),
    direction: CueDirection.values.byName(json['direction'] as String),
    label: json['label'] as String?,
    estimated: json['estimated'] as bool? ?? false,
  );
}

class Route {
  Route({
    required this.id,
    required this.name,
    required Iterable<RouteSegment> segments,
    Iterable<NavigationCue> cues = const [],
    this.sourceFormat = 'gpx',
  }) : segments = List.unmodifiable(segments),
       cues = List.unmodifiable(cues);
  final String id;
  final String name;
  final List<RouteSegment> segments;
  final List<NavigationCue> cues;
  final String sourceFormat;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'format': sourceFormat,
    'segments': segments.map((s) => s.toJson()).toList(),
    'cues': cues.map((c) => c.toJson()).toList(),
  };
  factory Route.fromJson(Map<String, dynamic> json) => Route(
    id: json['id'] as String,
    name: json['name'] as String,
    sourceFormat: json['format'] as String,
    segments: (json['segments'] as List).map(
      (s) => RouteSegment.fromJson(Map<String, dynamic>.from(s as Map)),
    ),
    cues: (json['cues'] as List).map(
      (c) => NavigationCue.fromJson(Map<String, dynamic>.from(c as Map)),
    ),
  );
}

class LocationFix {
  const LocationFix({
    required this.point,
    required this.timestamp,
    required this.accuracy,
    this.speed,
    this.heading,
  });
  final RoutePoint point;
  final DateTime timestamp;
  final double accuracy;

  /// Absence de mesure distincte de l'immobilité (zéro), notamment pour l'allure.
  final double? speed;
  final double? heading;
  Map<String, dynamic> toJson() => {
    'point': point.toJson(),
    'timestamp': timestamp.toUtc().toIso8601String(),
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
  };
  factory LocationFix.fromJson(Map<String, dynamic> json) => LocationFix(
    point: RoutePoint.fromJson(Map<String, dynamic>.from(json['point'] as Map)),
    timestamp: DateTime.parse(json['timestamp'] as String),
    accuracy: (json['accuracy'] as num).toDouble(),
    speed: (json['speed'] as num?)?.toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
  );
}

class RunSession {
  RunSession({
    required this.id,
    this.routeId,
    this.mode = RunMode.guided,
    this.name = '',
    this.generatedRouteId,
    required this.startedAt,
    required this.simulated,
    this.status = RunStatus.running,
    this.endedAt,
    this.activeSeconds = 0,
    this.distance = 0,
    this.progress = 0,
    this.locationProfile = LocationProfile.precise,
    this.traversalControl = TraversalControl.automatic,
    Set<String>? announcedCueIds,
    List<List<LocationFix>>? segments,
  }) : announcedCueIds = announcedCueIds ?? {},
       segments = segments ?? [[]];
  final String id;

  /// Itinéraire à suivre : absent lorsque l'on enregistre un Run libre.
  final String? routeId;
  final RunMode mode;
  String name;

  /// Lien vers le parcours créé à la fin ; distinct de l'itinéraire de guidage.
  String? generatedRouteId;
  final DateTime startedAt;
  final bool simulated;
  RunStatus status;
  DateTime? endedAt;
  int activeSeconds;
  double distance;
  double progress;
  final LocationProfile locationProfile;
  TraversalControl traversalControl;
  final Set<String> announcedCueIds;
  final List<List<LocationFix>> segments;
  Map<String, dynamic> toJson() => {
    'id': id,
    'routeId': routeId,
    'mode': mode.name,
    'name': name,
    'generatedRouteId': generatedRouteId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'simulated': simulated,
    'status': status.name,
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'activeSeconds': activeSeconds,
    'distance': distance,
    'progress': progress,
    'locationProfile': locationProfile.name,
    'traversalControl': traversalControl.name,
    'announcedCueIds': announcedCueIds.toList(),
  };
  factory RunSession.fromJson(Map<String, dynamic> json) => RunSession(
    id: json['id'] as String,
    routeId: json['routeId'] as String?,
    // Les données de la version 0.1 étaient toutes des courses guidées.
    mode: json['mode'] == null
        ? RunMode.guided
        : RunMode.values.byName(json['mode'] as String),
    name: json['name'] as String? ?? '',
    generatedRouteId: json['generatedRouteId'] as String?,
    startedAt: DateTime.parse(json['startedAt'] as String),
    simulated: json['simulated'] as bool,
    status: RunStatus.values.byName(json['status'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
    activeSeconds: json['activeSeconds'] as int,
    distance: (json['distance'] as num).toDouble(),
    progress: (json['progress'] as num).toDouble(),
    locationProfile:
        LocationProfile.values
            .where((value) => value.name == json['locationProfile'])
            .firstOrNull ??
        LocationProfile.precise,
    traversalControl:
        TraversalControl.values
            .where((value) => value.name == json['traversalControl'])
            .firstOrNull ??
        TraversalControl.automatic,
    announcedCueIds: Set<String>.from(json['announcedCueIds'] as List),
  );
}

class GuidanceSettings {
  const GuidanceSettings({
    this.warningDistance = 20,
    this.offRouteDistance = 30,
    this.voiceVolume = 1,
    this.locationProfile = LocationProfile.balanced,
  });
  final double warningDistance;
  final double offRouteDistance;
  final double voiceVolume;
  final LocationProfile locationProfile;
  GuidanceSettings copyWith({
    double? warningDistance,
    double? offRouteDistance,
    double? voiceVolume,
    LocationProfile? locationProfile,
  }) => GuidanceSettings(
    warningDistance: warningDistance ?? this.warningDistance,
    offRouteDistance: offRouteDistance ?? this.offRouteDistance,
    voiceVolume: voiceVolume ?? this.voiceVolume,
    locationProfile: locationProfile ?? this.locationProfile,
  );
  Map<String, dynamic> toJson() => {
    'warningDistance': warningDistance,
    'offRouteDistance': offRouteDistance,
    'voiceVolume': voiceVolume,
    'locationProfile': locationProfile.name,
  };
  factory GuidanceSettings.fromJson(Map<String, dynamic> json) =>
      GuidanceSettings(
        locationProfile:
            LocationProfile.values
                .where((value) => value.name == json['locationProfile'])
                .firstOrNull ??
            LocationProfile.balanced,
        warningDistance: ((json['warningDistance'] as num?)?.toDouble() ?? 20)
            .clamp(10, 200),
        offRouteDistance: ((json['offRouteDistance'] as num?)?.toDouble() ?? 30)
            .clamp(15, 100),
        voiceVolume: ((json['voiceVolume'] as num?)?.toDouble() ?? 1).clamp(
          0,
          1,
        ),
      );
}
