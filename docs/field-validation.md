# Fiche de validation terrain

Remplir une copie pour chaque appareil et build. Utiliser un parcours synthétique lorsque possible. Ne joignez pas de trace réelle à ce rapport.

## Contexte

- Date/heure :
- Build / commit :
- Appareil et modèle :
- Version Android / One UI :
- Version MapFollow :
- Autorisations accordées :
- Réglage batterie MapFollow :
- Réseau / lecteur audio utilisé :
- Itinéraire de test (nom synthétique) :

## Procédure ciblée — Run libre

Ces étapes sont à réaliser et à consigner pour chaque émulateur ou appareil. Les résultats partiels de `0.4.0+4` figurent en fin de document ; les validations terrain restent distinctes des tests automatisés. Utilisez uniquement un Run synthétique sur émulateur; sur téléphone, n’inscrivez aucune coordonnée dans ce compte rendu et ne joignez pas de GPX réel.

### Émulateur Android : vérifier le Run libre sans voix

1. Installez la version debug sur un émulateur de test dont la bibliothèque Parcours ne contient pas de parcours importé. N’installez pas de voix française pour ce contrôle.
2. Dans **Parcours**, touchez **Simuler un Run libre**. Confirmez que le Run démarre sans demander la voix et que la position synthétique se déplace sur la carte. Confirmez qu’aucun service de localisation Android au premier plan ni notification persistante n’est démarré par cette simulation.
3. Touchez **Pause**, puis **Reprendre**; confirmez qu’un nouveau segment commence. Touchez **Terminer** et vérifiez que l’écran affiche **Run terminé** et qu’un parcours apparaît dans Parcours.
4. Renommez le Run et vérifiez que le nom est synchronisé entre la session et le parcours. Touchez **Exporter / partager**, choisissez une destination de test, puis réimportez ce GPX dans l’application.
5. Ouvrez le parcours réimporté. Pour essayer le guidage, installez d’abord une voix française hors connexion et vérifiez qu’un départ guidé est possible; ce contrôle vocal est distinct de la preuve que le Run libre fonctionne sans voix.

### Samsung Galaxy S23 Ultra ou S21 5G : GPS réel

1. Notez modèle, version Android/One UI et numéro de build. Accordez les permissions de localisation et notifications demandées par Android. Restez dehors avec une vue dégagée du ciel.
2. Dans une zone de marche sûre, touchez **Lancer un Run libre** et marchez environ 200 m. Vérifiez l’attente puis l’état GPS exploitable, les alertes GPS visuelles, la notification persistante et l’augmentation de durée/distance.
3. Verrouillez l’écran pendant le déplacement et confirmez que le GPS et l’enregistrement continuent. Coupez uniquement Internet en gardant la localisation activée; la carte en ligne peut disparaître, tandis que le suivi GPS et l’enregistrement local doivent continuer.
4. Mettez en pause, reprenez, puis terminez. Vérifiez que la pause et la reprise restent des segments distincts et que le parcours généré peut être renommé, exporté, réimporté et sélectionné pour le guidage.
5. Pour vérifier la récupération explicite, démarrez un Run de test, interrompez le processus depuis le système Android, puis relancez MapFollow. Répondez au choix de récupération présenté par l’application et vérifiez les points et segments conservés. Ne concluez pas à une trace continue à travers l’arrêt.
6. Notez les étapes et résultats sans coordonnées GPS, puis partagez seulement le GPX synthétique du test émulateur si un fichier est nécessaire au diagnostic.

### Comparer les trois profils GPS

Effectuez trois Runs GPS réels d’au moins 30 minutes sur le même Samsung, le même itinéraire sûr et dans des conditions aussi proches que possible. Un profil se choisit dans **Réglages** et s’applique au prochain Run; consignez séparément **Précision · 1 s / 0 m**, **Équilibré · 2 s / 3 m** et **Autonomie · 5 s / 5 m**. Ces valeurs sont des demandes au système, pas des promesses d’intervalle ni d’autonomie.

