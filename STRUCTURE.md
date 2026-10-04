# Architecture de l’application

L’application sépare les modèles et règles métier, les accès aux données et services, la coordination d’une course, et l’interface Flutter. L’état partagé de l’interface utilise `ChangeNotifier` standard.

```text
lib/
  main.dart
  domain/
    models.dart       Route, RouteSegment, RoutePoint, NavigationCue,
                      LocationFix, RunSession
    geo.dart          calculs géographiques
    navigation.dart   progression et génération des indications
  data/
    repository.dart       persistance SQLite locale
    location_source.dart  GPS réel / simulation
    voice_service.dart    annonces et pont audio Android
    route_importer.dart  import GPX, TCX, PWX
    gpx_exporter.dart    création du document GPX
  application/
    run_controller.dart  orchestration et état ChangeNotifier
  presentation/
    app.dart             onglets et écrans
    route_map.dart       carte et couches de parcours
```

## Modèles et flux

`Route` représente l’itinéraire importé; il contient des `RouteSegment` ordonnés, faits de `RoutePoint`. `NavigationCue` contient une indication à annoncer. `LocationFix` normalise une position reçue du GPS ou du simulateur. `RunSession` contient les points et segments d’une session enregistrée.

Les deux sources de localisation aboutissent au même contrôleur et moteur de navigation. Une session ne franchit pas silencieusement une pause ou une coupure GPS : chaque reprise ouvre un segment séparé afin que l’export ne dessine pas une ligne inventée au travers du vide. Les écritures SQLite sont groupées de façon atomique.

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

Le code n’utilise pas directement le résultat de focus intégré de `flutter_tts`. Il passe par le canal natif `mapfollow/audio` pour demander temporairement le focus Android `MAY_DUCK`, parle avec `flutter_tts` réglé avec `focus: false`, puis abandonne le focus. Les événements d’interruption reçus par Android arrêtent la voix. Le comportement varie selon les lecteurs audio et doit être confirmé sur téléphone.

## Confidentialité dans le code

Utilisez des coordonnées synthétiques dans les exemples, logs, captures et rapports. Le partage GPX déclenché par l’utilisateur dans l’application reste une fonction prévue. Le manifeste et les règles d’extraction désactivent sauvegarde cloud et transfert appareil; ne promettez pas de comportement de restauration plus large sans l’avoir vérifié sur un appareil.
