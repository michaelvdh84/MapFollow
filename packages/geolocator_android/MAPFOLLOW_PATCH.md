# Adaptation locale Geolocator Android

Base : paquet publié `geolocator_android 5.1.1+1`, installé par le verrou Pub du projet avant cet audit. Sources originales : [Baseflow](https://github.com/Baseflow/flutter-geolocator/tree/main/geolocator_android), [version publiée](https://pub.dev/packages/geolocator_android/versions/5.1.1%2B1). Licence MIT et auteurs conservés. Les exemples et tests Dart amont ne sont pas embarqués ; le code du plugin et les tests Android sont conservés.

SHA-256 de l'archive Pub dans le verrou original : `1be90ea8aaaf9db8e7816b4fe0387f082ee8b5cf03355912dad90fb0a75717fa`.

Cette copie est résolue par `dependency_overrides` dans le pubspec racine. Aucun fichier du cache Pub n'est modifié. Une mise à jour amont doit comparer les changements ci-dessous, puis relancer les tests Android et Flutter avant de retirer ou mettre à jour l'override.

Modifications locales :

- `FusedLocationClient.java` : builder Google Play Services sur toutes les API Android prises en charge, minimum égal à l'intervalle demandé, âge initial zéro, délai de regroupement demandé zéro et attente précise explicite. Livraison de chaque position du callback dans son ordre. Résultats asynchrones ignorés après arrêt ; échec d'inscription transmis au flux.
- `LocationMapper.java` : temps monotone de mesure et de réception native, en nanosecondes.
- `android_position.dart` : métadonnées monotones facultatives, mapping, égalité et sérialisation.
- `android/build.gradle` : stubs Android autorisés pour les tests JVM. Aucun changement des dépendances Android de production.
- Tests Java des paramètres, lots, absence de points et métadonnées.

Les fournisseurs Fused et LocationManager, les permissions, la notification et le service restent ceux du plugin. `LocationSettings`, `AndroidSettings` et leurs paramètres publics sont conservés. Le délai zéro est normalisé par Google à l'intervalle ; `isBatched()` reste faux. L'adaptation ne fixe jamais l'intervalle à 1 s : Developer conserve notamment 500 ms.

Voir [l'audit](../../docs/android-location-audit.md) et le journal de vérification du projet.
