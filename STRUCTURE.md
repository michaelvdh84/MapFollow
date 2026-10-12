# Architecture de l’application

L’application sépare les modèles et règles métier, les accès aux données et services, la coordination d’une course, et l’interface Flutter. L’état partagé de l’interface utilise `ChangeNotifier` standard.

```text
lib/
  main.dart
  domain/
    models.dart       Route, RouteSegment, RoutePoint, NavigationCue,
                      LocationFix, RunSession
    location_quality.dart règles communes de qualité et état GPS
    location_filter.dart filtre Kalman local et rejet des sauts
    map_guidance.dart graphe des connexions OSM et indications ordonnées
    run_diagnostics.dart mode diagnostic et instantanés batterie
    recorded_route.dart conversion d’une session libre en parcours sauvegardé
    speed_window.dart moyenne glissante des vitesses
    traversal_classifier.dart classification des passages Aller/Retour
    gnss_status.dart instantanés GNSS éphémères
    geo.dart          calculs géographiques
    navigation.dart   progression et génération des indications
  data/
    repository.dart       persistance SQLite locale v2 et suppression atomique
    map_guidance_source.dart Overpass explicite et cache local borné
    battery_source.dart lecture du pont batterie Android
    diagnostic_exporter.dart export JSON local déclenché par utilisateur
    location_source.dart  GPS réel / simulation
    voice_service.dart    annonces et pont audio Android
    gnss_source.dart      lecture du statut satellite Android
    route_importer.dart  import GPX, TCX, PWX
    gpx_exporter.dart    création du document GPX
  application/
    run_controller.dart  orchestration et état ChangeNotifier
  presentation/
    app.dart             onglets et écrans
    free_run_screen.dart interface et actions du Run libre
    formatters.dart      affichage des durées et distances
    running_metrics.dart vitesse et allure live/résumé
    run_tracking_controls.dart profil, traversée et accès aux diagnostics
    developer_options.dart intervalle personnalisé et export local des logs
    gnss_panel.dart      panneau GNSS à durée de vie limitée
    route_map.dart       carte et couches de parcours
```

## Modèles et flux

`Route` représente l’itinéraire importé; il contient des `RouteSegment` ordonnés, faits de `RoutePoint`. `NavigationCue` contient une indication à annoncer. `LocationFix` normalise une position reçue du GPS ou du simulateur. `RunSession` contient les points et segments d’une session enregistrée.

Les deux sources de localisation (appareil et simulation) aboutissent au même contrôleur et aux règles communes de qualité, métriques et enregistrement. Le `NavigationEngine` et les annonces ne servent qu’au mode guidé; un Run libre ne prépare pas de parcours et ne parle pas. Une session ne franchit pas silencieusement une pause ou une coupure GPS : chaque reprise ouvre un segment séparé afin que l’export ne dessine pas une ligne inventée au travers du vide. Les écritures SQLite sont groupées de façon atomique.

Une session porte un mode guidé ou libre. Le mode libre n’a pas de parcours source (`routeId` nul) ni d’annonces vocales; le GPS réel conserve le service de premier plan et sa notification, tandis que les avertissements GPS sont visuels. La simulation déterministe réutilise le traitement de position sans démarrer le service Android. À la fin, une session libre assez longue peut produire le parcours `recorded-{run.id}`; les sessions plus courtes restent dans l’historique. Le renommage du parcours généré synchronise le nom de session. L’export GPX conserve les segments et les métadonnées disponibles de vitesse, précision et cap.

## Profils, métriques et passages

`GuidanceSettings.locationProfile` choisit le profil de la prochaine course; chaque `RunSession` épingle sa propre valeur et la reprend après récupération. Les valeurs transmises à Android sont des demandes, et ne garantissent ni l’intervalle réel ni une économie de batterie mesurable :

| Profil | Précision demandée | Intervalle | Distance minimale demandée |
|---|---|---:|---:|
| Précision | `bestForNavigation` | 1 s | 0 m |
| Équilibré | `high` | 2 s | 3 m |
| Autonomie | `high` | 5 s | 5 m |

Un changement de profil dans Réglages concerne la prochaine course; la course en cours conserve son profil épinglé. Les anciennes sessions sans champ profil sont interprétées comme `precise`.

