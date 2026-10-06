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

Ces étapes sont à réaliser et à consigner pour chaque émulateur ou appareil. Aucun essai manuel n’est confirmé pour `0.3.0+3`. Utilisez uniquement un Run synthétique sur émulateur; sur téléphone, n’inscrivez aucune coordonnée dans ce compte rendu et ne joignez pas de GPX réel.

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

Effectuez trois Runs GPS réels d’au moins 30 minutes sur le même Samsung, le même itinéraire sûr et dans des conditions aussi proches que possible. Un profil se choisit dans **Réglages** et s’applique au prochain Run; consignez séparément **Précision · 1 s / 2 m**, **Équilibré · 2 s / 3 m** et **Autonomie · 5 s / 5 m**. Ces valeurs sont des demandes au système, pas des promesses d’intervalle ni d’autonomie.

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
