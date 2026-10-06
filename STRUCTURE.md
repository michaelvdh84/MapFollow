# Architecture de l’application

L’application sépare les modèles et règles métier, les accès aux données et services, la coordination d’une course, et l’interface Flutter. L’état partagé de l’interface utilise `ChangeNotifier` standard.

```text
lib/
  main.dart
  domain/
    models.dart       Route, RouteSegment, RoutePoint, NavigationCue,
                      LocationFix, RunSession
    location_quality.dart règles communes de qualité et état GPS
    recorded_route.dart conversion d’une session libre en parcours sauvegardé
    speed_window.dart moyenne glissante des vitesses
    traversal_classifier.dart classification des passages Aller/Retour
    gnss_status.dart instantanés GNSS éphémères
    geo.dart          calculs géographiques
    navigation.dart   progression et génération des indications
  data/
    repository.dart       persistance SQLite locale
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
| Précision | `bestForNavigation` | 1 s | 2 m |
| Équilibré (défaut) | `high` | 2 s | 3 m |
| Autonomie | `high` | 5 s | 5 m |

Un changement de profil dans Réglages concerne la prochaine course; la course en cours conserve son profil épinglé. Les anciennes sessions sans champ profil sont interprétées comme `precise`.

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
