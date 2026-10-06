import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../application/run_controller.dart';
import '../domain/geo.dart';
import '../domain/models.dart' as domain;
import '../domain/navigation.dart';
import 'route_map.dart';
import 'free_run_screen.dart';
import 'formatters.dart';
import 'running_metrics.dart';
import 'run_tracking_controls.dart';

class MapFollowApp extends StatelessWidget {
  const MapFollowApp({super.key, required this.controller});
  final RunController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MapFollow',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      fontFamily: 'Roboto',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315d47)),
      scaffoldBackgroundColor: const Color(0xfff8faf6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    ),
    home: HomeScreen(controller: controller),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final RunController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _page = 0;
  RunController get c => widget.controller;
  Future<void> _import() => c.perform(() async {
    final routes = await c.pickRoutes();
    if (!mounted || routes.isEmpty) return;
    final domain.Route? route;
    if (routes.length == 1) {
      route = routes.single;
    } else {
      route = await showDialog<domain.Route>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choisir le parcours'),
          children: routes
              .map(
                (r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r),
                  child: Text('${r.name} · ${metres(routeDistance(r))}'),
                ),
              )
              .toList(),
        ),
      );
    }
    if (route != null) {
      await c.saveRoute(route);
      if (mounted) setState(() => _page = 1);
    }
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('MapFollow'),
        actions: [
          TextButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'MapFollow',
              applicationVersion: '0.3.0',
              applicationLegalese:
                  'Carte : © OpenStreetMap contributors · ODbL',
            ),
            icon: const Icon(Icons.info_outline),
            label: const Text('POC'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.error != null)
              MaterialBanner(
                content: Text(c.error!),
                actions: [
                  TextButton(
                    onPressed: c.dismissError,
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            if (c.recoverable != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Une course interrompue a été récupérée.',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Les points sauvegardés sont conservés. La reprise crée un nouveau segment.',
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.perform(() async {
                                      await c.recover();
                                      if (mounted) setState(() => _page = 1);
                                    }),
                              child: const Text('Reprendre'),
                            ),
                            TextButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.perform(c.closeRecovery),
                              child: const Text('Clôturer sans reprendre'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: !c.initialized
                  ? Center(
                      child: c.error == null
                          ? const CircularProgressIndicator()
                          : FilledButton(
                              onPressed: () => c.perform(c.initialize),
                              child: const Text('Réessayer'),
                            ),
                    )
                  : switch (_page) {
                      0 => _library(),
                      1 => _run(),
                      2 => _history(),
                      _ => SettingsScreen(controller: c),
                    },
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (index) => setState(() => _page = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: 'Parcours'),
          NavigationDestination(
            icon: Icon(Icons.navigation_outlined),
            label: 'Course',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Réglages'),
        ],
      ),
    ),
  );

  Widget _library() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Votre prochain trail',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Importez votre parcours, vérifiez les virages, puis lancez le guidage.',
      ),
      const SizedBox(height: 20),
      FreeRunActions(
        controller: c,
        onStarted: () {
          if (mounted) setState(() => _page = 1);
        },
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: c.busy || c.session != null ? null : _import,
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('Importer GPX, TCX ou PWX'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: c.busy || c.session != null
            ? null
            : () => c.perform(() async {
                await c.loadDemo();
                if (mounted) setState(() => _page = 1);
              }),
        icon: const Icon(Icons.science_outlined),
        label: const Text('Charger la démo synthétique'),
      ),
      const SizedBox(height: 24),
      if (c.routes.isEmpty)
        const _Notice(
          'Aucun parcours enregistré. La démo permet de tester le guidage sans courir.',
        ),
      for (final route in c.routes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.terrain),
              title: Text(route.name),
              subtitle: Text(
                '${metres(routeDistance(route))} · ${route.sourceFormat.toUpperCase()} · ${route.segments.length} segment(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: c.session != null
                  ? null
                  : () {
                      c.selectRoute(route);
                      setState(() => _page = 1);
                    },
            ),
          ),
        ),
      const SizedBox(height: 20),
      const _Notice(
        'POC expérimental : les indications estimées ne reconnaissent pas toutes les bifurcations. Vérifiez le parcours avant le départ.',
      ),
    ],
  );

  Widget _run() {
    final route = c.selectedRoute;
    if (route == null ||
        c.session?.mode == domain.RunMode.free ||
        (c.session == null && c.lastFinished?.mode == domain.RunMode.free)) {
      return FreeRunScreen(controller: c, onViewRoute: _viewRoute);
    }
    final run = c.session;
    final nav = c.navigation;
    final finished =
        run == null &&
            c.lastFinished?.mode == domain.RunMode.guided &&
            c.lastFinished?.routeId == route.id
        ? c.lastFinished
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (run == null) ...[
          if (finished != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Course guidée terminée',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (finished.simulated)
                      const Text('SIMULATION — données synthétiques.'),
                    const SizedBox(height: 8),
                    RunningMetrics(
                      activeSeconds: finished.activeSeconds,
                      distance: finished.distance,
                      metresPerSecond: finished.activeSeconds > 0
                          ? finished.distance / finished.activeSeconds
                          : null,
                      summary: true,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: c.busy
                          ? null
                          : () => c.perform(() => c.exportRun(finished.id)),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Exporter le GPX'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          FreeRunActions(controller: c),
          const SizedBox(height: 16),
        ],
        Text(route.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (run?.simulated == true)
          const _Notice(
            'SIMULATION — données synthétiques, ne pas suivre sur le terrain.',
          ),
        if (run != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    c.gpsReliable ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 18,
                  ),
                  label: Text(
                    c.gpsReliable
                        ? 'GPS ±${c.lastFix!.accuracy.round()} m'
                        : 'Guidage suspendu : GPS insuffisant',
                  ),
                ),
                Chip(
                  label: Text(switch (run.status) {
                    domain.RunStatus.running => 'En cours',
                    domain.RunStatus.paused => 'En pause',
                    domain.RunStatus.interrupted => 'Interrompue',
                    domain.RunStatus.finished => 'Terminée',
                  }),
                ),
              ],
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 330,
            child: RouteMap(
              key: ValueKey(route.id),
              route: route,
              fix: c.mapFix,
              recorded: run?.segments ?? const [],
              active: c.running,
              plannedRoute: run != null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (run != null)
          RunningMetrics(
            activeSeconds: c.elapsedSeconds,
            distance: run.distance,
            metresPerSecond: c.currentSpeedMetresPerSecond,
          ),
        if (run != null)
          Text(
            'Reste sur tracé : ${metres(nav?.remaining ?? c.prepared!.length)}',
          ),
        if (run != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Card(
              color: nav?.offRoute == true
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nav?.offRoute == true
                          ? 'Hors du parcours'
                          : nav?.nextCue == null
                          ? 'Suivez le tracé'
                          : '${directionText(nav!.nextCue!.cue.direction)} dans ${metres(nav.distanceToCue ?? 0)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('Dernière annonce : ${c.lastAnnouncement}'),
                  ],
                ),
              ),
            ),
          ),
        if (run == null) ...[
          const SizedBox(height: 12),
          Text(
            '${metres(c.prepared!.length)} · ${c.prepared!.cues.length} indication(s)',
          ),
          const SizedBox(height: 8),
          const _Notice(
            'Commencez près du départ et suivez le sens du fichier. À 20 m, la précision GPS et le temps de parole peuvent rendre l’annonce tardive.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: c.busy || c.recoverable != null
                ? null
                : () => c.perform(() => c.start(simulated: false)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Démarrer avec le GPS'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: c.busy || c.recoverable != null
                ? null
                : () => c.perform(() => c.start(simulated: true)),
            icon: const Icon(Icons.science),
            label: const Text('Simuler ce parcours'),
          ),
          const SizedBox(height: 16),
          Text(
            'Indications avant départ',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final cue in c.prepared!.cues)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                cue.cue.direction == domain.CueDirection.left
                    ? Icons.turn_left
                    : cue.cue.direction == domain.CueDirection.right
                    ? Icons.turn_right
                    : Icons.navigation,
              ),
              title: Text(directionText(cue.cue.direction)),
              subtitle: Text(
                'À ${metres(cue.distance)} · ${cue.cue.estimated ? 'estimée' : 'fournie par le fichier'}',
              ),
            ),
        ] else ...[
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
                            title: const Text('Terminer la course ?'),
                            content: const Text(
                              'Les points enregistrés seront conservés dans l’historique.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Continuer'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
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
      ],
    );
  }

  Widget _history() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Vos courses', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      if (c.history.isEmpty)
        const _Notice(
          'Les courses terminées apparaîtront ici. Les enregistrements restent sur votre téléphone.',
        ),
      for (final run in c.history)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.runName(run),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${run.startedAt.toLocal().day}/${run.startedAt.toLocal().month}/${run.startedAt.toLocal().year}',
                  ),
                  RunningMetrics(
                    activeSeconds: run.activeSeconds,
                    distance: run.distance,
                    metresPerSecond: run.activeSeconds > 0
                        ? run.distance / run.activeSeconds
                        : null,
                    summary: true,
                  ),
                  Text(
                    run.status == domain.RunStatus.finished
                        ? 'Terminée'
                        : 'Course récupérable',
                  ),
                  const SizedBox(height: 8),
                  if (run.mode == domain.RunMode.free &&
                      run.status == domain.RunStatus.finished)
                    RunHistoryActions(
                      controller: c,
                      run: run,
                      onViewRoute: _viewRoute,
                    )
                  else
                    OutlinedButton.icon(
                      onPressed:
                          c.busy || run.status != domain.RunStatus.finished
                          ? null
                          : () => c.perform(() => c.exportRun(run.id)),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Exporter le GPX'),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  void _viewRoute(domain.Route route) {
    c.selectRoute(route);
    setState(() => _page = 1);
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final RunController controller;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _warning, _offset, _volume;
  late domain.LocationProfile _profile;
  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _warning = s.warningDistance;
    _offset = s.offRouteDistance;
    _volume = s.voiceVolume;
    _profile = s.locationProfile;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final enabled = !c.busy && !c.running;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Un guidage à votre rythme',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<domain.LocationProfile>(
          initialValue: _profile,
          decoration: const InputDecoration(
            labelText: 'Profil GPS de la prochaine course',
          ),
          items: [
            for (final profile in domain.LocationProfile.values)
              DropdownMenuItem(
                value: profile,
                child: Text(locationProfileLabel(profile)),
              ),
          ],
          onChanged: !c.busy
              ? (value) => setState(() => _profile = value!)
              : null,
        ),
        const SizedBox(height: 8),
        const Text(
          'Appliqué au prochain départ. La course actuelle conserve son profil GPS. Les intervalles sont des demandes au système et peuvent varier selon Android.',
        ),
        const SizedBox(height: 20),
        Text('Prévenir ${_warning.round()} m avant le virage'),
        Slider(
          value: _warning,
          min: 10,
          max: 200,
          divisions: 38,
          label: '${_warning.round()} m',
          onChanged: enabled ? (v) => setState(() => _warning = v) : null,
        ),
        Text('Sortie de parcours : ${_offset.round()} m'),
        Slider(
          value: _offset,
          min: 15,
          max: 100,
          divisions: 17,
          label: '${_offset.round()} m',
          onChanged: enabled ? (v) => setState(() => _offset = v) : null,
        ),
        Text('Volume de la voix : ${(_volume * 100).round()} %'),
        Slider(
          value: _volume,
          min: 0,
          max: 1,
          divisions: 10,
          onChanged: enabled ? (v) => setState(() => _volume = v) : null,
        ),
        FilledButton(
          onPressed: !c.busy
              ? () => c.perform(
                  () => c.updateSettings(
                    c.running
                        ? c.settings.copyWith(locationProfile: _profile)
                        : c.settings.copyWith(
                            warningDistance: _warning,
                            offRouteDistance: _offset,
                            voiceVolume: _volume,
                            locationProfile: _profile,
                          ),
                  ),
                )
              : null,
          child: Text(
            c.running
                ? 'Enregistrer le profil de la prochaine course'
                : 'Enregistrer les réglages',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: enabled ? () => c.perform(c.testVoice) : null,
          icon: const Icon(Icons.volume_up_outlined),
          label: const Text('Tester la voix enregistrée'),
        ),
        const SizedBox(height: 20),
        const _Notice(
          'Le guidage nécessite une voix française hors connexion. Le Run libre peut enregistrer sans voix. La musique peut baisser pendant les annonces ; certains lecteurs de podcasts se mettent en pause.',
        ),
        const SizedBox(height: 12),
        const _Notice(
          'La carte nécessite Internet. Le GPS et les annonces restent actifs sans réseau pendant la session. Aucune localisation n’est envoyée à un serveur de suivi.',
        ),
        if (c.running)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Mettez la course en pause pour modifier les seuils et la voix. Le profil GPS choisi s’applique à la prochaine course.',
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(padding: const EdgeInsets.all(14), child: Text(text)),
  );
}
