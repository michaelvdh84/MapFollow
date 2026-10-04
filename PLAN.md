# Plan et état de MapFollow

## État actuel

Le prototype Android est implémenté. Le 4 octobre 2026, le dernier APK debug a été construit, l’analyse a terminé sans problème, les 34 tests ont réussi et `dart format` n’a modifié aucun fichier. La vérification AAPT confirme le paquet, la version et les API Android ciblées. Aucun téléphone n’était connecté; les essais terrain, Samsung et Bluetooth restent à faire. Voir [le journal de vérification](docs/verification.md). Samsung Galaxy S23 Ultra est l’appareil principal visé et Galaxy S21 5G le second appareil de référence, sans déclaration de compatibilité.

| Domaine | Comportement disponible | Vérification connue |
|---|---|---|
| Application | Flutter, interface française; onglets Parcours, Course, Historique, Réglages | Implémentée; APK debug construit; analyse sans problème |
| Cartographie | `flutter_map`, tuiles OpenStreetMap en ligne avec attribution | Essai physique en attente |
| Import | XML GPX, TCX, PWX; limites 10 MiB et 100 000 points; les ruptures invalides restent des segments distincts | Suite complète : 34 tests réussis |
| Navigation | Progression vers l’avant, qualité GPS, détection d’écart et rappels configurables | Tests automatisés réussis; essai GPS réel sur appareil en attente |
| Voix | `flutter_tts` avec demande native temporaire d’audio focus MAY_DUCK; interruptions arrêtent la voix | Tests automatisés réussis; essais avec lecteurs audio réels en attente |
| Course | Points enregistrés localement dans SQLite; transactions d’écriture atomiques; une seule session active | Tests automatisés réussis; enregistrement terrain en attente |
| Pause/reprise | Les pauses, pertes GPS et reprises créent des segments distincts | Tests automatisés réussis; test de session interrompue réelle en attente |
| Simulation | Déplacement synthétique à 3 m/s par le même moteur de suivi | Tests automatisés réussis; test de bout en bout sur téléphone en attente |
| Export | GPX via la feuille de partage Android; fichiers temporaires nettoyés par Android au moment de vider son cache | Tests automatisés réussis; partage avec une autre application en attente |
| Récupération | Une session interrompue est proposée explicitement à l’utilisateur | Tests automatisés réussis; récupération après arrêt sur téléphone en attente |

## Prochaine vérification

1. Installer l’APK debug sur un téléphone Android et remplir [la fiche terrain](docs/field-validation.md); aucun téléphone n’était connecté lors du dernier contrôle.
2. Vérifier permissions et suivi écran verrouillé, interruption audio, partage GPX, reprise, Bluetooth et réglages de batterie Samsung.
3. Évaluer iOS seulement après le jalon Android; le squelette iOS généré ne signifie pas qu’iOS fonctionne.

## Hors périmètre v1

Publication Play Store, serveur, compte/authentification, partage de position en direct, fonds de carte hors ligne et écran de suppression des données. Ne pas créer de suppression destructive sans spécification et validation dédiées.
