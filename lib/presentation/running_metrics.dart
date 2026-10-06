import 'package:flutter/material.dart';
import 'formatters.dart';

/// Mesures communes aux courses libres et guidées, pauses exclues.
class RunningMetrics extends StatelessWidget {
  const RunningMetrics({
    super.key,
    required this.activeSeconds,
    required this.distance,
    required this.metresPerSecond,
    this.summary = false,
  });
  final int activeSeconds;
  final double distance;
  final double? metresPerSecond;
  final bool summary;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 8,
    children: [
      Text('Durée active : ${duration(activeSeconds)}'),
      Text('Distance courue : ${metres(distance)}'),
      Text(
        '${summary ? 'Vitesse moyenne' : 'Vitesse'} : ${speed(metresPerSecond)}',
      ),
      Text(
        '${summary ? 'Allure moyenne' : 'Allure'} : ${pace(metresPerSecond)}',
      ),
    ],
  );
}
