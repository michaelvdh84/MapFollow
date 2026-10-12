# Audit des recommandations Android — 12 octobre 2026

## Décision et périmètre

Le document fourni a été évalué comme une proposition technique. La demande retenue est d'identifier ce qui existe déjà, d'intégrer les changements utiles et de conserver l'intervalle personnalisable. Branche : `codex/android-location-freshness`, version `0.5.2+7`. Les modifications locales de `0.5.1+6` déjà présentes sont conservées ; aucun commit ni push supplémentaire n'a été demandé.

Flutter 3.47.6 / Dart 3.13.5, Android min 26 / compile et target 36. Geolocator 14.1.1 utilise `geolocator_android 5.1.1+1` et Play Services Location 21.2.0. Le code vérifié sélectionne déjà Fused lorsque Play Services est disponible, avec repli LocationManager. Remplacer le fournisseur ou créer un deuxième abonnement serait inutile pour cet audit.

## Déjà présent et compléments

| Proposition | État vérifié / décision |
|---|---|
| Haute précision, intervalle 1 s, distance 0 m | Déjà le profil Précision. Developer conserve 250–10 000 ms et distance 0 m, épinglés à la session et à sa récupération. Équilibré 2 s/3 m et Autonomie 5 s/5 m restent disponibles. |
| Fused / SettingsClient | Déjà présents dans Geolocator. Le contrôle des réglages inclut la requête de localisation et propose une résolution système si disponible. |
| Autorisation fine/coarse | Le manifeste déclare les deux et le plugin les demande ensemble. MapFollow vérifie l'accès précis ; un accès approximatif bloque le départ avec un message. Aucun nouvel accès en arrière-plan. |
| Service de premier plan | Déjà déclaré de type location par le manifeste fusionné du plugin, notification persistante et permissions dédiées. Départ depuis l'action visible ; pause/fin annulent l'abonnement. Le wakelock existant est conservé dans l'attente d'un essai écran éteint. |
| Filtrage, arrêt, sauts, coupures | Déjà traités par les règles communes et le filtre `kalman-passive-3`, avec tests de virages, demi-tours, marche lente et pertes. Le réglage à 25 m de précision annoncée reste une heuristique. |
| Distance / allure | Distance horizontale géodésique par haversine, sur les positions traitées enregistrées. Le seuil d'enregistrement de 0,75 m reste indépendant d'une simplification d'affichage. Pas de distance 3D ; allure instantanée depuis vitesse Android nullable lissée 5 s, résumé distance / durée active. |
| OSM et guidage | Les directions viennent du parcours et des connexions préparées. Aucune trace enregistrée n'est forcée sur OSM ou sur la Garmin. |
| Diagnostics / confidentialité | Déjà Normal et Diagnostic, original fourni par Android + résultat filtré + décision, batterie du téléphone entier, export explicite et coordonnées exclues par défaut. Une position Fused originale est déjà fusionnée par le système : ce n'est pas une mesure GNSS brute. |
| Acquisition native | Compléments ci-dessous via une copie locale bornée du plugin, sous sa licence MIT. |

## Modifications de 0.5.2

Le builder de **Google Play Services** n'est pas conditionné par Android API 33 : la bibliothèque 21.2.0 est déjà la dépendance du plugin. Il est maintenant utilisé sur toutes les versions Android prises en charge. Le minimum suit exactement l'intervalle choisi, y compris 500 ms ; auparavant les API inférieures à 33 demandaient un minimum égal à la moitié de l'intervalle.

La requête fixe explicitement `setMaxUpdateAgeMillis(0)`, `setMaxUpdateDelayMillis(0)` et `setWaitForAccurateLocation(true)`. L'âge initial zéro exclut une première position historique Fused. Les deux autres choix rendent explicites des valeurs déjà par défaut : ils ne constituent pas un gain mesuré. Google normalise le délai zéro à l'intervalle ; la requête n'autorise pas le regroupement (`isBatched() == false`). Ces paramètres restent des demandes au système. [Builder Google](https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest.Builder), [requête et regroupement](https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest).

Le callback parcourait seulement `getLastLocation()` ; il transmet maintenant tous les éléments de `getLocations()` dans leur ordre. Les requêtes Fused actives sans regroupement sont normalement livrées individuellement selon Google : cette correction est une protection contre une perte silencieuse de points, pas la preuve que les anciennes sorties ont perdu des lots. Les résultats tardifs de SettingsClient/inscription et callbacks sont ignorés après l'arrêt ; un échec asynchrone d'inscription remonte au flux existant.

`elapsedRealtimeNanos` et l'instant monotone de réception native sont transmis, stockés avec les points disponibles et conservés dans les diagnostics. L'âge à la livraison, les intervalles de prédiction/rejet et la détection des coupures utilisent ces valeurs lorsqu'elles existent. Chaque nouvel abonnement reçoit un identifiant distinct : aucune comparaison monotone entre appareils, pauses/reprises ou récupérations après reboot. Les données anciennes et simulations gardent le repli UTC ; aucune ancienne trace n'est réécrite et le schéma SQLite ne change pas.

L'export ajoute cadence monotone et âge de livraison natif, sans coordonnées par défaut ni comptages GNSS. Les fenêtres internes de courbure, lissage de vitesse et chronomètre UI gardent encore leurs références temporelles UTC. Un ordre UTC inverse est toujours refusé : cette version n'annonce pas une résistance complète à un changement manuel de l'horloge pendant une course.

