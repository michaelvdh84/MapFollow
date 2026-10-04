# Installer MapFollow sur un nouveau PC Windows

Ce guide part d’un PC sans environnement de développement mobile. À la fin, vous pourrez modifier le code dans VS Code, exécuter les tests, lancer l’application Android dans un émulateur ou sur votre Samsung et produire un APK.

Suivez les étapes dans l’ordre. Les commandes se saisissent dans **PowerShell**, depuis la racine du projet sauf indication contraire. Les dossiers `.tools/`, les caches et l’APK ne sont pas présents dans le dépôt GitHub : chaque nouveau PC doit installer ses outils.

## 1. Prévoir le matériel et les téléchargements

Pour ce parcours, utilisez Windows 11 64 bits sur un PC Intel/AMD avec virtualisation disponible. Prévoyez un SSD, au moins 16 Go de RAM pour Android Studio avec l’émulateur, idéalement 32 Go, et environ 40 Go libres pour l’ensemble des outils, images et caches. Les besoins exacts dépendent des téléchargements; consultez les [prérequis officiels Android Studio](https://developer.android.com/studio/install).

Si le PC supporte mal l’émulateur, vous pourrez développer avec votre Samsung connecté par USB. La version Windows native et la version navigateur de MapFollow ne sont pas implémentées. La compilation iOS nécessitera ultérieurement un Mac et Xcode.

Les premières installations et compilations nécessitent Internet. Prévoyez aussi un câble USB de données pour le téléphone.

## 2. Installer Git, VS Code et Android Studio

Téléchargez les logiciels depuis leurs sites officiels :

| Outil | Téléchargement | Rôle |
|---|---|---|
| Git pour Windows | [Git](https://git-scm.com/download/win) | Récupérer le projet et suivre les modifications |
| Visual Studio Code | [VS Code](https://code.visualstudio.com/Download) | Modifier et déboguer le code |
| Android Studio, version stable | [Android Studio](https://developer.android.com/studio) | Installer le SDK et gérer l’émulateur |
| Eclipse Temurin, **JDK 17**, Windows x64, HotSpot | [Adoptium](https://adoptium.net/temurin/releases/?version=17) | Compiler les composants Android |

Installez Git avec son accès depuis la ligne de commande. Installez VS Code; l’option d’ajout au PATH permet d’utiliser `code .`. Installez Android Studio et laissez-le utiliser son Java intégré pour son propre fonctionnement. Le **JDK 17 de MapFollow** sera configuré séparément à l’étape 5.

Vous n’avez pas besoin d’installer Dart séparément : Flutter l’inclut. Visual Studio, Docker, Node.js et un compte développeur Play Store ne sont pas nécessaires pour ce POC Android.

Fermez puis rouvrez PowerShell après l’installation de Git. Vérifiez :

```powershell
git --version
```

Résultat attendu : une version de Git. Si la commande n’est pas reconnue, vérifiez son installation et rouvrez le terminal.

## 3. Récupérer le projet

Choisissez un dossier court, hors OneDrive, par exemple `C:\Dev`. Si ce dossier existe déjà, réutilisez-le :

```powershell
New-Item -ItemType Directory -Force C:\Dev | Out-Null
Set-Location C:\Dev
git clone https://github.com/michaelvdh84/MapFollow.git
Set-Location MapFollow
New-Item -ItemType Directory -Force .tools | Out-Null
```

Résultat attendu : `C:\Dev\MapFollow` contient notamment `pubspec.yaml`, `lib/`, `android/` et `scripts/`. Si vous avez déjà cloné le projet, ouvrez ce dossier existant au lieu de relancer `git clone`.

## 4. Installer la version Flutter du projet

Depuis `C:\Dev\MapFollow` :

```powershell
git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git .tools/flutter
.\scripts\flutter.ps1 --version
```

La version retenue est **Flutter 3.47.6**, avec **Dart 3.13.5**. Le premier lancement télécharge les composants Flutter nécessaires. Le message Git signalant un état « detached HEAD » pour le tag Flutter est normal : il concerne la copie des outils, pas le dépôt MapFollow.

Autre méthode : téléchargez cette version depuis l’[archive officielle Flutter](https://docs.flutter.dev/install/archive), puis extrayez-la pour obtenir exactement `.tools\flutter\bin\flutter.bat`. Ne créez pas une double arborescence `.tools\flutter\flutter`.

Le script `scripts/flutter.ps1` configure les chemins et caches locaux pour chaque commande. Vous n’avez pas besoin d’ajouter Flutter au PATH Windows global. Utilisez ce script pour les commandes indiquées dans le guide.

## 5. Installer Java 17 dans le projet

Sur Adoptium, choisissez **JDK 17 / Windows / x64 / HotSpot**, puis l’archive **ZIP**. Vérifiez le téléchargement selon les [instructions Adoptium](https://adoptium.net/installation/archives), extrayez-le et placez le contenu du dossier JDK dans `.tools\jdk`.

L’arborescence attendue est :

```text
MapFollow/
  .tools/
    flutter/bin/flutter.bat
    jdk/bin/java.exe
    jdk/bin/keytool.exe
```

Ne mettez pas le JDK un niveau trop bas, par exemple `.tools\jdk\jdk-17...\bin`. Choisissez bien un **JDK**, car le programme `keytool` est utilisé pour la signature de développement.

Vérifiez depuis la racine :

```powershell
.\.tools\jdk\bin\java.exe -version
Test-Path .\.tools\jdk\bin\keytool.exe
```

Résultat attendu : Java **17** et `True`. Le wrapper configure `JAVA_HOME` vers cette copie pour ses commandes. Aucun changement du Java système n’est nécessaire.

## 6. Installer le SDK Android

Dans Android Studio, ouvrez **SDK Manager** depuis **More Actions** sur l’accueil, ou **Tools > SDK Manager** dans un projet ouvert.

Définissez **Android SDK Location** sur le chemin absolu `C:\Dev\MapFollow\.tools\android-sdk`. Adaptez ce chemin si vous avez choisi un autre dossier. L’assistant peut déjà avoir installé un SDK ailleurs : choisissez ici le dossier qui sera utilisé par MapFollow et installez-y les composants nécessaires.

Dans **SDK Platforms**, installez les plateformes **API 35 et API 36**. Dans **SDK Tools**, activez **Show Package Details** si nécessaire, puis installez :

| Composant | Version / sélection |
|---|---|
| Android SDK Build-Tools | **36.0.0** |
| Android SDK Platform-Tools | Version stable proposée |
| Android SDK Command-line Tools | Version stable proposée |
| Android Emulator | Version stable proposée |
| NDK (Side by side) | **28.2.13676358** |
| CMake | **3.22.1** |

Cliquez **Apply**, examinez les licences proposées et acceptez celles nécessaires pour installer les composants. Les téléchargements peuvent être volumineux. Vérifiez ensuite :

```powershell
Test-Path .\.tools\android-sdk\platform-tools\adb.exe
Test-Path .\.tools\android-sdk\emulator\emulator.exe
```

Les deux commandes doivent répondre `True`.

Configurez Flutter pour qu’il retrouve les mêmes outils, y compris lorsqu’il est lancé par VS Code :

```powershell
$mapFollowRoot = (Get-Location).Path
$mapFollowSdk = Join-Path $mapFollowRoot '.tools\android-sdk'
$mapFollowJdk = Join-Path $mapFollowRoot '.tools\jdk'
.\scripts\flutter.ps1 config "--android-sdk=$mapFollowSdk" "--jdk-dir=$mapFollowJdk"
.\scripts\flutter.ps1 doctor -v
```

La commande `config` enregistre ces chemins dans les préférences Flutter de votre compte Windows; elle peut donc changer les outils par défaut utilisés par vos autres projets Flutter. Elle ne change pas le PATH Windows. À répéter si vous déplacez ce dossier.

Résultat attendu : **Android toolchain** est disponible et utilise les chemins choisis. Un avertissement de PATH Flutter/Dart est possible avec cette installation locale. La détection de Visual Studio concerne la compilation Windows, hors périmètre. Vérifiez en priorité les erreurs de la partie Android et les chemins Java/SDK.

Si les licences Android ne sont pas toutes reconnues :

```powershell
.\scripts\flutter.ps1 doctor --android-licenses
```

Lisez et acceptez les licences requises. Pour plus de détails, consultez [l’installation Android Flutter](https://docs.flutter.dev/platform-integration/android/setup).

## 7. Vérifier le projet et construire une première fois

```powershell
.\scripts\flutter.ps1 pub get
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 build apk --debug
```

Exécutez les commandes une par une et corrigez une erreur avant la suivante. Résultats attendus : dépendances récupérées, analyse sans erreur, tests réussis et APK sous `build\app\outputs\flutter-apk\app-debug.apk`. Le [journal de vérification](verification.md) rapporte les résultats obtenus sur le PC initial; cette installation sur votre nouveau PC reste à vérifier.

La première compilation télécharge également Gradle et des dépendances Android; elle peut être longue. Flutter recrée les scripts Gradle générés absents du clone et prépare `android/local.properties`. Le wrapper crée `.tools/debug.keystore`. Ces fichiers locaux restent exclus de Git.

## 8. Configurer VS Code

Ouvrez **le dossier MapFollow entier**, pas uniquement `lib/` ou `android/` :

```powershell
code .
```

Si `code` n’est pas disponible, utilisez **File > Open Folder** dans VS Code et choisissez `C:\Dev\MapFollow`.

Installez les extensions suggérées par le projet : **Flutter** (`Dart-Code.flutter`, qui fournit aussi Dart) et **PowerShell** (`ms-vscode.powershell`). Acceptez la confiance du dossier si vous reconnaissez le projet cloné.

Le fichier `.vscode/settings.json` pointe déjà sur `.tools/flutter`. Les dossiers d’outils et de build sont masqués dans l’explorateur VS Code pour garder le code lisible; ils existent toujours sur disque. Ouvrez **Terminal > New Terminal** et choisissez PowerShell.

Résultat attendu : les fichiers `.dart` sont reconnus, l’analyse et l’autocomplétion fonctionnent. Consultez [Flutter dans VS Code](https://docs.flutter.dev/tools/vs-code) pour l’utilisation du débogueur.

## 9. Lancer l’émulateur et simuler

Dans Android Studio **Device Manager**, créez un téléphone Pixel avec une image **Google Play, API 36, x86_64**, puis démarrez-le. L’installation du moteur vocal et des données françaises se fait **dans Android**, pas dans Windows.

Les étapes détaillées sont dans [le guide de démarrage](startup-guide.md#2-créer-le-téléphone-virtuel-sur-pc). Vérifiez les appareils, puis lancez l’application :

```powershell
.\scripts\flutter.ps1 emulators
.\scripts\flutter.ps1 devices
.\scripts\flutter.ps1 run -d emulator-5554
```

Remplacez `emulator-5554` par l’identifiant Android réellement affiché. Gardez le terminal ouvert. Dans MapFollow, préparez la voix française, puis utilisez **Parcours > Charger la démo synthétique > Course > Simuler ce parcours**. Voir [le scénario complet](startup-guide.md#4-faire-la-première-simulation-sans-courir).

Le PC exécute l’application Android dans un téléphone virtuel. La simulation intégrée suit automatiquement le tracé; elle ne reproduit pas les restrictions Samsung ni les problèmes GPS réels.

## 10. Faire votre première modification

Pendant que `flutter.ps1 run` fonctionne et que MapFollow est affiché :

1. Ouvrez `lib/presentation/app.dart` dans VS Code.
2. Cherchez `title: const Text('MapFollow')` dans l’`AppBar`.
3. Remplacez ce texte par `title: const Text('MapFollow — mon test')`.
4. Enregistrez avec **Ctrl+S**.
5. Dans le terminal où `flutter run` fonctionne, appuyez sur **r**.

Résultat attendu : le titre change à l’écran sans réinstaller l’application. C’est le **hot reload**. Rétablissez ensuite le titre initial et refaites `r`.

Dans ce terminal : **r** recharge les changements Dart, **R** redémarre l’application Flutter, **q** termine la session. Le hot reload conserve l’état et ne réexécute pas `main()` ni `initState()`; certains changements nécessitent donc un redémarrage. Une modification Kotlin, du manifeste Android ou des dépendances natives nécessite d’arrêter puis relancer la compilation. Voir [la documentation du hot reload](https://docs.flutter.dev/tools/hot-reload).

Pour utiliser des points d’arrêt, quittez d’abord la session du terminal avec `q`, sélectionnez l’appareil Android dans la barre d’état de VS Code, puis lancez **Run > Start Debugging / F5**. Utilisez la barre du débogueur pour recharger et arrêter. La première compilation via le wrapper de l’étape 7 doit avoir préparé la clé de développement; le lancement F5 direct ne passe pas par ce wrapper.

## 11. Savoir où modifier le code

| Besoin | Dossier principal |
|---|---|
| Écrans, boutons, textes | `lib/presentation/` |
| Progression, virages, calculs GPS | `lib/domain/` |
| GPS, voix, fichiers, SQLite | `lib/data/` |
| Démarrage/pause/reprise et coordination | `lib/application/` |
| Focus audio et permissions natives | `android/app/src/main/` |
| Vérification automatique | `test/` |
| Guides et état du POC | `docs/`, `PLAN.md`, `STRUCTURE.md` |

Commencez par [STRUCTURE.md](../STRUCTURE.md) et respectez [AGENTS.md](../AGENTS.md). Utilisez les fichiers synthétiques dans `assets/` et `test/fixtures/`; gardez vos parcours personnels hors du dépôt.

## 12. Valider après une modification

Depuis la racine, dans un autre terminal :

```powershell
.\.tools\flutter\bin\dart.bat format lib test
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
```

Avant d’essayer un nouvel APK :

```powershell
.\scripts\flutter.ps1 build apk --debug
```

Pour contrôler le format sans modifier les fichiers, utilisez `.\.tools\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test`. Les tests automatiques complètent les essais interactifs; ils ne valident pas l’autonomie ou le guidage écran verrouillé sur Samsung.

Les sources et le verrou de dépendances `pubspec.lock` se versionnent. Les outils, caches, clés et données personnelles restent exclus. Consultez `git status --short` avant un commit; n’ajoutez pas de token ou de fichier GPS personnel.

## 13. Lancer sur votre Samsung

Activez le débogage USB, branchez le téléphone et acceptez son autorisation. Puis :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe devices
.\scripts\flutter.ps1 run -d SAMSUNG_ID
```

Remplacez `SAMSUNG_ID` par l’identifiant du S23 Ultra ou S21 5G. Le [guide de démarrage Android](startup-guide.md#5-installer-sur-votre-s23-ultra-ou-s21-5g) décrit aussi l’installation manuelle de l’APK. Le téléphone peut remplacer l’émulateur pour toute la boucle modification/test.

Chaque PC génère sa propre clé debug. Un APK compilé sur le nouveau PC peut donc être refusé comme mise à jour d’un APK signé sur l’ancien PC. Pour conserver les données de l’application lors d’une mise à jour, utilisez la même clé debug copiée entre vos PC par un moyen privé; ne la mettez pas dans Git. Une désinstallation supprime les données locales : exportez auparavant les courses à conserver.

## 14. Dépannage de l’installation

| Problème | Vérification / action |
|---|---|
| Flutter absent | Vérifiez `.tools\flutter\bin\flutter.bat` et l’absence de double dossier `flutter` |
| Java ou `keytool` absent | Vérifiez `.tools\jdk\bin`, la version 17, puis les chemins de `doctor -v` |
| SDK absent ou mauvais chemin | Vérifiez Android Studio et répétez `config` avec les chemins absolus de l’étape 6 |
| Licence ou composant manquant | Retournez dans SDK Manager, puis `doctor --android-licenses` |
| Émulateur absent de `devices` | Démarrez-le dans Device Manager et vérifiez le SDK utilisé |
| Émulateur lent ou impossible à lancer | Consultez [l’accélération Android](https://developer.android.com/studio/run/emulator-acceleration); utilisez le Samsung si nécessaire |
| Erreur de téléchargement réseau | Vérifiez la connexion et le proxy du PC; relancez la commande en échec |
| Voix française absente | Téléchargez les données vocales dans Android et utilisez le test vocal MapFollow |
| Analyse VS Code indisponible | Ouvrez la racine du projet, vérifiez l’extension Flutter et `.vscode/settings.json` |

Si PowerShell refuse d’exécuter les fichiers `.ps1`, consultez `Get-ExecutionPolicy -List`. Sur votre PC personnel, pour autoriser les scripts locaux uniquement dans la fenêtre courante, vous pouvez utiliser `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`, puis relancer la commande. Sur un PC géré, respectez la politique de votre organisation; une stratégie imposée peut empêcher ce changement.

## Checklist de fin

- [ ] Git et VS Code installés.
- [ ] Flutter 3.47.6 et JDK 17 dans `.tools/`.
- [ ] SDK Android configuré, composants et licences disponibles.
- [ ] `doctor -v` confirme l’environnement Android.
- [ ] Dépendances, analyse, tests et construction APK réussis.
- [ ] Émulateur ou Samsung détecté par `devices`.
- [ ] Voix française locale audible dans MapFollow.
- [ ] Démo simulée puis visible dans l’historique.
- [ ] Une modification Dart est visible après hot reload.

Guide préparé le 4 octobre 2026, à partir du code et des documents officiels. Le tag Flutter indiqué et les options de configuration ont été vérifiés. Une installation complète sur un second PC et les essais interactifs sur émulateur/Samsung restent à effectuer; aucun résultat de ces essais n’est présumé.
