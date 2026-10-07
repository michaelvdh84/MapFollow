/// Diagnostic settings belong to the session, independently of GPS profiles.
enum DiagnosticsMode { normal, diagnostic }

/// Snapshot of the whole device battery, not consumption attributed to the app.
class BatterySample {
  const BatterySample({
    required this.timestamp,
    this.levelPercent,
    this.charging,
    this.temperatureC,
    this.voltageMv,
    this.currentMicroAmps,
    this.chargeMicroAh,
    this.event = 'sample',
  });

  final DateTime timestamp;
  final int? levelPercent;
  final bool? charging;
  final double? temperatureC;
  final int? voltageMv;

  /// Android reports discharge as negative current; unavailable stays null.
  final int? currentMicroAmps;
  final int? chargeMicroAh;
  final String event;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'levelPercent': levelPercent,
    'charging': charging,
    'temperatureC': temperatureC,
    'voltageMv': voltageMv,
    'currentMicroAmps': currentMicroAmps,
    'chargeMicroAh': chargeMicroAh,
    'event': event,
  };

  factory BatterySample.fromJson(Map<String, dynamic> json) => BatterySample(
    timestamp: DateTime.parse(json['timestamp'] as String),
    levelPercent: integer(json['levelPercent'], minimum: 0, maximum: 100),
    charging: json['charging'] is bool ? json['charging'] as bool : null,
    temperatureC: finite(json['temperatureC']),
    voltageMv: integer(json['voltageMv'], minimum: 1),
    currentMicroAmps: integer(json['currentMicroAmps']),
    chargeMicroAh: integer(json['chargeMicroAh'], minimum: 0),
    event: json['event'] as String? ?? 'sample',
  );

  static double? finite(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  /// The unsupported Android property sentinel must never become a reading.
  static int? integer(Object? value, {int? minimum, int? maximum}) {
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      return null;
    }
    final number = value.toInt();
    if (number == -2147483648 ||
        (minimum != null && number < minimum) ||
        (maximum != null && number > maximum)) {
      return null;
    }
    return number;
  }
}
