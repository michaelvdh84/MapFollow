# Journal de vérification

## Contrôles de la version actuelle — `0.5.2+7` (12 octobre 2026)

Branche `codex/android-location-freshness`. L'[audit Android](android-location-audit.md) distingue recommandations déjà présentes, corrections natives et expérimentations différées. Les modifications locales de 0.5.1 sont conservées.

| Contrôle | Méthode | Résultat |
|---|---|---|
| Formatage final | `dart format --output=none --set-exit-if-changed lib test packages/geolocator_android/lib` | 68 fichiers ; 0 modifié |
| Analyse finale | `scripts/flutter.ps1 analyze` | Aucun problème ; 59,8 s |
| Suite Flutter finale | `scripts/flutter.ps1 test` | 169 tests réussis ; 39 s |
| Suite Java du plugin | `android/gradlew.bat :geolocator_android:testDebugUnitTest --console=plain`, SDK et JDK locaux | 16 tests réussis, 0 échec ; Gradle 23 s |
| Build debug final | `scripts/flutter.ps1 build apk --debug` | Réussi ; 168,9 s |
| APK final / AAPT | Paquet, SDK, taille, SHA-256 | `be.mapfollow.mapfollow`, `0.5.2` code 7 ; minSdk 26, compile/target 36 ; 192 294 482 octets ; `543489785CCA41E2B840AD2674CD3F6795E7F347A75B7D12109F015F176D42B2` |
| S23 Ultra, Android 16 | Build de validation via Flutter puis APK final via `adb install -r` | Succès ; métadonnées finales 0.5.2 code 7 ; aucune désinstallation ni suppression des courses |
| Flutter MCP | DTD S23, hot reload après dernières modifications Dart, erreurs d'exécution | Rechargement réussi ; aucune erreur remontée pendant la connexion ; session de debug terminée après remplacement de l'APK |
| S21 | Disponibilité ADB au démarrage de cet audit | Non connecté ; version précédemment installée 0.5.1+6 conservée |
| Nouveau suivi GPS réel | Réception, démarrage, écran verrouillé, batterie, comparaison | Pas de Run créé ; aucun gain terrain mesuré pour 0.5.2 |
| Diff | `git -c core.safecrlf=false diff --check` | Aucun défaut |

Les nouveaux tests couvrent les requêtes Fused à 250/500/1 000/10 000 ms, les distances des profils, l'absence de première position en cache et de regroupement, chaque élément d'un lot dans son ordre, les lots vides, le mapping natif monotone, les données anciennes, les doublons/désordres, les intervalles et coupures du filtre et les cadences exportées sans franchir un reboot. Les tests de 0,5 s Developer, récupération et confidentialité des exports restent dans la suite.

Le premier test Java attendait un délai effectif de zéro ; Google le normalise à l'intervalle et le regroupement reste désactivé. Le test final vérifie ces deux propriétés. Les avertissements Java source/target 8 du plugin, JDK, XML SDK et migration Kotlin de `flutter_tts` restent non bloquants. Une vérification UI physique finale et les essais de réception/écran éteint restent à faire ; installation et hot reload ne les remplacent pas.

## Contrôles précédents — `0.5.1+6` (12 octobre 2026)

| Contrôle | Méthode | Résultat |
|---|---|---|
| Formatage | `dart format --output=none --set-exit-if-changed lib test` | 63 fichiers ; 0 modifié |
| Analyse | `scripts/flutter.ps1 analyze --no-pub` | Aucun problème ; 70,4 s |
| Suite complète finale | `scripts/flutter.ps1 test --no-pub` | 163 tests réussis ; 32 s |
| Build debug final | `scripts/flutter.ps1 build apk --debug --no-pub` | Gradle réussi ; 100,5 s |
| APK final / AAPT | Paquet, version, SDK, taille, SHA-256 | `be.mapfollow.mapfollow`, `0.5.1` code 6 ; minSdk 26, compile/target 36 ; 92 202 960 octets ; `093D66B72A11614DFE30215DA9C08EC6EB71AFA304C93D842B3ACDA0BFFB8B88` |
| Rejeu S21, règles d'enregistrement incluses | Diagnostics bruts, calcul en mémoire | 5 015,8 m communs / 5 030 m compteur Garmin (−0,28 %) ; aucun rejet ; [détails et limites](comparison-s21-2026-10-12.md) |
| Version dans l'interface | Pont Android et test widget avec version 9.8.7+42 | Valeur fixe 0.3.0 supprimée ; affichage dynamique et retour de page testés |
| Flutter MCP | S23 puis S21, hot reload et erreurs d'exécution | Rechargements réussis ; aucune erreur remontée pendant les connexions |
| S23 | APK final, `adb install -r` et métadonnées | Installation réussie après reconnexion ; version 0.5.1 code 6 ; affichage POC physique à confirmer, écran verrouillé lors du contrôle |
| S21 | Même APK final, `adb install -r` et métadonnées | Installation réussie ; version 0.5.1 code 6 ; affichage POC physique à confirmer, MapFollow n'est pas resté au premier plan |
| Nouvelle sortie terrain | Version corrigée 0.5.1+6 | Non réalisée ; cible ≤2 % non validée sur un nouvel enregistrement |

