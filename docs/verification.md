# Journal de vérification

## Contrôles de la version actuelle — `0.4.0+4` (7 octobre 2026)

| Contrôle | Commande / méthode | Résultat |
|---|---|---|
| Analyse Dart | `scripts/flutter.ps1 analyze` | Aucun problème ; 10,2 s |
| Suite complète | `scripts/flutter.ps1 test` | 143 tests réussis ; 20 s |
| Formatage | `dart format --output=none --set-exit-if-changed lib test` | 60 fichiers ; 0 modifié |
| Build Android debug | `scripts/flutter.ps1 build apk --debug` | Build Gradle réussi ; 87,6 s |
| APK / AAPT | Paquet, version, SDK, taille, SHA-256 | `be.mapfollow.mapfollow`, `0.4.0` code 4 ; minSdk 26, compile/target 36 ; 168 874 586 octets ; `29435805FC9A5E790E14FD8BF39E4F602DBE873B9DF1AB124912BA7ABD69B4D3` |
| Installation S23 Ultra | `adb install -r`, démarrage et Historique | Succès sans désinstallation/effacement ; courses précédentes visibles ; profil Précision sélectionné |
| Essai Android court | Run libre Diagnostic, service, arrêt du processus, clôture, bilan et dialogues | Service/notification confirmés ; récupération explicite ; batterie 100 %→100 %, recharge/interruption/courbe ; export annulé, confirmation de suppression et annulation testées ; réglage final Normal |
| Rejeu de l'ancien GPX | Traitement en mémoire, résultats agrégés uniquement | 7 500,0 → 7 524,5 m ; 7 rejets ; aucune amélioration réelle démontrée |
| Nouvelle comparaison Garmin | Nouvelle sortie, Précision, écran verrouillé avec YouTube Music | À réaliser ; cible <3 % non validée |

Les nouveaux tests couvrent bruit, arrêt, sauts, virage, demi-tour, pause/perte/reprise, chemins parallèles, connexions OSM et ponts, ambiguïtés, cache/réseau, batterie normale/diagnostic, récupération, exports, migration v1, confirmation et rollback de suppression. Les avertissements de dépendances et de tuiles OSM de test ne constituent pas des échecs.

Le build émet des avertissements non bloquants d'accès natif JDK, d'usage futur du Kotlin Gradle Plugin par `flutter_tts` et de versions XML du SDK. La lecture complète de la base privée du téléphone pour comparer ses points a été refusée par le contrôle automatique ; aucune base ni coordonnée n'a été transférée. La conservation sur appareil est vérifiée via l'historique, et la migration exacte des anciennes traces est couverte par SQLite synthétique.

Le contrôle a aussi refusé la lecture des journaux privés et demandé une autorisation explicite pour nettoyer le Run d'essai. Cette autorisation a été obtenue ; l'essai ne figure plus dans l'historique. Voir [les étapes et limites du contrôle physique](field-validation.md) : écran OFF observé ponctuellement, suivi prolongé verrouillé avec YouTube Music et précision Garmin encore à valider. Le téléphone en charge ne permet pas de mesurer une consommation représentative.

## Contrôle précédent — `0.3.0+3`

Analyse, tests, formatage, compilation Gradle et métadonnées AAPT de `0.3.0+3` sont confirmés ci-dessous. Aucun de ces contrôles ne remplace un essai manuel.

| Contrôle | Commande / méthode | Résultat |
|---|---|---|
| Analyse Dart | `scripts/flutter.ps1 analyze` | Aucun problème détecté; 22,3 s |
| Suite automatisée complète | `scripts/flutter.ps1 test` | 99 tests réussis; 13 s |
| Formatage Dart | `dart format --output=none --set-exit-if-changed lib test` | 44 fichiers examinés; 0 modifié; 0,35 s |
| Build Android debug | `scripts/flutter.ps1 build apk --debug` | Build Gradle réussi; 20,1 s |
| APK et métadonnées | `build/app/outputs/flutter-apk/app-debug.apk`; vérification AAPT | Paquet `be.mapfollow.mapfollow`, version `0.3.0` (code 3), minSdk 26, compile/target SDK 36; taille 195 516 366 octets; SHA-256 `024B8B721E11D56CE6E1626EB21EE11B1D9277861CA63B316E5EF0A60A05DF79` |
| Essais manuels Android | Émulateur et appareil physique | Non réalisés; aucun appareil n’était connecté |

Les essais profil GPS de 30 minutes, GPS écran verrouillé, récupération après arrêt, diagnostics GNSS sur Android et partage GPX réel restent à faire. Les essais Samsung Galaxy S23 Ultra et Galaxy S21 5G ne sont pas confirmés. Le build a émis des avertissements non bloquants sur l’accès natif JDK et la migration future du Kotlin Gradle Plugin de `flutter_tts`; l’APK debug a néanmoins été construit et vérifié.

