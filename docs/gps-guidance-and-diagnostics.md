# GPS, indications et diagnostics — 0.4.0+4

## Préparer une course

Dans Réglages, **Précision · 1 s / 0 m** est le défaut des nouveaux réglages. Une préférence GPS déjà enregistrée est conservée. Équilibré demande toujours 2 s / 3 m et Autonomie 5 s / 5 m. Chaque course épingle son profil ; le changer ne modifie que le prochain départ. Sur Android, ces profils demandent tous la haute précision au fournisseur de localisation. La cadence, la précision et l'autonomie réellement obtenues dépendent du système et des conditions de réception.

Les mesures GPS réelles passent par un filtre Kalman local 2D à vitesse constante, pondéré par la précision annoncée. Le filtre rejette les valeurs invalides et les sauts incompatibles avec les mesures précédentes, atténue le bruit et stabilise les virages avec un bruit d'accélération adaptatif. Une immobilité n'est reconnue qu'après trois vitesses valides inférieures ou égales à 0,5 m/s et des positions cohérentes. Une vitesse absente reste inconnue. Les positions traitées servent au dessin, à la distance, au guidage et aux passages Aller/Retour ; le cap Android reste une métadonnée et ne choisit pas les intersections. Aucun point n'est inventé pendant une absence de mesure et aucun recalage sur une route OSM n'est appliqué à l'enregistrement.

La simulation conserve ses coordonnées déterministes sans filtre Kalman ni service Android. Pause, reprise, perte GPS et récupération gardent des segments distincts. Un pic isolé rejeté pour saut ou innovation n'impose pas à lui seul une rupture entre les bonnes positions voisines. Le classement Auto reste heuristique : caps stabilisés sur plusieurs points, couloir 15 m, exclusion des 30 m récents, seuils 45°/135° et confirmation sur trois positions et 15 m. Les voies parallèles proches restent ambiguës.

## Préparer les intersections

Avant le départ, **Préparer les indications avec OpenStreetMap** demande confirmation de l'envoi de la zone du parcours à Overpass. Cette action est facultative et n'est jamais déclenchée par l'ouverture d'une course ou par une position GPS.

Le prototype personnel utilise `https://overpass-api.de/api/interpreter`, configurable à la compilation par `MAPFOLLOW_OVERPASS_ENDPOINT`. Une requête sélectionne les chemins dans un couloir de 80 m autour d'un échantillonnage du parcours ; limites : 100 km, 100 segments, 2 500 points de requête, réponse 6 MiB, 100 000 éléments OSM, 75 000 arêtes et 20 000 échantillons de correspondance. HTTPS uniquement, aucune redirection automatique ; délai total 35 s, délai de requête Overpass 25 s. Une panne propose une nouvelle tentative manuelle. Le cache cartographique local vit au plus sept jours pour la réutilisation et reste limité à 24 MiB. Il ne contient pas de tuiles préchargées.

Les indications reposent sur les connexions entre identifiants de nœuds OSM. Un pont ou deux voies qui se croisent sans nœud connecté ne produisent pas une intersection. Le parcours est traité dans son ordre : les passages aller et retour portent des distances et identifiants d'indication distincts. La reconnaissance reste conservative, avec couloir de correspondance 20 m et passages de jonction à 15 m : les portions absentes ou ambiguës affichent « Suivez le tracé ».

Les origines affichées sont **fichier**, **OpenStreetMap** et **estimation géométrique**. Les indications explicites du fichier sont conservées et priment près du même passage. Les estimations géométriques sont dans une liste secondaire et ne sont plus annoncées vocalement. Les indications préparées sont enregistrées avec le parcours et utilisables sans nouvel appel réseau. Le fond de carte reste en ligne avec attribution OSM visible ; aucune carte hors ligne n'est promise.

Références : [modèle de requêtes Android](https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest.Builder), [Overpass QL](https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL), [politique des instances publiques](https://dev.overpass-api.de/overpass-doc/en/preface/commons.html). Un service destiné à un public plus large devra remplacer l'instance publique par une solution adaptée.

## Batterie et diagnostic local

**Normal**, défaut : deux instantanés, début et fin. Le résumé montre niveau, état de charge et variation en points de pourcentage. Les anciennes courses affichent « Batterie non mesurée ». Une reprise après arrêt signale la période sans mesures ; une fin sans mesure initiale ne fabrique pas de bilan complet.

**Diagnostic**, à choisir avant le départ : instantanés au début, toutes les minutes pendant le suivi actif, à la pause, à la reprise, à l'interruption et à la fin. Le résumé ajoute une courbe lorsque suffisamment de mesures sont disponibles. Le mode reste épinglé au Run même après récupération. Le pont `mapfollow/battery` lit les données Android existantes, sans permission supplémentaire ; niveau, charge, température, tension, courant et charge restante sont nullables selon le matériel. Une lecture indisponible n'empêche pas le Run.

Le diagnostic conserve aussi les mesures GPS reçues, y compris les mesures rejetées, l'heure de réception, le résultat traité, la décision du filtre et l'état d'enregistrement. Ces données restent dans SQLite ; aucune coordonnée ne doit apparaître dans les journaux de développement. **Exporter le diagnostic** prévient que le JSON contient des positions et demande une action explicite avant la feuille de partage. Les comptages GNSS ne sont ni conservés ni exportés. Le GPX habituel contient les positions traitées et leurs métadonnées disponibles.

La batterie mesurée est celle du **téléphone entier**, incluant YouTube Music, l'écran, le réseau et les autres applications. Une recharge ou des mesures manquantes sont signalées. Une baisse de 7 points ne mesure pas une consommation attribuable exclusivement à MapFollow. [API batterie Android](https://developer.android.com/training/monitoring-device-state/battery-monitoring).

## Supprimer une course

Dans Historique, **Supprimer** est disponible sur les courses terminées. Le dialogue précise le caractère définitif et propose **Supprimer aussi le parcours généré**, décoché par défaut. Le parcours reste alors réutilisable. Une course active ou récupérable empêche la suppression de son parcours source. Les parcours importés ne sont jamais supprimés par cette action.

SQLite v2 supprime en transaction la course, ses points et ses diagnostics, ainsi que son parcours généré lorsque demandé. Une erreur restaure l'ensemble. Les exports déjà partagés restent à leur destination ; leur suppression appartient à cette destination. La migration depuis v1 ne modifie pas les anciennes positions ni les préférences explicitement enregistrées.

## Validation terrain

Les tests synthétiques valident les mécanismes, pas la précision réelle d'un téléphone. Comparer une nouvelle sortie Garmin/MapFollow avec Précision, même parcours et mêmes conditions d'écran/audio. Mesurer distance, cadence et écarts au tracé ; viser moins de 3 % d'écart de distance sans déclarer cette cible atteinte avant essai. Consigner modèle, OS, build et étapes dans [la fiche terrain](field-validation.md), sans coordonnées ni GPX réel.

Le rejeu en mémoire de la trace MapFollow fournie, sans sauvegarde des coordonnées, donne 7 524,5 m après traitement contre 7 500,0 m auparavant, avec sept mesures rejetées. Il ne démontre pas d'amélioration de l'écart de distance observé avec Garmin (~7 049 m). L'ancienne trace n'est pas modifiée ; la cadence 1 s et le filtre restent à évaluer sur une nouvelle acquisition. L'implémentation atténue le bruit synthétique et les sauts, sans garantir la correction d'une dérive systématique de positions.
