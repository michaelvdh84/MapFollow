---
name: mapfollow-development
description: Develop the MapFollow Flutter route-following proof of concept while preserving its architecture, privacy, and Android behavior boundaries.
---

# Développement MapFollow

Pour les changements de code, consultez [l’état du projet](../../../PLAN.md), [l’architecture](../../../STRUCTURE.md), et les guides Android et confidentialité lorsqu’ils concernent le changement.

- Gardez les modèles dans `lib/domain`, les adaptations de plugins et accès locaux dans `lib/data`, la coordination `ChangeNotifier` dans `lib/application`, et les widgets dans `lib/presentation`.
- Employez des coordonnées synthétiques dans les exemples et tests. Ne mettez pas de vraies coordonnées GPS dans le dépôt, les logs, captures d’écran ou rapports. L’export GPX que l’utilisateur déclenche dans l’application est une fonction attendue; conservez son action explicite.
- Gardez une seule session active; pause, perte GPS et reprise ouvrent des segments séparés. La récupération après arrêt nécessite un choix explicite.
- Préservez les limites v1 : tuiles OSM en ligne avec attribution, stockage SQLite local et partage GPX; pas de serveur, compte, partage live, carte hors ligne ou suppression d’historique.
- Le focus audio passe par le pont natif `mapfollow/audio` en mode `MAY_DUCK`; arrêtez les annonces sur interruption et ne garantissez pas le comportement des lecteurs tiers.
- La voix française hors ligne est une condition au démarrage de la session. Les fichiers importés sont limités à 10 MiB et 100 000 points; conservez les ruptures de trace.
- Utilisez `scripts/flutter.ps1` pour les commandes Flutter locales. Consultez [PLAN.md](../../../PLAN.md) pour l’état actuel des builds et vérifications. Ne généralisez pas les tests automatisés aux essais terrain. S23 Ultra (principal) et S21 5G (secondaire) restent à valider.
- Pour les essais terrain et données sensibles, lisez [la procédure et sa fiche](../../../docs/privacy-and-testing.md) et [field-validation.md](../../../docs/field-validation.md).