Pour chaque Run, gardez le même réglage réseau et les mêmes conditions d’écran verrouillé, notez le niveau de batterie avant/après, observez l’état GPS et les avertissements, puis ouvrez **Diagnostics GNSS** pendant une portion pour vérifier les satellites vus/utilisés. Pour comparer la cadence effectivement fournie, relevez localement les écarts entre horodatages des points GPX et ne reportez ici que la cadence mesurée en secondes. Ne partagez pas le GPX d’une sortie réelle, ses coordonnées ou des captures; le compte rendu garde uniquement appareil, profil, durée, cadence résumée, batterie et qualité observée.

## Résultats

| Vérification | Résultat (OK / Échec / Non essayé) | Notes sans coordonnées GPS |
|---|---|---|
| Installation et démarrage | | |
| Import GPX, TCX et PWX | | |
| Fichier invalide donne une erreur lisible | | |
| Attribution OSM visible | | |
| Carte et enregistrement sans réseau | | |
| Simulation et annonces | | |
| Démarrer une course libre sans voix ni parcours | | |
| Profil GPS courant est épinglé au Run et réglage change au prochain départ | | |
| Précision, Équilibré et Autonomie comparés pendant 30 min chacun | | |
| Cadence GPS effectivement reçue relevée (sans consigner de coordonnées) | | |
| Batterie avant/après et écran verrouillé relevés pour chaque profil | | |
| Diagnostics GNSS actifs dans panneau visible puis périmés/inactifs à la fermeture | | |
| Alertes visuelles de qualité GPS en course libre | | |
| Notification GPS réel présente; simulation sans service au premier plan | | |
| Pause/reprise et perte GPS conservent des segments | | |
| Course libre complète apparaît dans l’historique et comme parcours enregistré | | |
| Session trop courte reste dans l’historique sans parcours généré | | |
| Renommer le parcours généré synchronise le nom de la session | | |
| GPX conserve les segments et métadonnées disponibles | | |
| GPX exporté/réimporté conserve les directions Aller/Retour avec l’URI mf exacte | | |
| Couches Aller bleu 6 px / Retour orange pointillé 3 px et filtres | | |
| Choix manuel Aller/Retour ne modifie que les prochains points | | |
| Voix française disponible | | |
| Podcast pendant annonce / interruption | | |
| GPS écran verrouillé (durée : ___ min) | | |
| Notification du service visible | | |
| Pause et reprise créent des segments distincts | | |
| Export partagé et ouvert par une autre application | | |
| Historique persiste après redémarrage | | |
| Récupération de session est explicite | | |

## Problèmes observés

- Étapes pour reproduire :
- Résultat attendu :
- Résultat constaté :
- Journaux expurgés de toute coordonnée :
- Session réelle supprimée ou conservée avec consentement :

## Campagne 0.4.0+4 — GPS, OSM, batterie, historique

- Vérifier Précision au prochain départ et le mode Normal/Diagnostic épinglé pendant pause/reprise/récupération.
- Avec un parcours synthétique, vérifier préparation OSM explicite, origines, aller-retour, absence de virage géométrique vocal et comportement sans réseau.
- Vérifier batterie début/fin en Normal, relevés minute et courbe en Diagnostic, recharge et données manquantes. L'export JSON doit avertir des positions GPS.
- Vérifier annulation de suppression, suppression de la course synthétique avec/sans parcours, protection d'un parcours actif. Ne pas supprimer des courses personnelles pour cet essai.
- Nouvelle sortie comparative avec Garmin, écran verrouillé et YouTube Music : noter distance, cadence et écarts résumés. La cible <3 % reste à vérifier ; aucun rapport ne contient de coordonnées.

### Contrôle ADB du 7 octobre 2026

Appareil : Samsung Galaxy S23 Ultra `SM_S918B`, Android 16 ; MapFollow `0.4.0+4`, APK debug. Installation par `adb install -r` réussie, sans désinstallation ni effacement. Les courses précédentes sont visibles dans l'historique et affichent « Batterie non mesurée ». Le profil Précision est sélectionné et le mode global final est Normal.

