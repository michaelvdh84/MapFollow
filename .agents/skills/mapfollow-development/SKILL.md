---
name: mapfollow-development
description: Develop the MapFollow Flutter route-following proof of concept while preserving its architecture, privacy, and Android behavior boundaries.
---

# Développement MapFollow

Pour les changements de code, consultez [l’état du projet](../../../PLAN.md), [l’architecture](../../../STRUCTURE.md), et les guides Android et confidentialité lorsqu’ils concernent le changement.

- Gardez les modèles dans `lib/domain`, les adaptations de plugins et accès locaux dans `lib/data`, la coordination `ChangeNotifier` dans `lib/application`, et les widgets dans `lib/presentation`.
- Employez des coordonnées synthétiques dans les exemples et tests. Ne mettez pas de vraies coordonnées GPS dans le dépôt, les logs, captures d’écran ou rapports. L’export GPX que l’utilisateur déclenche dans l’application est une fonction attendue; conservez son action explicite.
- Gardez une seule session active; pause, perte GPS et reprise ouvrent des segments séparés. La récupération après arrêt nécessite un choix explicite.
- Préservez les limites : tuiles OSM en ligne avec attribution, stockage SQLite local et partage GPX; pas de serveur, compte, partage live ou carte hors ligne. La suppression individuelle terminée est confirmée et atomique ; le parcours généré est conservé par défaut et un parcours actif/récupérable est protégé.
- Le focus audio passe par le pont natif `mapfollow/audio` en mode `MAY_DUCK`; arrêtez les annonces sur interruption et ne garantissez pas le comportement des lecteurs tiers.
- En mode guidé, une voix française hors ligne est une condition au démarrage; le mode course libre n’a ni itinéraire source ni annonce vocale. Les fichiers importés sont limités à 10 MiB et 100 000 points; conservez les ruptures de trace.
- Le GPS réel garde le service Android au premier plan et sa notification; les alertes de qualité GPS en course libre restent visuelles. La simulation est déterministe et ne lance pas le service au premier plan.
- Une course libre complète assez longue est aussi enregistrée comme parcours stable `recorded-{run.id}`; une session trop courte reste dans l’historique sans parcours. Les simulations commencent par `SIMULATION`; renommer un parcours généré synchronise le nom de session. Le GPX enrichi comprend les métadonnées GPS disponibles (vitesse, précision, cap).
- Chaque Run épingle son profil GPS (`precise` 1 s/0 m, `balanced` 2 s/3 m, `autonomy` 5 s/5 m) ; `precise` est le défaut, les choix sauvegardés sont conservés et les anciennes sessions absentes du champ retombent sur `precise`. Developer peut remplacer l'intervalle par 250–10 000 ms avec distance minimale 0 m ; ce remplacement est épinglé à la session et repris après récupération. Ce sont des requêtes à Android, jamais une garantie de cadence, précision ou autonomie.
- Respectez les indicateurs de présence Geolocator : les valeurs absentes ne deviennent pas des zéros. Les incertitudes de vitesse/cap sont facultatives ; le filtre utilise la norme de vitesse GNSS uniquement avec incertitude exploitable et calcule ses directions depuis les positions.
- Developer sélectionne Normal/Diagnostic avant départ et exporte les logs d'une course terminée. Les positions GPS sont exclues par défaut ; les inclure est explicite et le consentement se réinitialise au changement de course. Une ancienne course Normal n'acquiert pas de mesures détaillées rétrospectivement. La batterie mesure le téléphone entier. Aucun comptage GNSS n'est persisté ou exporté.
- La vitesse enregistrée reste nullable. L’interface moyenne les vitesses valides sur 5 s; vide la fenêtre après pause/reprise; la pause affiche 0 km/h et allure `--`; le résumé utilise distance/durée active.
- Auto classe les passages avec l’heuristique `TraversalClassifier` (cellules 25 m, couloir 15 m, exclusion des 30 m récents, seuil de direction 45°/135°, confirmation 3 positions sur 15 m). Les chemins parallèles proches restent ambigus; les choix Aller/Retour manuels ne changent que les prochains points. Ne modifiez pas le sens du guidage importé.
- La simulation du Run libre fait deux passages sur le même tracé synthétique déterministe, sans service de premier plan. Conservez les libellés de direction par point dans les métadonnées GPX et le namespace versionné exact.
- Le panneau GNSS observe seulement le récepteur existant via `mapfollow/gnssStatus` tant que le panneau est visible et l’activité reprise. N’ajoutez aucune requête GPS, sélection de constellation, persistance de comptes, ni journalisation GNSS; les états inactif/attente de première observation/permission/indisponible/périmé sont explicites et les comptages ne garantissent pas la précision.
- Utilisez `scripts/flutter.ps1` pour les commandes Flutter locales. Consultez [PLAN.md](../../../PLAN.md) pour l’état actuel des builds et vérifications. Ne généralisez pas les tests automatisés aux essais terrain. S23 Ultra (principal) et S21 5G (secondaire) restent à valider.
- Pour les essais terrain et données sensibles, lisez [la procédure et sa fiche](../../../docs/privacy-and-testing.md) et [field-validation.md](../../../docs/field-validation.md).
