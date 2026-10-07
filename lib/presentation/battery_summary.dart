import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/run_diagnostics.dart';

class BatterySummary extends StatelessWidget {
  const BatterySummary({
    super.key,
    required this.samples,
    this.interrupted = false,
    this.detailed = false,
  });

  final List<BatterySample> samples;
  final bool interrupted;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) return const Text('Batterie non mesurée');
    final first = samples.first;
    final startLevel = first.event == 'start' ? first.levelPercent : null;
    final finished = samples.last.event == 'finish';
    final last = samples.last;
    final complete = startLevel != null && last.levelPercent != null;
    final charging =
        samples.any((sample) => sample.charging == true) ||
        samples.indexed.skip(1).any((entry) {
          final previous = samples[entry.$1 - 1].levelPercent;
          final level = entry.$2.levelPercent;
          return previous != null && level != null && level > previous;
        });
    final missing =
        startLevel == null ||
        samples.any(
          (sample) => sample.levelPercent == null || sample.charging == null,
        );
    final levels = samples
        .where((sample) => sample.levelPercent != null)
        .toList();
    final change = complete ? startLevel - last.levelPercent! : null;
    final summary = !finished
        ? 'Batterie au départ : ${_percent(startLevel)} · bilan à la fin'
        : 'Batterie : ${_percent(startLevel)} → ${_percent(last.levelPercent)}'
              '${change == null
                  ? ''
                  : change >= 0
                  ? ' · baisse $change points'
                  : ' · hausse ${-change} points'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary),
        const Text(
          'Téléphone entier, y compris YouTube Music et les autres applications.',
        ),
        if (charging)
          const Text(
            'Recharge détectée : la baisse ne mesure pas la consommation totale.',
          ),
        if (interrupted)
          const Text(
            'Mesure interrompue : une période de la course est sans relevés.',
          ),
        if (missing)
          const Text('Certaines mesures de batterie sont indisponibles.'),
        if (first.event == 'start' && first.charging != null)
          Text(
            'Charge au départ : ${first.charging! ? 'oui' : 'non'}'
            '${finished && last.charging != null ? ' · à la fin : ${last.charging! ? 'oui' : 'non'}' : ''}',
          ),
        if (detailed && levels.length >= 3) ...[
          const SizedBox(height: 8),
          Semantics(
            label:
                'Évolution de la batterie : ${levels.first.levelPercent} à ${levels.last.levelPercent} pour cent.',
            child: SizedBox(
              height: 96,
              width: double.infinity,
              child: CustomPaint(
                painter: _BatteryPainter(
                  samples,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const Text('Courbe du niveau (%) selon le temps de la course.'),
        ],
      ],
    );
  }

  String _percent(int? level) => level == null ? '--' : '$level %';
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.samples, this.color);
  final List<BatterySample> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = samples
        .where((sample) => sample.levelPercent != null)
        .toList();
    if (valid.length < 3) return;
    final minimum = valid
        .map((sample) => sample.levelPercent!)
        .reduce(math.min);
    final maximum = valid
        .map((sample) => sample.levelPercent!)
        .reduce(math.max);
    final lower = math.max(0, minimum - 1);
    final upper = math.min(100, maximum + 1);
    final range = math.max(1, upper - lower);
    final start = samples.first.timestamp.millisecondsSinceEpoch;
    final duration = math.max(
      1,
      samples.last.timestamp.millisecondsSinceEpoch - start,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    var connected = false;
    for (final sample in samples) {
      final level = sample.levelPercent;
      if (level == null) {
        connected = false;
        continue;
      }
      final x =
          28 +
          (size.width - 30) *
              (sample.timestamp.millisecondsSinceEpoch - start) /
              duration;
      final y = 4 + (size.height - 8) * (upper - level) / range;
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = color);
      connected = true;
    }
    canvas.drawPath(path, paint);
    for (final entry in [(upper, 0.0), (lower, size.height - 16)]) {
      final text = TextPainter(
        text: TextSpan(
          text: '${entry.$1} %',
          style: TextStyle(color: color, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(0, entry.$2));
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}
