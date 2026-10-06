# Parcours, enregistrement et export

## Importer un parcours

MapFollow importe des fichiers XML GPX, TCX et PWX. Le fichier doit être encodé en UTF-8, mesurer au plus 10 MiB et contenir au plus 100 000 points. Les points invalides ou les discontinuités ne sont pas reliés artificiellement : les ruptures de parcours restent représentées par des segments distincts. Des exemples de démonstration synthétiques se trouvent dans `assets/demo.gpx`.

Les fichiers peuvent contenir des informations différentes selon leur format et l’application qui les a produits. L’import conserve la géométrie et traite les champs facultatifs lorsqu’ils sont présents. En cas d’erreur, réessayez avec un export GPX/TCX/PWX standard et un fichier plus petit.

## Enregistrer une course

Les sessions et points sont stockés localement dans SQLite. Une seule session peut être active à la fois. Les insertions de points sont regroupées de façon atomique pour éviter de laisser une écriture partielle.

Une course libre n’a pas de parcours source et ne lance pas le guidage vocal. Le GPS réel utilise le service Android au premier plan; les avertissements sur la qualité GPS sont affichés à l’écran. La simulation reste synthétique et déterministe et ne démarre pas ce service. Une course libre terminée dont un segment contient au moins deux positions distinctes produit aussi un parcours généré à identifiant stable `recorded-{run.id}`. La conversion copie dans ces points les libellés Aller/Retour déjà enregistrés; des anciens points sans direction restent non classés. Une course plus courte reste dans l’historique sans parcours généré. Les noms de simulation commencent par `SIMULATION`; renommer le parcours généré met à jour le nom de sa session.

## Profil GPS, métriques et couches aller/retour

Dans **Réglages**, choisissez le profil GPS qui sera appliqué à la prochaine course. La sélection par défaut est **Équilibré**. Le profil est ensuite épinglé à la session, conservé lors de la récupération, et n’est pas modifié par un changement des réglages pendant la course. Ces intervalles sont des demandes à Android; le système décide des positions effectivement livrées, et aucune économie de batterie n’est garantie.

| Profil | Précision demandée | Intervalle demandé | Déplacement minimal demandé |
|---|---|---:|---:|
| Précision | `bestForNavigation` | 1 s | 2 m |
| Équilibré | `high` | 2 s | 3 m |
| Autonomie | `high` | 5 s | 5 m |

La vitesse en direct est la moyenne des vitesses GPS valides des cinq dernières secondes; elle ne modifie pas les valeurs brutes exportées. Si le système ne fournit pas de vitesse, l’application affiche `--` au lieu de supposer une immobilité. Pendant une pause, vitesse = 0 et allure = `--`. Le résumé utilise distance divisée par temps actif, pauses exclues. Après une reprise, la fenêtre de cinq secondes repart vide.

Le mode **Auto** classe les positions acceptées comme Aller ou Retour et sauvegarde ce libellé sur chaque point. C’est une heuristique : grille de recherche de 25 m, exclusion des 30 m récemment parcourus, correspondance dans un couloir de 15 m, puis comparaison de cap (≤45° pour Aller, ≥135° pour Retour). Un changement de sens exige trois positions couvrant au moins 15 m; le nouveau calque peut donc apparaître avec retard. Des sentiers parallèles distants de 15 m ou moins peuvent être confondus. Les contrôles **Aller** et **Retour** imposent le sens pour les prochains points seulement; **Auto** reprend la classification. En mode guidé, cela ne change pas le sens de navigation du parcours importé.

Sur la carte, le tracé Aller est bleu et épais (6 px); le Retour est orange, fin et pointillé (3 px). Les filtres **Aller** et **Retour** peuvent masquer leurs calques. Le parcours planifié du guidage demeure vert. Les anciens points qui ne portent pas de direction restent dans le calque non classé orange.

La pause, la perte de signal GPS et une reprise créent des segments distincts. Le tracé ne dessine donc pas une fausse ligne droite par-dessus une période sans point. Une session interrompue à la fermeture peut être proposée explicitement au prochain démarrage; vérifiez les dates et segments avant de continuer ou terminer cette session.

La simulation guidée avance à 3 m/s pour essayer les annonces et le suivi sans GPS réel. La simulation d’un Run libre fait deux passages aller-retour sur le même trajet synthétique déterministe, sans démarrer le service Android de localisation au premier plan. Ces deux simulations passent par les mêmes règles de validation et d’enregistrement que les flux GPS correspondants, sans enregistrer une vraie trace de déplacement.

