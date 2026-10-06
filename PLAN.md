# Plan et état de MapFollow

## État actuel

Le code courant porte la version `0.3.0+3`; 99 tests passent, l’analyse ne détecte aucun problème, le formatage a vérifié 44 fichiers sans modification et l’APK debug a été construit et vérifié (AAPT). Les 52 tests et les autres résultats associés à l’APK mentionnés plus bas concernent la version précédente `0.2.0+2`. Aucun essai manuel ni partage Android réel n’a été effectué; Samsung Galaxy S23 Ultra et Galaxy S21 5G restent à valider sans déclaration de compatibilité. Voir [le journal de vérification](docs/verification.md).

| Domaine | Comportement disponible | Vérification connue |
|---|---|---|
| Application | Flutter, interface française; onglets Parcours, Course, Historique, Réglages | Analyse, 99 tests, formatage et APK debug `0.3.0+3` confirmés; détails dans le journal |
| Cartographie | `flutter_map`, tuiles OpenStreetMap en ligne avec attribution | Essai physique en attente |
| Import | XML GPX, TCX, PWX; limites 10 MiB et 100 000 points; les ruptures invalides restent des segments distincts | Couvert par les 99 tests de `0.3.0+3`; aucun essai de partage réel |
| Navigation | Progression vers l’avant, qualité GPS, détection d’écart et rappels configurables | Suite automatisée `0.3.0+3` réussie; essais GPS et voix réels à faire |
| Voix | `flutter_tts` avec demande native temporaire d’audio focus MAY_DUCK; interruptions arrêtent la voix guidée | Tests automatisés réussis; comportement avec lecteurs audio réels à vérifier |
| Course | Points enregistrés localement dans SQLite; transactions d’écriture atomiques; une seule session active | Suite automatisée `0.3.0+3` réussie; essai terrain à faire |
| Pause/reprise | Les pauses, pertes GPS et reprises créent des segments distincts | Tests automatisés réussis; interruption réelle et reprise sur téléphone à vérifier |
| Simulation | Guidage à 3 m/s; Run libre déterministe aller-retour sans service de premier plan | Tests automatisés réussis; essai manuel en attente |
| Export | GPX via feuille de partage Android, métadonnées GPS et direction; fichiers temporaires dans le cache | Tests automatisés réussis; partage Android réel à vérifier |
| Récupération | Une session interrompue est proposée explicitement à l’utilisateur | Tests automatisés réussis; récupération après arrêt sur téléphone à vérifier |
| Course libre | Démarrage sans parcours source ni voix; GPS réel avec notification et simulation déterministe sans service de premier plan; qualité GPS affichée; pause/reprise segmentées | 99 tests réussis; essai terrain en attente |
| Parcours enregistré | Une course libre assez longue est aussi sauvegardée sous `recorded-{run.id}`; une session courte reste dans l’historique; nom synchronisé | Tests automatisés réussis; parcours UI sur appareil à vérifier |
| GPX enrichi | Extensions des métadonnées GPS disponibles (vitesse, précision, cap) | Tests automatisés réussis; partage sur appareil à vérifier |
| Profils GPS | Précision 1 s/2 m, Équilibré 2 s/3 m, Autonomie 5 s/5 m; choix épinglé par session | Tests automatisés réussis; intervalles non garantis et comparaison terrain à faire |
| Traversée aller/retour | Classifieur heuristique, choix manuel sur prochains points et calques filtrables | Tests automatisés réussis; ambiguïtés possibles sur voies parallèles proches; validation terrain à faire |
| Métriques de course | Vitesse moyenne glissante sur 5 s, allure et résumé basé sur temps actif | Tests automatisés `0.3.0+3` réussis |
| Diagnostics GNSS | Comptes vus/utilisés observés depuis récepteur actif, sans second fix ni persistance | Tests automatisés réussis; observation sur appareil à faire |

## Prochaine vérification

1. Installer l’APK debug sur un téléphone Android et remplir [la fiche terrain](docs/field-validation.md); aucun téléphone n’était connecté lors du dernier contrôle.
2. Vérifier permissions et suivi écran verrouillé, interruption audio, partage GPX, reprise, Bluetooth et réglages de batterie Samsung.
3. Évaluer iOS seulement après le jalon Android; le squelette iOS généré ne signifie pas qu’iOS fonctionne.

## Hors périmètre v1

Publication Play Store, serveur, compte/authentification, partage de position en direct, fonds de carte hors ligne et écran de suppression des données. Ne pas créer de suppression destructive sans spécification et validation dédiées.
