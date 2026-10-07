import 'package:flutter/material.dart';
import '../application/run_controller.dart';
import '../domain/models.dart';
import '../domain/run_diagnostics.dart';

class HistoryTools extends StatelessWidget {
  const HistoryTools({super.key, required this.controller, required this.run});
  final RunController controller;
  final RunSession run;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      if (run.diagnosticsMode == DiagnosticsMode.diagnostic)
        TextButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Exporter le diagnostic'),
          onPressed: controller.busy || run.status != RunStatus.finished
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Exporter le diagnostic ?'),
                      content: const Text(
                        'Ce fichier contient les positions GPS reçues, y compris les mesures rejetées, et les relevés batterie. Choisissez vous-même sa destination de partage.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Exporter'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await controller.perform(
                      () => controller.exportDiagnostics(run.id),
                    );
                  }
                },
        ),
      TextButton.icon(
        icon: const Icon(Icons.delete_outline),
        label: const Text('Supprimer'),
        onPressed: controller.busy || run.status != RunStatus.finished
            ? null
            : () async {
                var alsoRoute = false;
                final generated = controller.generatedRoute(run);
                final allowed = controller.canDeleteGeneratedRoute(run);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => StatefulBuilder(
                    builder: (context, setState) => AlertDialog(
                      title: const Text('Supprimer cette course ?'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'La course, ses points GPS et ses diagnostics seront supprimés définitivement de ce téléphone. Les fichiers déjà exportés restent à leur destination.',
                          ),
                          if (generated != null)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: alsoRoute,
                              title: const Text(
                                'Supprimer aussi le parcours généré',
                              ),
                              subtitle: allowed
                                  ? null
                                  : const Text(
                                      'Ce parcours est utilisé par une course active ou récupérable.',
                                    ),
                              onChanged: allowed
                                  ? (v) => setState(() => alsoRoute = v!)
                                  : null,
                            ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer définitivement'),
                        ),
                      ],
                    ),
                  ),
                );
                if (confirmed == true) {
                  await controller.perform(
                    () => controller.deleteRun(
                      run.id,
                      deleteGeneratedRoute: alsoRoute,
                    ),
                  );
                }
              },
      ),
    ],
  );
}