La précision Android est un rayon estimé à 68 %, et non une erreur maximale. Le filtre utilise explicitement un modèle conservateur isotrope : variance par axe `max(3 m, accuracy)²`, pondération de cadence. C'est une approximation de réglage, pas une conversion exacte du rayon radial à une covariance ni une preuve d'indépendance des mesures Fused. [Objet Location Android](https://developer.android.com/reference/android/location/Location).

## Choix à expérimenter séparément

Attendre plusieurs positions à 5–10 m avant un nouveau libellé « GPS prêt » n'est pas ajouté ici. La qualité actuelle dépend du signal reçu ; `waitForAccurateLocation` ne certifie pas plusieurs mesures cohérentes. Il faut tester le délai de démarrage et la distance omise si le coureur part avant une acquisition satisfaisante. Aucun rejet global de tout déplacement inférieur à `accuracy` n'est ajouté.

Le mode `setFullTracking(true)` demande les callbacks de mesures GNSS à partir de l'API 31, peut désactiver le duty cycling et augmente la consommation. Il n'est pas activé sans comparaison A/B sur S23/S21. Il ne fournit pas deux positions indépendantes GPS/Galileo, ni une précision garantie. Le panneau GNSS passif actuel est conservé. [API full tracking](https://developer.android.com/reference/android/location/GnssMeasurementRequest.Builder).

Pas d'exemption générale batterie Samsung, de fusion inertielle supplémentaire ou de remplacement du filtre sur la seule base d'une discussion. La Garmin Venu 3 reste une comparaison secondaire ; la cible relative de 2 % n'est pas une garantie d'erreur absolue.

## Code public étudié, sans copie

**OpenTracks**, dépôt Codeberg actuel : [GpsHandler.java, commit ce26e205](https://codeberg.org/OpenTracksApp/OpenTracks/src/commit/ce26e20571b1139b22697ad2d314c54247e1ef54/src/main/java/de/dennisguse/opentracks/sensors/GpsHandler.java) contrôle validité/précision et paramètres d'échantillonnage avant agrégation. [TrackPointCreator.java, commit 447d1bb7](https://codeberg.org/OpenTracksApp/OpenTracks/src/commit/447d1bb7a319880e7ef8b0be9d6f75d41fd80b3c/src/main/java/de/dennisguse/opentracks/services/handlers/TrackPointCreator.java) sépare capteurs, points stockés et valeurs UI, avec une horloge dédiée. La [discussion 1870](https://github.com/OpenTracksApp/OpenTracks/discussions/1870), sur l'ancien dépôt GitHub archivé, illustre les compromis seuils/arrêts ; elle ne valide aucun réglage pour MapFollow.

**RunnerUp** : [TrackerGPS.java, commit cee30bbe](https://github.com/jonasoreland/runnerup/blob/cee30bbec571433123cd5528e72c91436d665487/app/src/main/org/runnerup/tracker/component/TrackerGPS.java) utilise LocationManager GPS avec intervalle et distance configurables, puis retire ses callbacks à l'arrêt. Ce choix n'est pas une raison de remplacer le Fused existant. La [discussion 682](https://github.com/jonasoreland/runnerup/issues/682) est un retour historique de problèmes GPS, pas une preuve universelle de bénéfice d'un Kalman. Aucun code de ces projets n'a été copié.

## Baseline et protocole terrain

La baseline disponible est celle du [S21 du 12 octobre](comparison-s21-2026-10-12.md) : cadence reçue médiane 0,674 s pour demande 0,5 s, précision déclarée médiane 6,255 m, aucune coupure supérieure à 10 s dans les logs, batterie 47 → 42 %. La version 0.5.0 dépassait le compteur Garmin de 3,54 % sur la période commune ; le rejeu 0.5.1 donne −0,28 %. Ce rejeu ne mesure pas une nouvelle acquisition, un comportement écran verrouillé ni une précision absolue. Les horodatages monotones n'étaient pas présents dans cette baseline.

Pour comparer 0.5.2 : mêmes instants de départ/arrêt dehors, Diagnostic avant départ, téléphone fixé au même endroit, premier essai 1 s puis parcours comparable 0,5 s. Prévoir ciel ouvert, ville, forêt, virages serrés, demi-tour, marche et arrêt 60 s, pause/reprise, 10 min écran verrouillé avec musique/Bluetooth, puis export GPX/logs explicite. Noter modèle, OS, version, délai de premier signal exploitable, cadence effective, âge de livraison, rejets, segments, dérive à l'arrêt, fidélité des virages et baisse batterie du téléphone entier. Ajouter un trajet de longueur indépendante connue ; noter séparément compteur et GPX Garmin. Les positions personnelles restent locales. Utiliser [la fiche terrain](field-validation.md).

Autres sources officielles consultées le 12 octobre 2026 : [permissions à l'exécution](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime), [contrôle des réglages](https://developer.android.com/develop/sensors-and-location/location/change-location-settings), [services de type location](https://developer.android.com/develop/background-work/services/fgs/service-types), [FusedLocationProviderClient](https://developers.google.com/android/reference/com/google/android/gms/location/FusedLocationProviderClient). Résultats des commandes et des essais : [journal de vérification](verification.md).
