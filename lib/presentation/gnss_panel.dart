import 'dart:async';
import 'package:flutter/material.dart';
import '../data/gnss_source.dart';
import '../domain/gnss_status.dart';

/// Le panneau est seul abonné : fermer la feuille libère les diagnostics natifs.
class GnssPanel extends StatefulWidget {
  const GnssPanel({
    super.key,
    required this.running,
    required this.simulated,
    this.source,
    this.now,
  });
  final bool running;
  final bool simulated;
  final GnssSource? source;
  final DateTime Function()? now;
  @override
  State<GnssPanel> createState() => _GnssPanelState();
}

class _GnssPanelState extends State<GnssPanel> {
  StreamSubscription<GnssSnapshot>? _subscription;
  Timer? _timer;
  GnssSnapshot? _snapshot;
  bool _unavailable = false;
  DateTime get _now => widget.now?.call() ?? DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    if (!widget.running || widget.simulated) return;
    _subscription = (widget.source ?? AndroidGnssSource()).snapshots.listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            _snapshot = snapshot;
            _unavailable = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _unavailable = true);
      },
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant GnssPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.simulated != widget.simulated ||
        oldWidget.source != widget.source) {
      unawaited(_subscription?.cancel());
      _subscription = null;
      _timer?.cancel();
      _snapshot = null;
      _unavailable = false;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _timer?.cancel();
    super.dispose();
  }

  String? get _message {
    if (widget.simulated) {
      return 'Diagnostics GNSS indisponibles en simulation.';
    }
    if (!widget.running) {
      return 'Diagnostics GNSS inactifs : reprenez une course GPS réelle.';
    }
    if (_unavailable) return 'Diagnostics GNSS indisponibles sur cet appareil.';
    final snapshot = _snapshot;
    if (snapshot == null) return 'En attente des diagnostics GNSS…';
    if (snapshot.availability == GnssAvailability.available &&
        snapshot.isStale(_now)) {
      return 'Diagnostics GNSS périmés : aucune mise à jour depuis plus de 10 s.';
    }
    return switch (snapshot.availability) {
      GnssAvailability.available => null,
      GnssAvailability.waiting => 'En attente de la première observation GNSS…',
      GnssAvailability.unavailable =>
        'Diagnostics GNSS indisponibles sur cet appareil.',
      GnssAvailability.permissionDenied =>
        'Permission de localisation requise pour les diagnostics GNSS.',
      GnssAvailability.inactive =>
        'Diagnostics GNSS inactifs : le suivi GPS doit être en cours au premier plan.',
    };
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diagnostics GNSS',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_message != null)
            Text(_message!)
          else ...[
            Text(
              'Satellites vus : ${_snapshot!.seen} · utilisés : ${_snapshot!.used}',
            ),
            const SizedBox(height: 8),
            for (final count in _snapshot!.constellations)
              Text(
                '${count.name} : ${count.seen} vus · ${count.used} utilisés',
              ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Le téléphone choisit les constellations disponibles. Ces nombres ne garantissent pas la précision GPS.',
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    ),
  );
}
