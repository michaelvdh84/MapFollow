# Android : installation, permissions et dépannage

Pour effectuer votre premier essai, commencez par [le guide de démarrage et simulation sur PC / Samsung](startup-guide.md). Ce document détaille les prérequis et le fonctionnement Android.

## Installer les outils

Le dépôt contient des copies locales de Flutter, Android SDK et Java sous `.tools/`. Le script `scripts/flutter.ps1` prépare les chemins et caches locaux pour chaque commande. `.tools/` est un dossier d’outils et n’est pas destiné à être versionné.

### Préparer un nouveau PC

Suivez [le guide complet d’installation et de développement sur un nouveau PC Windows](new-pc-setup.md). Il définit les chemins `.tools/flutter`, `.tools/jdk` (JDK 17) et `.tools/android-sdk`, puis explique la configuration Flutter et VS Code, les validations et la première modification. Le Java intégré d’Android Studio sert à l’IDE; il n’est pas supposé être un JDK 17 pour le projet.

Pour débuter, Android Studio est la méthode la plus simple pour installer/mettre à jour les plateformes Android, outils de compilation, NDK et licences : ouvrez **Tools > SDK Manager**, sélectionnez les composants demandés si nécessaire, puis acceptez les licences dans l’interface. Le SDK configuré pour le projet cible Android API 36, compile/target 36, minimum Android 26, Build Tools 36.0.0 et NDK 28.2.13676358. Java est Temurin 17.0.20.1, Android Gradle Plugin 9.1 et Kotlin 2.4.

Pour les personnes à l’aise avec la ligne de commande, le SDK Manager local est aussi disponible. Depuis la racine du dépôt, la commande fournie pour installer les paquets ciblés est :

```powershell
.\.tools\android-sdk\cmdline-tools\latest\bin\android.exe --no-metrics --sdk=.tools\android-sdk sdk install platforms/android-36 build-tools/36.0.0 ndk/28.2.13676358
```

Le wrapper peut aussi afficher son diagnostic :

```powershell
.\scripts\flutter.ps1 doctor -v
```

Les versions Flutter 3.47.6 et Dart 3.13.5 sont fournies localement. Autres commandes :

```powershell
.\scripts\flutter.ps1 pub get
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 build apk --debug
.\scripts\flutter.ps1 run -d DEVICE_ID
```

Pour répertorier les appareils Android connectés :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe devices
```

Déverrouillez le téléphone, activez **Options pour les développeurs > Débogage USB**, branchez-le et acceptez le dialogue d’autorisation. Lancez avec :

```powershell
.\scripts\flutter.ps1 run -d DEVICE_ID
```

Pour compiler et installer manuellement la version debug :

```powershell
.\scripts\flutter.ps1 build apk --debug
.\.tools\android-sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
```

Remplacez `DEVICE_ID` par la valeur montrée par `adb devices`. La version debug sert aux essais seulement.

## Position et écran verrouillé

L’application utilise un service de premier plan de localisation lorsqu’une course est suivie. Android demande l’autorisation de localisation pendant que l’application est utilisée; accordez-la pour démarrer le suivi. Android affiche une notification pendant le service. L’écran verrouillé doit être testé explicitement : autorisation accordée ne garantit pas que chaque fabricant ou réglage de batterie laissera le service fonctionner sans interruption.

Si le suivi s’arrête, déverrouillez le téléphone, vérifiez l’autorisation de localisation et les réglages batterie de MapFollow, puis revenez à l’application. Une terminaison forcée ou un arrêt système peut créer une interruption; une session trouvée après redémarrage est proposée explicitement. Le prototype ne garantit pas une trace continue après un arrêt forcé.

### Profils de localisation

Dans **Réglages**, le profil s’applique au prochain Run et reste épinglé dans cette session, y compris lors d’une récupération. Un nouveau choix en Réglages ne change pas une course déjà commencée. Le profil par défaut est **Équilibré**.

| Profil | Niveau de précision demandé | Cadence demandée | Filtre de distance demandé |
|---|---|---:|---:|
| Précision | `bestForNavigation` | 1 s | 2 m |
| Équilibré | `high` | 2 s | 3 m |
| Autonomie | `high` | 5 s | 5 m |

Ces valeurs configurent la requête faite au système Android. Le fabricant, le système, la réception et les économies d’énergie peuvent faire varier la cadence réellement reçue; le profil Autonomie ne garantit donc pas une durée de batterie particulière. Pour comparer les profils, utilisez le même appareil, la même sortie et la même durée, puis consignez cadence observée, conditions GPS et niveau de batterie dans [la fiche terrain](field-validation.md).

### Diagnostics GNSS

Pendant une course GPS réelle, ouvrez **Diagnostics GNSS** pour consulter les nombres de satellites vus et utilisés, regroupés par constellation lorsque l’OS les expose. Le téléphone choisit les constellations; MapFollow ne les sélectionne pas. Le panneau observe le récepteur déjà actif, n’émet pas une seconde demande de position GPS et ne mémorise pas les relevés. Il requiert la permission de localisation déjà utilisée pour la course et n’en demande pas une autre.

L’écoute existe seulement tant que le panneau est visible et l’activité Android reprise. En simulation, le diagnostic est signalé comme indisponible. Le panneau distingue les états inactif, attente de la première observation, permission requise, indisponible et instantané périmé (aucune mise à jour depuis plus de 10 secondes). Le nombre de satellites vus ou utilisés ne garantit pas la précision de la position; les critères de qualité affichés par la course restent séparés.

## Voix et podcasts

Le guidage vocal dépend d’une voix française Android installée et utilisable hors ligne. Si elle manque, le démarrage d’une course guidée est refusé; une course libre ne fait pas d’annonces et ne dépend pas de la synthèse vocale. Dans Android, ouvrez **Paramètres > Gestion globale > Synthèse vocale**, choisissez le moteur disponible puis gérez/téléchargez la voix française dans ses réglages. Les noms des menus changent selon le téléphone.

En mode guidé, MapFollow demande le focus audio Android `MAY_DUCK` pendant la parole et le libère ensuite. En pratique cela peut baisser le volume d’un podcast; certaines applications peuvent mettre le podcast en pause lors d’une interruption. Le pont natif signale les interruptions et arrête l’annonce. Le Run libre ne prépare pas et n’appelle pas la voix. Testez le guidage avec votre lecteur habituel : le comportement dépend de celui-ci.

## Samsung : dépannage

Sur Samsung Galaxy S23 Ultra et Galaxy S21 5G, si le suivi écran verrouillé se coupe, regardez si MapFollow est dans les applications en veille ou en veille profonde, vérifiez son réglage de batterie et confirmez que l’autorisation de localisation est toujours active. Les menus varient selon la version One UI. Notez modèle, version Android/One UI, build et réglages observés dans [la fiche terrain](field-validation.md). Ces deux appareils sont des cibles d’essai; aucun résultat n’est encore confirmé.

## Réseau et carte

La carte utilise des tuiles en ligne OpenStreetMap et montre leur attribution. Une perte de réseau peut laisser une carte vide ou incomplète; les traces de course restent enregistrées localement, mais le fond de carte n’est pas disponible hors ligne. Les demandes de tuiles révèlent au service réseau concerné l’adresse IP et les secteurs affichés. Respectez les [règles d’utilisation des tuiles OpenStreetMap](https://operations.osmfoundation.org/policies/tiles/); ne préchargez pas les tuiles pour un usage hors ligne.
