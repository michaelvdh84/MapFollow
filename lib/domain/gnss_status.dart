/// Informations éphémères du récepteur ; aucune position ni persistance.
enum GnssAvailability {
  available,
  waiting,
  unavailable,
  permissionDenied,
  inactive,
}

class GnssConstellationCount {
  const GnssConstellationCount({
    required this.code,
    required this.name,
    required this.seen,
    required this.used,
  });
  final String code, name;
  final int seen, used;
}

class GnssSnapshot {
  GnssSnapshot({
    required this.observedAt,
    required this.availability,
    Iterable<GnssConstellationCount> constellations = const [],
  }) : constellations = List.unmodifiable(constellations);
  final DateTime observedAt;
  final GnssAvailability availability;
  final List<GnssConstellationCount> constellations;
  int get seen => constellations.fold(0, (total, c) => total + c.seen);
  int get used => constellations.fold(0, (total, c) => total + c.used);
  bool isStale(DateTime now) =>
      now.difference(observedAt) > const Duration(seconds: 10);
}
