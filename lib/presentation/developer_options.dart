import 'package:flutter/material.dart';

import '../domain/models.dart' as domain;
import '../domain/run_diagnostics.dart';

/// Parses seconds entered by the user into the integer millisecond system request.
int? parseLocationIntervalMillis(String value) {
  final text = value.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final seconds = double.tryParse(text);
  if (seconds == null || !seconds.isFinite || seconds < 0.25 || seconds > 10) {
    return null;
  }
  return (seconds * 1000).round();
}

String? validateLocationInterval(String? rawValue) {
  final value = rawValue ?? '';
  if (value.trim().isEmpty || parseLocationIntervalMillis(value) != null) {
    return null;
  }
  return 'Saisissez une valeur entre 0,25 et 10 secondes.';
}

class DeveloperOptions extends StatefulWidget {
  const DeveloperOptions({
    super.key,
    required this.intervalMillis,
    required this.onIntervalChanged,
    required this.diagnosticsMode,
    required this.onDiagnosticsModeChanged,
    required this.runs,
    required this.onExport,
    required this.busy,
  });

  final int? intervalMillis;
  final ValueChanged<int?> onIntervalChanged;
  final DiagnosticsMode diagnosticsMode;
  final ValueChanged<DiagnosticsMode> onDiagnosticsModeChanged;
  final List<domain.RunSession> runs;
  final Future<void> Function(String runId, bool includePositions) onExport;
  final bool busy;

  @override
  State<DeveloperOptions> createState() => _DeveloperOptionsState();
}

class _DeveloperOptionsState extends State<DeveloperOptions> {
  late final TextEditingController _intervalController;
  String? _selectedRunId;
  bool _includePositions = false;

  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController(
      text: widget.intervalMillis == null
          ? ''
          : (widget.intervalMillis! / 1000).toString(),
    );
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final finishedRuns = widget.runs
        .where((run) => run.status == domain.RunStatus.finished)
        .toList();
    final selected = finishedRuns.any((run) => run.id == _selectedRunId)
        ? _selectedRunId
        : null;
    final selectedRun = finishedRuns.where((run) => run.id == selected);
    final diagnosticRun = selectedRun.isEmpty ? null : selectedRun.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Developer', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('developerLocationInterval'),
          controller: _intervalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: const InputDecoration(
            labelText: 'Intervalle GPS personnalisé (secondes)',
            hintText: 'Vide = intervalle du profil GPS',
            suffixText: 's',
          ),
          validator: validateLocationInterval,
          onChanged: (value) {
            if (validateLocationInterval(value) == null) {
              widget.onIntervalChanged(
                value.trim().isEmpty
                    ? null
                    : parseLocationIntervalMillis(value),
              );
            }
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'La valeur est épinglée au prochain départ et demande un filtre de distance de 0 m. Elle remplace l’intervalle du profil GPS. La course en cours garde ses réglages ; Android peut appliquer une cadence différente.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<DiagnosticsMode>(
          key: ValueKey<DiagnosticsMode>(widget.diagnosticsMode),
          initialValue: widget.diagnosticsMode,
          decoration: const InputDecoration(labelText: 'Journaux locaux'),
          items: const [
            DropdownMenuItem(
              value: DiagnosticsMode.normal,
              child: Text('Normal · batterie début / fin'),
            ),
            DropdownMenuItem(
              value: DiagnosticsMode.diagnostic,
              child: Text('Diagnostic · détails GPS et batterie'),
            ),
          ],
          onChanged: widget.busy
              ? null
              : (value) {
                  if (value != null) widget.onDiagnosticsModeChanged(value);
                },
        ),
        const SizedBox(height: 6),
        const Text(
          'Le mode Diagnostic conserve localement les positions reçues, les décisions de filtrage et des relevés batterie. Aucun comptage GNSS n’est enregistré. Ce choix concerne la prochaine course.',
        ),
        const SizedBox(height: 20),
        Text(
          'Exporter les logs',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('developerExportRun'),
          initialValue: selected,
          hint: const Text('Choisir une course'),
          decoration: const InputDecoration(labelText: 'Course terminée'),
          items: [
            for (final run in finishedRuns)
              DropdownMenuItem(
                value: run.id,
                child: Text(run.name.isEmpty ? run.id : run.name),
              ),
          ],
          onChanged: widget.busy
              ? null
              : (value) => setState(() {
                  _selectedRunId = value;
                  _includePositions = false;
                }),
        ),
        if (diagnosticRun != null) ...[
          if (diagnosticRun.diagnosticsMode == DiagnosticsMode.diagnostic)
            CheckboxListTile(
              key: const Key('developerIncludePositions'),
              contentPadding: EdgeInsets.zero,
              value: _includePositions,
              title: const Text('Inclure les positions GPS'),
              subtitle: const Text(
                'Les positions GPS détaillées seront ajoutées au fichier exporté.',
              ),
              onChanged: widget.busy
                  ? null
                  : (value) =>
                        setState(() => _includePositions = value ?? false),
            )
          else
            const Text(
              'Course en mode Normal : seules les métadonnées et les mesures batterie disponibles seront exportées. Aucun détail GPS n’a été enregistré.',
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('developerExportLogs'),
            onPressed: widget.busy
                ? null
                : () => widget.onExport(
                    diagnosticRun.id,
                    diagnosticRun.diagnosticsMode ==
                            DiagnosticsMode.diagnostic &&
                        _includePositions,
                  ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exporter les logs'),
          ),
        ],
      ],
    );
  }
}