## Exporter en GPX

Depuis l’historique, partagez la session au format GPX via la feuille de partage Android. Le fichier préserve les limites entre segments. Dans l’espace de noms MapFollow, `mf:run` enregistre mode, durée active, distance, simulation, profil GPS, contrôle Aller/Retour et, si disponible, date de fin; chaque point exporte les métadonnées GPS disponibles `mf:accuracyMeters`, `mf:speedMetersPerSecond`, `mf:headingDegrees` et son libellé `mf:traversalDirection` (valeur `outbound` ou `returning`). Un champ absent ou invalide n’est pas exporté. Une copie temporaire est créée pour le partage et est supprimée lorsque Android vide le cache de l’application; elle peut donc subsister quelque temps dans le cache. Il n’y a pas encore de bouton pour effacer une session ou supprimer immédiatement ce fichier temporaire.

### Extensions GPX MapFollow

L’espace de noms `mf` est versionné à l’adresse `https://github.com/michaelvdh84/MapFollow/xmlns/1`. Les exemples ci-dessous utilisent des coordonnées synthétiques. `trk`, `trkseg`, `trkpt`, `ele` et `time` restent des éléments GPX standards; `extensions` ajoute les métadonnées MapFollow.

```xml
<gpx version="1.1" creator="MapFollow"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:mf="https://github.com/michaelvdh84/MapFollow/xmlns/1">
  <metadata>
    <name>Run libre synthétique</name>
    <time>2026-10-06T12:00:00Z</time>
    <extensions>
      <mf:run mode="free" activeSeconds="65" distanceMeters="12.4"
              simulated="false" locationProfile="balanced"
              traversalControl="automatic" endedAt="2026-10-06T12:01:05Z"/>
    </extensions>
  </metadata>
  <trk><name>Run libre synthétique</name><trkseg>
    <trkpt lat="50.000000" lon="4.000000">
      <ele>120.0</ele><time>2026-10-06T12:00:01Z</time>
      <extensions>
        <mf:accuracyMeters>4.5</mf:accuracyMeters>
        <mf:speedMetersPerSecond>2.8</mf:speedMetersPerSecond>
        <mf:headingDegrees>90.0</mf:headingDegrees>
        <mf:traversalDirection>outbound</mf:traversalDirection>
      </extensions>
    </trkpt>
    <trkpt lat="50.000050" lon="4.000050">
      <time>2026-10-06T12:00:05Z</time>
      <extensions><mf:traversalDirection>returning</mf:traversalDirection></extensions>
    </trkpt>
  </trkseg></trk>
</gpx>
```

Les unités sont les suivantes : altitude `ele`, précision et distance en mètres; vitesse en mètres par seconde; cap en degrés, de 0 inclus à 360 exclu; durée active en secondes. Les dates de `metadata/time`, des points et de `endedAt` sont écrites en UTC, avec le suffixe `Z`. `locationProfile` vaut `precise`, `balanced` ou `autonomy`; `traversalControl` vaut `automatic`, `outbound` ou `returning`. `mf:traversalDirection` vaut `outbound` ou `returning`. Une métadonnée absente ou invalide est omise; par exemple le cap doit être fini et satisfaire `0 ≤ cap < 360`.

À l’import GPX, la géométrie standard et ses segments restent exploitables comme parcours, avec les champs standards reconnus par l’importateur. L’import reconnaît aussi `mf:traversalDirection` lorsque le nom et l’URI du namespace correspondent exactement à `mf`; les libellés sont réutilisés pour les calques Aller/Retour. Les attributs de `mf:run` (mode, durée, profil, contrôle de sens, etc.) restent informatifs : ils ne reconstituent pas une `RunSession` dans l’historique et ne restaurent pas tous les détails d’une course. Des extensions d’un autre namespace portant simplement le même nom local sont ignorées. Les anciennes sessions qui n’ont pas le champ `locationProfile` sont lues avec le profil `precise`; les réglages globaux nouvellement créés utilisent `balanced` par défaut.

Les 52 tests mentionnés dans le journal précédent correspondent à la version `0.2.0+2`; ils ne valident pas la version courante `0.3.0+3`. Voir [le journal de vérification](verification.md) pour les contrôles de chaque version. Le partage Android sur appareil reste à vérifier lors des essais terrain.
