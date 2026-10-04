# Consignes pour le dépôt

- Consultez [PLAN.md](PLAN.md) et [le journal de vérification](docs/verification.md) pour l’état réel des fonctions et contrôles. APK debug construit, analyse sans problème, 34 tests réussis et formatage propre sont confirmés; les essais physiques restent à faire.
- Respectez la séparation décrite dans [STRUCTURE.md](STRUCTURE.md): modèles dans `lib/domain`, accès et plugins dans `lib/data`, orchestration `ChangeNotifier` dans `lib/application`, interface dans `lib/presentation`.
- Utilisez `assets/demo.gpx` ou des coordonnées synthétiques dans les exemples, logs, captures, commits et rapports. L’export GPX déclenché par l’utilisateur dans l’application reste autorisé et attendu.
- Les données des courses sont locales; Android désactive les sauvegardes cloud et transferts d’appareil dans le manifeste/règles d’extraction. Ne promettez pas une confidentialité plus forte sans valider le parcours de restauration. Il n’existe pas encore de suppression d’historique.
- Une seule course active; pause/perte GPS/reprise doivent rester des segments distincts. La récupération après arrêt du processus est explicite.
- La carte dépend des tuiles en ligne OSM et doit garder l’attribution visible. Ne préchargez pas les tuiles et ne présentez pas une carte hors ligne comme disponible.
- Le suivi en premier plan dépend des permissions, de l’OS et des restrictions constructeur. La voix demande le focus natif Android; ne promettez pas un comportement identique avec tous les lecteurs de podcasts.
- Utilisez `scripts/flutter.ps1` et les outils dans `.tools/`. Ne supposez pas que ces outils soient présents sur un autre poste.
- Pour les essais physiques, notez modèle, OS, build et étapes dans [la fiche terrain](docs/field-validation.md). Samsung S23 Ultra et S21 5G restent à valider.