`GuidanceSettings.locationIntervalMillis` est un remplacement facultatif dans **Developer** (250–10 000 ms). Il épingle `RunSession.locationIntervalMillis`, avec filtre de distance 0 m lorsqu'il est actif. Sans ce champ, `requestedLocationIntervalMillis` reprend la cadence du profil. La persistance JSON ne nécessite pas de changement de schéma SQLite et ne réécrit pas les anciennes traces. Les nouvelles sessions portent aussi `locationFilterVersion` ; les anciennes sont déclarées inconnues dans le diagnostic.

L'adaptateur Android distingue la présence des valeurs Geolocator (`hasSpeed`, `hasAccuracy`, etc.) de leurs zéros par défaut. `LocationFix.speedAccuracy` et `headingAccuracy` sont optionnels. Le filtre pondère les mesures rapprochées, contraint la norme de vitesse uniquement avec incertitude exploitable et adapte son mouvement aux courbes et virages confirmés par les positions. Les seuils sont détaillés dans [le comportement GPS](docs/gps-guidance-and-diagnostics.md).

`LocationFix.speed` est nullable : null signifie qu’aucune vitesse exploitable n’a été fournie et ne signifie pas zéro. `SpeedWindow` moyenne les vitesses GPS valides des cinq dernières secondes. Après pause/reprise, la fenêtre est effacée. Une pause affiche la vitesse nulle et une allure `--`; lorsqu’une vitesse n’est pas disponible, les deux mesures restent `--`. Le résumé emploie la distance divisée par la durée active, pauses exclues.

`TraversalClassifier` est une heuristique, pas une preuve de direction. Il indexe les premiers passages dans une grille de 25 m, ignore les 30 m les plus récents pour éviter de rematcher le tracé tout juste parcouru et cherche un couloir à 15 m. Un cap à 45° ou moins correspond à l’aller; à 135° ou plus, au retour. Un changement automatique n’est confirmé qu’après trois points valides couvrant au moins 15 m, ce qui peut retarder un changement aller→retour ou retour→nouvelle portion. Des sentiers parallèles à moins de 15 m peuvent être ambigus. Les choix manuels Aller/Retour s’appliquent aux prochains points seulement et sont sauvegardés; Auto relance la classification automatique. Dans le guidage, ce classement change les couches enregistrées, pas le sens de navigation importé.

Les couches bleues (aller, 6 px) et orange pointillées (retour, 3 px) se masquent par les filtres Aller/Retour de la carte; un parcours guidé planifié reste vert. Les anciens points sans direction restent dans la couche non classée orange.

## Diagnostics GNSS

Pendant un Run GPS réel, ouvrir **Diagnostics GNSS** observe le récepteur Android déjà actif et rapporte des nombres par constellation si l’OS les fournit. Le téléphone choisit ses constellations; MapFollow ne les sélectionne pas. Ce panneau n’émet pas de seconde demande GPS et n’enregistre aucune donnée GNSS. Il existe des états explicites : inactif, attente de la première observation, permission requise, indisponible ou données périmées après 10 s. L’écoute s’arrête quand le panneau se ferme ou que l’application passe en arrière-plan. Un compte de satellites ne garantit pas une précision donnée. En simulation, les diagnostics ne sont pas disponibles.

## Seuils actuels de navigation

- Position considérée exploitable si sa précision est au plus 25 m et son âge au plus 10 s.
- Avertissement de guidage à 20 m d’un virage, configurable de 10 à 200 m.
- Détection d’écart après 3 positions GPS valides consécutives au-delà de 30 m du parcours, configurable de 15 à 100 m.
- Retour dans le couloir après 2 positions consécutives à moins de 70 % du seuil d’écart (21 m avec le réglage par défaut).
- Rappel d’écart toutes les 60 s.
- Progression le long de l’itinéraire limitée à 150–500 m vers l’avant et 50 m vers l’arrière.
- Estimation des indications de virage à environ ±20 m, avec seuil de direction 45° et regroupement des virages proches de 25 m.

Ces paramètres sont des heuristiques du prototype et restent à évaluer en conditions terrain.

Le partage GPX est déclenché par le contrôleur de course à partir du document produit par `gpx_exporter.dart`; ce fichier de données ne présente pas directement la feuille de partage.

## Voix et audio Android

