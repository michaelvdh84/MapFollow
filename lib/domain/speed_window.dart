import 'models.dart';

/// Moyenne des vitesses mesurées récemment, sans modifier les mesures exportées.
/// Une mesure absente ne devient pas une immobilité fictive.
class SpeedWindow {
  final List<({DateTime timestamp, double speed})> _samples = [];

  void clear() => _samples.clear();

  void add(LocationFix fix) {
    final speed = fix.speed;
    if (speed == null || !speed.isFinite || speed < 0) {
      clear();
      return;
    }
    _samples.add((timestamp: fix.timestamp, speed: speed));
    _prune(fix.timestamp);
  }

  double? average(DateTime now) {
    _prune(now);
    if (_samples.isEmpty) return null;
    return _samples.fold<double>(0, (sum, sample) => sum + sample.speed) /
        _samples.length;
  }

  void _prune(DateTime now) => _samples.removeWhere(
    (sample) => now.difference(sample.timestamp).inMilliseconds > 5000,
  );
}
