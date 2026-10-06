/// Conversion des mètres en libellé français pour les écrans de course.
String metres(double value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(2)} km'
    : '${value.round()} m';

/// Une durée active s'affiche en heures, minutes et secondes, pauses exclues.
String duration(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

String speed(double? metresPerSecond) =>
    metresPerSecond == null || !metresPerSecond.isFinite || metresPerSecond < 0
    ? '--'
    : '${(metresPerSecond * 3.6).toStringAsFixed(1)} km/h';

/// Arrondir la durée totale avant de séparer minutes et secondes évite « 5:60 ».
String pace(double? metresPerSecond) {
  if (metresPerSecond == null ||
      !metresPerSecond.isFinite ||
      metresPerSecond <= 0) {
    return '--';
  }
  final seconds = (1000 / metresPerSecond).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} min/km';
}