Le code n’utilise pas directement le résultat de focus intégré de `flutter_tts`. En mode guidé, il passe par le canal natif `mapfollow/audio` pour demander temporairement le focus Android `MAY_DUCK`, parle avec `flutter_tts` réglé avec `focus: false`, puis abandonne le focus. Les événements d’interruption reçus par Android arrêtent la voix. Le mode libre ne prépare ni n’utilise le service vocal. Le comportement varie selon les lecteurs audio et doit être confirmé sur téléphone.

## Confidentialité dans le code

Utilisez des coordonnées synthétiques dans les exemples, logs, captures et rapports. Le partage GPX déclenché par l’utilisateur dans l’application reste une fonction prévue. Le manifeste et les règles d’extraction désactivent sauvegarde cloud et transfert appareil; ne promettez pas de comportement de restauration plus large sans l’avoir vérifié sur un appareil.

## Extension 0.4.0+4

Les GPS réels passent par le filtre du domaine avant le contrôleur de distance/navigation ; les simulations restent déterministes. La préparation Overpass utilise un isolate pour construire les indications sans modifier la géométrie. L'origine et la distance ordonnée des indications sont persistées avec Route. NavigationEngine ignore les estimations géométriques pour la voix et l'indication suivante. RunSession épingle le mode diagnostic et stocke les relevés batterie ; les diagnostics GPS sont dans une table séparée, chargés seulement pour export. La suppression de course, points et diagnostics est transactionnelle. Voir [le comportement et les bornes](docs/gps-guidance-and-diagnostics.md).

`RunController.diagnosticDocument` produit le JSON d'une course terminée et `exportDiagnostics` l'ouvre dans le partage natif. `DiagnosticExporter` v2 résume cadence, décisions et batterie et supprime récursivement les coordonnées par défaut ; le choix explicite `includePositions` ajoute les positions d'une course Diagnostic. Les anciennes courses Normal exportent leurs métadonnées et relevés disponibles avec une note d'absence des détails GPS. Aucun comptage GNSS n'est inclus.

## Correction 0.5.1+6

`LocationFilter` conserve son état Kalman pour le mouvement et le rejet de mesures et régularise la position émise selon la cohérence position/vitesse et l'incertitude disponible. Les consommateurs de trace, distance, progression et Aller/Retour reçoivent toujours la même position traitée. Les resets vident également l'historique et l'état d'amorçage de cette régularisation. Le replay de diagnostics utilise les positions brutes, jamais le GPX déjà filtré, et ne modifie pas les anciennes courses.

Chaque diagnostic de position indique la version réellement utilisée. Le champ de session conserve la version initiale ; `observedFilterVersions` résume les versions observées, notamment après récupération d'une session créée avant une mise à jour. Les anciennes lignes sans champ reprennent leur version de session ou `unknown`.

`AndroidAppInfoSource` lit le nom de version et le numéro de build du paquet installé via `mapfollow/appInfo`. Le contrôleur expose ce libellé à l'écran POC ; aucune deuxième constante de version n'est conservée dans la présentation. Un environnement sans pont affiche une version indisponible.

## Acquisition 0.5.2+7

`packages/geolocator_android` contient l'adaptation MIT du plugin Android résolue par l'override Pub. Le flux, les fournisseurs Fused/LocationManager et le service restent les mêmes ; les changements natifs et leur maintenance sont décrits dans `MAPFOLLOW_PATCH.md`. Le builder conserve les intervalles des profils/Developer et exclut la première position Fused en cache. Aucun deuxième abonnement n'est ajouté.

`LocationFix` porte facultativement temps monotone de mesure/réception et identifiant d'abonnement. `intervalSince` utilise l'horloge monotone seulement au sein du même abonnement, sinon UTC. Les points filtrés/enregistrés conservent ces champs. `LocationQuality` utilise l'âge natif lorsque disponible ; filtre, guidage et coupures de l'enregistrement reprennent l'intervalle disponible. L'export regroupe les cadences monotones par abonnement, sans franchir une récupération ou un reboot. Les champs JSON optionnels ne nécessitent pas de migration SQLite et les anciennes traces restent inchangées. Les timers UI et certaines fenêtres du filtre restent UTC ; voir [les limites de l'audit](docs/android-location-audit.md).