## Contrôle précédent — `0.2.0+2` (6 octobre 2026)

| Contrôle | Commande / méthode | Résultat |
|---|---|---|
| Analyse Dart | `scripts/flutter.ps1 analyze` | Aucun problème détecté; 16,5 s |
| Suite automatisée complète | `scripts/flutter.ps1 test` | Tous les tests réussis : 52; 11 s |
| Formatage Dart | `dart format --output=none --set-exit-if-changed lib test` | 29 fichiers examinés; 0 modifié; 0,15 s |
| Build Android debug | `scripts/flutter.ps1 build apk --debug` | Build finale réussie en 19,7 s après les derniers ajustements |
| APK et métadonnées | `build/app/outputs/flutter-apk/app-debug.apk`; vérification AAPT | Paquet `be.mapfollow.mapfollow`, version `0.2.0` (code 2), minSdk 26, compile/target SDK 36; taille 168 754 326 octets; SHA-256 `64A72E305F62552F11301A2390EC7135B487068B0E4316207675C5CC9D66CC08` |
| Appareils ADB | `adb devices` | Commande autorisée, aucun appareil connecté; aucun essai manuel sur émulateur ou appareil physique |
| Logs de développement | `logs/debut.txt` | Présent localement et ignoré par Git |

Cette version incluait le Run libre. Les 52 tests, l’analyse, le formatage et le build sont confirmés uniquement pour `0.2.0+2`. Cette build comprenait le centrage de carte pour un point unique et les contrôles de fraîcheur GPS à la milliseconde. Aucun appareil ou émulateur n’était connecté pour un essai manuel.

## Résultats historiques — 4 octobre 2026

Ces contrôles portent sur le code antérieur au Run libre. Ils décrivent le point de départ et ne valident pas la version actuelle.

| Contrôle | Commande / méthode | Résultat |
|---|---|---|
| Analyse Dart | `scripts/flutter.ps1 analyze` | Aucun problème détecté; 34,2 s |
| Suite automatisée complète | `scripts/flutter.ps1 test` | Tous les tests réussis : 34 |
| Formatage Dart | `dart format --output=none --set-exit-if-changed lib test` | 21 fichiers examinés, 0 modifié |
| Validation de la skill | `quick_validate.py` avec Python embarqué et PyYAML local | Skill MapFollow valide |
| Build Android debug | `scripts/flutter.ps1 build apk --debug` | Premier build : environ 1 074,2 s avec installation initiale du SDK. Build final après corrections : réussi en 15,9 s. |
| APK et métadonnées | `build/app/outputs/flutter-apk/app-debug.apk`; vérification AAPT et signature | Paquet `be.mapfollow.mapfollow`, version `0.1.0` (code 1), minSdk 26, compile/target SDK 36; signature v2 valide; taille 160,9 MiB; SHA-256 `811B19E94A06E9A5EEEBD6A54A2D710EB2D31228F2D81D0380F8E0A9537630FB` |
| Installation ADB | `adb devices` | Aucun appareil listé; installation et essais physiques en attente |
| Essai terrain d’une heure | Procédure [field-validation.md](field-validation.md) | Non réalisé / non confirmé |

Les 34 tests, l’analyse, le formatage et le build du tableau ci-dessus concernaient `0.1.0`, le code du 4 octobre. Aucun résultat terrain sur Samsung Galaxy S23 Ultra (cible principale) ou Galaxy S21 5G (cible secondaire) n’est confirmé. Les essais Bluetooth et le squelette iOS n’ont pas été testés. Une compilation ne constitue pas un essai de l’interface sur appareil.

## Remarque historique du build du 4 octobre

Le build du 4 octobre n’avait signalé aucune erreur de code. Un avertissement d’une dépendance tierce indiquait que `flutter_tts` pourrait devoir mettre à jour sa configuration Kotlin Gradle Plugin lors d’une évolution future; il n’avait pas empêché cette compilation. Aucun avertissement similaire n’est consigné ici pour le build du 6 octobre.

Le premier build a installé plusieurs composants Android et duré longtemps. Les SDK 35 et 36, Build Tools 36, NDK 28.2.13676358 et CMake 3.22.1 sont présents dans `.tools/android-sdk`. Pour `build` et `run`, le wrapper génère `.tools/debug.keystore` avec `keytool` si la clé locale manque; Git ignore ce fichier. Si `.tools/jdk` n’existe pas, `JAVA_HOME` doit désigner Java 17 ou le JBR d’Android Studio. Le wrapper ne modifie pas le PATH Windows global. Cette clé Android de debug ne sert pas à une publication.
