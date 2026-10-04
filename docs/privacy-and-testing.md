# Confidentialité et essais manuels

## Données et confidentialité

Les courses et points GPS sont conservés dans SQLite sur l’appareil par l’application. Le manifeste Android désactive `allowBackup` et la sauvegarde complète; `data_extraction_rules.xml` exclut les données de la sauvegarde cloud et du transfert d’appareil. Le prototype n’envoie pas les courses à un serveur et ne possède ni compte, ni suivi partagé. Le comportement système après installation/restauration n’a pas encore été validé sur appareil. Un fichier GPX exporté via une autre application suit aussi les règles de cette application.

La carte télécharge les tuiles OpenStreetMap au fil de l’affichage. Le service de tuiles peut voir l’adresse IP et la zone cartographique demandée. L’attribution OpenStreetMap est visible dans l’application. Les cartes ne sont pas disponibles hors ligne. Respectez la [politique de tuiles OSM](https://operations.osmfoundation.org/policies/tiles/) et les licences/attributions des dépendances présentes dans `pubspec.yaml`.

N’utilisez jamais une vraie trace GPS dans les fixtures, captures, journaux, commits ou rapports d’agents. Les exemples doivent être synthétiques. L’application n’a pas encore d’interface de suppression durable des sessions : expliquez-le à l’utilisateur avant tout essai avec ses données personnelles.

## Essai terrain d’une heure

Utilisez un itinéraire synthétique et un participant consentant. N’essayez pas de manipuler le téléphone en courant. Complétez la [fiche de compte rendu](field-validation.md) et ne conservez pas la trace réelle après l’essai sauf demande explicite du participant.

1. Installer et ouvrir l’application; examiner la demande de permission puis autoriser la localisation.
2. Essayer l’import du GPX inclus, puis un fichier synthétique TCX et PWX; confirmer qu’un fichier malformé retourne un message utile.
3. Vérifier l’attribution de la carte. Couper temporairement le réseau et observer l’état de la carte et l’enregistrement local.
4. Dans l’onglet Course, démarrer le simulateur et observer la progression et les indications. Dans Réglages, essayer le bouton de test vocal avec un podcast, puis déclencher une interruption audio si possible.
5. Démarrer un suivi GPS réel à l’extérieur avec consentement. Verrouiller l’écran au moins 15 minutes et vérifier la notification et la continuité des points.
6. Mettre en pause, attendre, reprendre puis terminer. Vérifier qu’il n’y a aucune ligne dessinée à travers la pause.
7. Exporter le GPX avec la feuille de partage, l’ouvrir dans une autre application et comparer le nombre de points et segments.
8. Fermer et relancer MapFollow. Vérifier l’historique et le dialogue de récupération explicite d’une éventuelle session interrompue.
9. Si disponibles, répéter le test écran verrouillé sur Galaxy S23 Ultra et Galaxy S21 5G; consigner Android/One UI et les réglages de batterie.

L’essai d’une heure est un contrôle pratique, pas une preuve de fiabilité sur une journée complète. Les essais physiques sont en attente de résultats confirmés.