Les nouveaux tests couvrent courbes et angles à précision 3/6 m sur quatre cadences, dérive lente, axes et orientation, champs de mouvement absents puis restaurés, seuil de vitesse faible et identification des versions réellement utilisées dans les diagnostics. Tous les anciens tests restent dans la suite. Le filtre ne fournit pas une garantie universelle ≤2 % : une dérive lente synthétique reste ambiguë. Les positions historiques ne sont pas recalculées.

La lecture de version native est limitée à Android ; les tests utilisent un lecteur injecté afin de ne pas attendre un appel Android dans une horloge simulée. Les scripts temporaires de rejeu ont été retirés avant l'analyse finale ; seuls les agrégats sont consignés. Les avertissements JDK, XML SDK et migration Kotlin de `flutter_tts` restent non bloquants.

## Contrôles précédents — `0.5.0+5` (11 octobre 2026)

| Contrôle | Commande / méthode | Résultat |
|---|---|---|
| Analyse Dart | `scripts/flutter.ps1 analyze` | Aucun problème ; 60,3 s |
| Suite complète | `scripts/flutter.ps1 test` | 157 tests réussis ; 65 s |
| Formatage | `dart format --output=none --set-exit-if-changed lib test` | 62 fichiers ; 0 modifié |
| Build Android debug livré | `scripts/flutter.ps1 run --no-pub -d <S23>` | Build Gradle réussi ; 57,8 s |
| APK / AAPT | Paquet, version, SDK, taille, SHA-256 | `be.mapfollow.mapfollow`, `0.5.0` code 5 ; minSdk 26, compile/target 36 ; 119 020 850 octets ; `661593E3B2C586BF1F450F9DF4FC7C202CF7D1673672455365383A29BDB6C15F` |
| Flutter MCP | Reconnexion, hot reload, erreurs d'exécution | Rechargement réussi après les dernières modifications ; aucune erreur remontée |
| S23 Ultra | Installation sans effacement, Developer, redémarrage, export | 0,5 s conservé après démarrage à froid ; historique présent ; logs d'une course Normal ouvrent la feuille de partage Android, annulée sans envoi ; mode final Normal |
| S21 5G | Même APK, `adb install -r`, démarrage et version du paquet | Succès ; `SM-G991B`, Android 15 ; version `0.5.0` code 5 ; quatre onglets visibles ; aucun Run lancé ni permission accordée automatiquement |
| Nouvelle précision terrain | Sortie S21 du 12 octobre, demande 0,5 s, Diagnostic | +3,54 % commun face au compteur Garmin ; cible ≤2 % non atteinte ; [analyse des 140 m ajoutés par le filtre](comparison-s21-2026-10-12.md) |

Les tests supplémentaires couvrent l'intervalle personnalisé et sa récupération, les indicateurs de présence Android, les exports avec positions exclues par défaut et consentement explicite, ainsi que le comportement du filtre à 1 s, 0,5 s et 0,25 s. Sur une ligne droite synthétique bruitée, la distance reste à moins de 2 % de la référence ; les courbes, virages, arrêts et incertitudes de vitesse ont leurs propres critères. Ces résultats ne prouvent pas la précision sur une course réelle.

Le dernier GPX utilisateur, enregistré avec la version précédente, donne 7 270,7 m au total et 7 223,9 m sur les instants communs à Garmin. Face aux 7 020 m affichés par la montre, l'écart commun est +2,91 %. Le GPX Garmin lui-même mesure 6 956,9 m ; il faut distinguer sa longueur géométrique du compteur de la montre. Les calculs sont réalisés en mémoire et seuls ces agrégats sont consignés.

La feuille Android d'export Normal est vérifiée sans envoi. L'export Diagnostic avec positions fourni le 12 octobre est cohérent avec les 3 129 points du GPX S21 ; le suivi prolongé écran verrouillé et les conditions audio restent à confirmer. Aucun Run d'essai supplémentaire n'a été créé ni supprimé. Les avertissements de build JDK, Kotlin Gradle Plugin et XML SDK restent non bloquants.

## Contrôles précédents — `0.4.0+4` (7 octobre 2026)

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
