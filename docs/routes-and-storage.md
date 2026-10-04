# Parcours, enregistrement et export

## Importer un parcours

MapFollow importe des fichiers XML GPX, TCX et PWX. Le fichier doit être encodé en UTF-8, mesurer au plus 10 MiB et contenir au plus 100 000 points. Les points invalides ou les discontinuités ne sont pas reliés artificiellement : les ruptures de parcours restent représentées par des segments distincts. Des exemples de démonstration synthétiques se trouvent dans `assets/demo.gpx`.

Les fichiers peuvent contenir des informations différentes selon leur format et l’application qui les a produits. L’import conserve la géométrie et traite les champs facultatifs lorsqu’ils sont présents. En cas d’erreur, réessayez avec un export GPX/TCX/PWX standard et un fichier plus petit.

## Enregistrer une course

Les sessions et points sont stockés localement dans SQLite. Une seule session peut être active à la fois. Les insertions de points sont regroupées de façon atomique pour éviter de laisser une écriture partielle.

La pause, la perte de signal GPS et une reprise créent des segments distincts. Le tracé ne dessine donc pas une fausse ligne droite par-dessus une période sans point. Une session interrompue à la fermeture peut être proposée explicitement au prochain démarrage; vérifiez les dates et segments avant de continuer ou terminer cette session.

Le simulateur avance à 3 m/s et emprunte le même moteur de localisation que le GPS. Utilisez-le pour essayer les annonces et le suivi sans enregistrer une vraie trace de déplacement.

## Exporter en GPX

Depuis l’historique, partagez la session au format GPX via la feuille de partage Android. Le fichier préserve les limites entre les segments. Une copie temporaire est créée pour le partage et est supprimée lorsque Android vide le cache de l’application; elle peut donc subsister quelque temps dans le cache. Il n’y a pas encore de bouton pour effacer une session ou supprimer immédiatement ce fichier temporaire.

La suite automatisée complète a réussi ses 34 tests. Le partage Android et l’ouverture du fichier dans une autre application restent à vérifier lors des essais terrain.
