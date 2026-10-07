import 'geo.dart';
import 'models.dart';

/// Contrôle commun au guidage et à l'enregistrement sans parcours.
/// Aucun accès Android ici : les mêmes règles sont testables avec du faux GPS.
abstract final class LocationQuality {
  static bool hasValidCoordinates(RoutePoint point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90 &&
      point.latitude <= 90 &&
      point.longitude >= -180 &&
      point.longitude <= 180;

  static bool accepts(
    LocationFix fix, {
    required DateTime now,
    LocationFix? previous,
  }) => rejectionReason(fix, now: now, previous: previous) == null;

  /// Codes stables utilisables par les diagnostics locaux, sans coordonnées.
  static String? rejectionReason(
    LocationFix fix, {
    required DateTime now,
    LocationFix? previous,
  }) {
    final age = now.difference(fix.timestamp).inMilliseconds;
    if (!hasValidCoordinates(fix.point)) return 'invalid_coordinates';
    if (!fix.accuracy.isFinite || fix.accuracy < 0 || fix.accuracy > 25) {
      return 'poor_accuracy';
    }
    if (age < -2000 || age > 10000) return 'invalid_age';
    if (previous == null) return null;
    if (!fix.timestamp.isAfter(previous.timestamp)) return 'non_monotonic';
    final seconds =
        fix.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    // L'incertitude des deux positions est ajoutée à la vitesse maximale plausible.
    return distanceBetween(previous.point, fix.point) >
            12 * seconds + fix.accuracy + previous.accuracy
        ? 'implausible_jump'
        : null;
  }
}
