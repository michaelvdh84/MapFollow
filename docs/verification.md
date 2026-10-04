# Journal de vérification

Résultats finaux communiqués pour le 4 octobre 2026.

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

L’APK de débogage final se trouve dans `build/app/outputs/flutter-apk/app-debug.apk`. La suite complète de 34 tests, l’analyse, le formatage et le build final sont confirmés. Aucun résultat terrain sur Samsung Galaxy S23 Ultra (cible principale) ou Galaxy S21 5G (cible secondaire) n’est confirmé. Les essais Bluetooth et le squelette iOS n’ont pas été testés. La compilation ne constitue pas un essai de l’interface sur appareil; seules les prévisualisations de widgets Bibliothèque, Réglages et Historique ont été consultées.

## Avertissement restant

Le build n’a signalé aucune erreur de code. Un avertissement d’une dépendance tierce indique que `flutter_tts` pourrait devoir mettre à jour sa configuration Kotlin Gradle Plugin lors d’une évolution future; il n’a pas empêché la compilation.

Le premier build a installé plusieurs composants Android et duré longtemps. Les SDK 35 et 36, Build Tools 36, NDK 28.2.13676358 et CMake 3.22.1 sont présents dans `.tools/android-sdk`. Pour `build` et `run`, le wrapper génère `.tools/debug.keystore` avec `keytool` si la clé locale manque; Git ignore ce fichier. Si `.tools/jdk` n’existe pas, `JAVA_HOME` doit désigner Java 17 ou le JBR d’Android Studio. Le wrapper ne modifie pas le PATH Windows global. Cette clé Android de debug ne sert pas à une publication.
