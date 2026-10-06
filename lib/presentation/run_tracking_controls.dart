import 'package:flutter/material.dart';
import '../application/run_controller.dart';
import '../domain/models.dart';
import 'gnss_panel.dart';

String locationProfileLabel(LocationProfile profile) => switch (profile) {
  LocationProfile.precise => 'Précision · 1 s / 2 m',
  LocationProfile.balanced => 'Équilibré · 2 s / 3 m',
  LocationProfile.autonomy => 'Autonomie · 5 s / 5 m',
};

class RunTrackingControls extends StatelessWidget {
  const RunTrackingControls({super.key, required this.controller});
  final RunController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final run = c.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profil GPS ${run == null ? 'au prochain départ' : 'de cette course'} : ${locationProfileLabel(run?.locationProfile ?? c.settings.locationProfile)}',
        ),
        if (run == null)
          const Text(
            'Choisissez le profil dans Réglages. Les changements s’appliquent à la prochaine course.',
          ),
        if (run != null) ...[
          const SizedBox(height: 8),
          SegmentedButton<TraversalControl>(
            segments: const [
              ButtonSegment(
                value: TraversalControl.automatic,
                label: Text('Auto'),
              ),
              ButtonSegment(
                value: TraversalControl.outbound,
                label: Text('Aller'),
              ),
              ButtonSegment(
                value: TraversalControl.returning,
                label: Text('Retour'),
              ),
            ],
            selected: {run.traversalControl},
            onSelectionChanged: c.busy || run.status == RunStatus.finished
                ? null
                : (values) =>
                      c.perform(() => c.updateTraversalControl(values.single)),
          ),
          const SizedBox(height: 4),
          Text(
            'Le choix Aller / Retour s’applique aux prochains points uniquement.${run.mode == RunMode.guided ? ' Le guidage garde le sens du parcours importé.' : ''}',
          ),
          TextButton.icon(
            onPressed: !c.busy && c.running && !run.simulated
                ? () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => ListenableBuilder(
                      listenable: c,
                      builder: (_, _) => GnssPanel(
                        running: c.running && c.session != null,
                        simulated: c.session?.simulated ?? run.simulated,
                      ),
                    ),
                  )
                : null,
            icon: const Icon(Icons.satellite_alt),
            label: const Text('Diagnostics GNSS'),
          ),
          if (run.simulated)
            const Text('Diagnostics GNSS indisponibles en simulation.'),
        ],
      ],
    );
  }
}
