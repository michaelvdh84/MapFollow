import 'package:flutter/material.dart';
import '../application/run_controller.dart';
import '../domain/models.dart' as domain;
import 'route_map.dart';
import 'running_metrics.dart';
import 'run_tracking_controls.dart';
import 'battery_summary.dart';
import 'history_tools.dart';
import '../domain/run_diagnostics.dart';

/// Présentation du Run libre : seul le contrôleur connaît GPS et stockage.
class FreeRunScreen extends StatelessWidget {
  const FreeRunScreen({
    super.key,
    required this.controller,
    required this.onViewRoute,
  });
  final RunController controller;
  final void Function(domain.Route) onViewRoute;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final run = c.session ?? c.lastFinished;
    final finished = c.session == null && run != null;
    final route = run == null ? null : c.generatedRoute(run);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          finished ? 'Run terminé' : 'Run libre',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (run == null) ...[
          const Text(
            'Enregistrez votre trajet sans importer de parcours. Le GPS dessine la trace et le parcours sera sauvegardé à la fin.',
          ),
          const SizedBox(height: 16),
          FreeRunActions(controller: c),
        ] else ...[
          Text(c.runName(run), style: Theme.of(context).textTheme.titleMedium),
          if (run.simulated)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'SIMULATION — données synthétiques, ne pas suivre sur le terrain.',
              ),
            ),
          if (!finished) ...[
            const SizedBox(height: 8),
            Text(
              c.mapFix == null
                  ? 'En attente du GPS'
                  : c.gpsReliable
                  ? 'GPS ±${c.lastFix!.accuracy.round()} m'
                  : 'GPS insuffisant : enregistrement des positions suspendu.',
            ),
            Text(switch (run.status) {
              domain.RunStatus.running => 'En cours',
              domain.RunStatus.paused => 'En pause',
              domain.RunStatus.interrupted => 'Interrompue',
              domain.RunStatus.finished => 'Terminée',
            }),
          ],
        ],
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 300,
            child: RouteMap(
              key: ValueKey('${run?.id ?? 'free-empty'}-$finished'),
              route: route,
              fix: finished ? null : c.mapFix,
              recorded: run?.segments ?? const [],
              active: c.running,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (run != null) ...[
          RunningMetrics(
            activeSeconds: finished ? run.activeSeconds : c.elapsedSeconds,
            distance: run.distance,
            metresPerSecond: finished
                ? (run.activeSeconds > 0
                      ? run.distance / run.activeSeconds
                      : null)
                : c.currentSpeedMetresPerSecond,
            summary: finished,
          ),
          const SizedBox(height: 16),
          if (finished) ...[
            BatterySummary(
              samples: run.batterySamples,
              interrupted: run.batteryInterrupted,
              detailed: run.diagnosticsMode == DiagnosticsMode.diagnostic,
            ),
            HistoryTools(controller: c, run: run),
            Text(
              route == null
                  ? 'Course conservée dans l’historique. Il faut au moins deux positions distinctes dans un même segment pour créer un parcours réutilisable.'
                  : 'Votre parcours est enregistré dans Parcours. Vous pouvez maintenant le suivre ou le partager.',
            ),
            const SizedBox(height: 12),
            RunHistoryActions(
              controller: c,
              run: run,
              onViewRoute: onViewRoute,
              requirePoints: true,
            ),
            const SizedBox(height: 24),
            FreeRunActions(controller: c),
          ] else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: c.busy
                          ? null
                          : () => c.perform(c.running ? c.pause : c.resume),
                      icon: Icon(c.running ? Icons.pause : Icons.play_arrow),
                      label: Text(c.running ? 'Pause' : 'Reprendre'),
                    ),
                    OutlinedButton.icon(
                      onPressed: c.busy
                          ? null
                          : () async {
                              final finish = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Terminer le Run ?'),
                                  content: const Text(
                                    'La course et son parcours seront sauvegardés.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Continuer'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Terminer'),
                                    ),
                                  ],
                                ),
                              );
                              if (finish == true) {
                                await c.perform(c.finishAfterPending);
                              }
                            },
                      icon: const Icon(Icons.stop),
                      label: const Text('Terminer'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RunTrackingControls(controller: c),
              ],
            ),
        ],
      ],
    );
  }
}

/// Accès commun depuis Parcours, Course et le récapitulatif, sans détour par l'import.
class FreeRunActions extends StatelessWidget {
  const FreeRunActions({super.key, required this.controller, this.onStarted});
  final RunController controller;
  final VoidCallback? onStarted;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final enabled = !c.busy && c.session == null && c.recoverable == null;
    Future<void> start(bool simulated) => c.perform(() async {
      await c.start(simulated: simulated, mode: domain.RunMode.free);
      onStarted?.call();
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunTrackingControls(controller: c),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: enabled ? () => start(false) : null,
              icon: const Icon(Icons.directions_run),
              label: const Text('Lancer un Run libre'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => start(true) : null,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Simuler un Run libre'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'La simulation synthétique effectue un aller-retour vers le départ.',
        ),
      ],
    );
  }
}

/// Historique = métadonnées légères ; l'export recharge les points à la demande.
class RunHistoryActions extends StatelessWidget {
  const RunHistoryActions({
    super.key,
    required this.controller,
    required this.run,
    required this.onViewRoute,
    this.requirePoints = false,
  });
  final RunController controller;
  final domain.RunSession run;
  final void Function(domain.Route) onViewRoute;
  final bool requirePoints;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final route = c.generatedRoute(run);
    final hasExport =
        !requirePoints ||
        run.segments
                .expand((s) => s)
                .map((fix) => '${fix.point.latitude},${fix.point.longitude}')
                .toSet()
                .length >=
            2;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (route != null)
          OutlinedButton.icon(
            onPressed: c.busy || c.session != null
                ? null
                : () => onViewRoute(route),
            icon: const Icon(Icons.route),
            label: const Text('Voir le parcours'),
          ),
        OutlinedButton.icon(
          onPressed: c.busy
              ? null
              : () async {
                  final name = await showDialog<String>(
                    context: context,
                    builder: (_) => _RenameRunDialog(name: c.runName(run)),
                  );
                  if (name != null) {
                    await c.perform(() => c.renameRun(run.id, name));
                  }
                },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Renommer'),
        ),
        OutlinedButton.icon(
          onPressed: c.busy || !hasExport
              ? null
              : () => c.perform(() => c.exportRun(run.id)),
          icon: const Icon(Icons.ios_share),
          label: const Text('Exporter / partager'),
        ),
      ],
    );
  }
}

class _RenameRunDialog extends StatefulWidget {
  const _RenameRunDialog({required this.name});
  final String name;
  @override
  State<_RenameRunDialog> createState() => _RenameRunDialogState();
}

class _RenameRunDialogState extends State<_RenameRunDialog> {
  late final TextEditingController input = TextEditingController(
    text: widget.name,
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Renommer le Run'),
    content: TextField(
      controller: input,
      maxLength: 120,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Nom du parcours'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