Un Run libre réel court en Diagnostic a été créé uniquement pour l'essai, sans export de positions. Le service Geolocator est observé au premier plan, type location, avec notification persistante. La mise en veille affiche `mScreenState=OFF` ; lors du contrôle ultérieur l'écran est revenu ON et le service reste actif. Ce contrôle ne valide pas une course prolongée écran verrouillé. Aucun lecteur YouTube Music actif n'a été confirmé.

Après arrêt du processus et relance, le choix Reprendre / Clôturer sans reprendre apparaît explicitement. La clôture réussit ; le résumé affiche 100 % → 100 %, recharge et interruption signalées, courbe présente. Cela vérifie les lectures et relevés détaillés, pas la consommation : le téléphone est en charge. L'export de diagnostic présente une confirmation, annulée sans partage. La suppression présente son option parcours décochée ; l'annulation conserve l'essai. Le nettoyage de cet essai et de son parcours a ensuite été autorisé explicitement par l'utilisateur ; l'essai n'est plus visible et les anciennes courses restent présentes. Aucun service GPS ne reste actif.

Les contrôles automatiques ont refusé l'extraction de la base et des journaux privés du téléphone. La migration exacte, les exports et le rollback de suppression sont couverts par les tests synthétiques. Restent à réaliser : préparation OSM et partage Android réels, pause/reprise physique, suivi prolongé verrouillé avec YouTube Music, Galaxy S21 5G et nouvelle comparaison Garmin (<3 % non validé).

## Campagne 0.5.0+5 — Developer et cadence personnalisée (11 octobre 2026)

Le même APK debug `0.5.0+5` est installé sans désinstallation sur Samsung Galaxy S23 Ultra `SM_S918B`, Android 16, et Galaxy S21 5G `SM-G991B`, Android 15. Sur le S21, `adb install -r`, démarrage à froid, version du paquet et présence des quatre onglets sont confirmés. Aucun Run ni changement de permission n'est effectué sur ce second téléphone ; ses réglages Samsung et sa réception GPS restent à tester.

Sur le S23, Developer est accessible et l'intervalle 0,5 s est sauvegardé, puis retrouvé après arrêt du processus et relance. L'historique antérieur reste présent. Une course terminée Normal est sélectionnée dans Developer ; Exporter les logs ouvre la feuille Android, annulée sans transmettre le fichier. Aucun Run supplémentaire n'est créé ou supprimé. Le mode final est Normal : pour la prochaine sortie, choisir Diagnostic avant le départ pour conserver les données GPS reçues et les décisions du filtre. La présence d'un service Geolocator lié à l'activité ne vaut pas démarrage d'une requête GPS en course ; aucun service au premier plan n'est constaté lors du contrôle final.

La dernière sortie utilisateur avait YouTube Music, Bluetooth, casque et Garmin connectés, avec une baisse déclarée de 4 points de batterie du téléphone entier. MapFollow a démarré 17,4 s avant les premières données Garmin et terminé 19,9 s après. La longueur totale MapFollow est 7 270,7 m ; limitée aux instants Garmin elle devient 7 223,9 m. La montre affichait 7,02 km : écart commun +2,91 %. La longueur géométrique Garmin est distincte, 6 956,9 m, soit +3,84 % GPX-à-GPX. La séparation temporelle interpolée entre les traces est de 6,2 m en médiane et 9,7 m au percentile 95 ; elle ne mesure pas une erreur absolue par rapport au terrain. La cadence MapFollow médiane est 1,0 s et le percentile 95 est 1,082 s. Aucune coordonnée n'est conservée dans ce compte rendu.

Ces données proviennent de la version précédente. Pour valider `0.5.0+5`, effectuer une nouvelle sortie avec Précision, Developer 0,5 s et Diagnostic, en démarrant/arrêtant les deux appareils aux mêmes instants. Noter séparément compteur Garmin, longueur GPX, distance MapFollow, cadence réellement reçue, batterie, recharge et éventuelles interruptions. Viser ≤2 % sur la période comparable ; cette cible n'est pas encore validée. Exporter explicitement GPX et logs après la course ; les positions des logs sont décochées par défaut. Le suivi prolongé écran verrouillé avec YouTube Music reste à vérifier sur chaque téléphone.
