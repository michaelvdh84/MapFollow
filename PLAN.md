# Plan et état de MapFollow

## État actuel

Le code courant porte la version `0.5.0+5`. Il ajoute **Developer**, l'intervalle GPS personnalisé (dont 0,5 s), l'export de logs sans coordonnées par défaut et un filtre adapté aux cadences rapprochées, aux courbes et à la vitesse GNSS disponible. Voir [le comportement détaillé](docs/gps-guidance-and-diagnostics.md) et [le journal de vérification](docs/verification.md). La dernière sortie utilisateur donne +2,91 % sur la période commune face aux 7,02 km affichés par Garmin ; la nouvelle cible ≤2 % nécessite une sortie avec `0.5.0+5`. Les vérifications `0.4.0+4` et antérieures restent historiques.

Pour le prochain essai : Précision, Developer à 0,5 s, mode Diagnostic avant départ, mêmes instants de départ et arrêt que Garmin. Exporter GPX et logs explicitement après la course ; les coordonnées des logs restent décochées par défaut. La baisse de 4 points de batterie déclarée pour la dernière sortie inclut YouTube Music et Bluetooth.

| Domaine | Comportement disponible | Vérification connue |
|---|---|---|
| Application | Flutter, interface française; onglets Parcours, Course, Historique, Réglages | Analyse, 157 tests, formatage et build `0.5.0+5` ; installation et démarrage S23/S21 réussis ; détails dans le journal |
| Cartographie | `flutter_map`, tuiles OpenStreetMap en ligne avec attribution | Essai physique en attente |
| Import | XML GPX, TCX, PWX; limites 10 MiB et 100 000 points; les ruptures invalides restent des segments distincts | Couvert par la suite de 157 tests de `0.5.0+5`; aucun essai de partage réel |
| Navigation | Progression vers l’avant, qualité GPS, détection d’écart et rappels configurables | Suite automatisée `0.5.0+5` réussie; essais GPS et voix réels à faire |
| Voix | `flutter_tts` avec demande native temporaire d’audio focus MAY_DUCK; interruptions arrêtent la voix guidée | Tests automatisés réussis; comportement avec lecteurs audio réels à vérifier |
| Course | Points enregistrés localement dans SQLite; transactions d’écriture atomiques; une seule session active | Suite automatisée `0.5.0+5` réussie; essai terrain à faire |
| Pause/reprise | Les pauses, pertes GPS et reprises créent des segments distincts | Tests automatisés réussis; interruption réelle et reprise sur téléphone à vérifier |
| Simulation | Guidage à 3 m/s; Run libre déterministe aller-retour sans service de premier plan | Tests automatisés réussis; essai manuel en attente |
| Export | GPX via feuille de partage Android, métadonnées GPS et direction; fichiers temporaires dans le cache | Tests automatisés réussis; partage Android réel à vérifier |
| Récupération | Une session interrompue est proposée explicitement à l’utilisateur | Tests automatisés réussis; récupération après arrêt sur téléphone à vérifier |
| Course libre | Démarrage sans parcours source ni voix; GPS réel avec notification et simulation déterministe sans service de premier plan; qualité GPS affichée; pause/reprise segmentées | 157 tests réussis; essai terrain en attente |
| Parcours enregistré | Une course libre assez longue est aussi sauvegardée sous `recorded-{run.id}`; une session courte reste dans l’historique; nom synchronisé | Tests automatisés réussis; parcours UI sur appareil à vérifier |
| GPX enrichi | Extensions des métadonnées GPS disponibles (vitesse, précision, cap) | Tests automatisés réussis; partage sur appareil à vérifier |
| Profils GPS | Précision 1 s/0 m par défaut des nouveaux réglages, Équilibré 2 s/3 m, Autonomie 5 s/5 m; préférences conservées, choix épinglé par session | Intervalles non garantis ; filtre testé sur données synthétiques, comparaison terrain à faire |
| Developer | Intervalle 250–10 000 ms épinglé ; export après course sans positions par défaut | Tests UI/persistance/export réussis ; 0,5 s sauvegardé sur S23 et feuille de partage Normal ouverte puis annulée |
| Traversée aller/retour | Classifieur heuristique, choix manuel sur prochains points et calques filtrables | Tests automatisés réussis; ambiguïtés possibles sur voies parallèles proches; validation terrain à faire |
| Métriques de course | Vitesse moyenne glissante sur 5 s, allure et résumé basé sur temps actif | Tests automatisés `0.5.0+5` réussis |
| Diagnostics GNSS | Comptes vus/utilisés observés depuis récepteur actif, sans second fix ni persistance | Tests automatisés réussis; observation sur appareil à faire |
| Intersections OSM | Préparation explicite via Overpass, cache local borné, branches connectées et passages ordonnés ; origine affichée | Tests synthétiques des intersections, ponts, ambiguïtés, réseau et cache ; essai terrain à faire |
| Batterie et diagnostics | Normal début/fin ; Diagnostic minute, événements et GPS brut/filtré exportable explicitement | Tests du pont, résumé, événements, récupération et export ; consommation du téléphone entier |
| Suppression | Course terminée, confirmation et option parcours généré décochée ; SQLite v2 atomique | Tests annulation, conservation, protection active, migration et rollback |

## Prochaine vérification

1. Compléter [la fiche terrain](docs/field-validation.md) après l'installation et les contrôles ADB partiels réussis sur Samsung S23 Ultra et S21 5G.
2. Vérifier permissions et suivi écran verrouillé, interruption audio, partage GPX, reprise, Bluetooth et réglages de batterie Samsung.
3. Comparer une nouvelle sortie Garmin avec Précision, Developer à 0,5 s et Diagnostic ; viser ≤2 % sur la période comparable et noter la distance du compteur Garmin séparément de la longueur de son GPX.
4. Évaluer iOS seulement après le jalon Android; le squelette iOS généré ne signifie pas qu’iOS fonctionne.

## Hors périmètre v1

Publication Play Store, serveur, compte/authentification, partage de position en direct et fonds de carte hors ligne. La suppression individuelle de l’historique fait partie de `0.4.0+4` ; aucune suppression globale n’est proposée.
