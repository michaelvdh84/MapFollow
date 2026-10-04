# MapFollow

MapFollow est un prototype Flutter de guidage et d’enregistrement de parcours. L’application Android affiche une carte OpenStreetMap, importe un itinéraire, annonce des indications, enregistre une course localement et exporte une trace GPX. Le support iOS est une piste future, non prise en charge ni testée aujourd’hui.

## État du projet

Le prototype contient les fonctions décrites dans ce guide. Le dernier APK debug a été construit, l’analyse ne signale aucun problème, les 34 tests passent et le formatage est propre. Aucun appareil Android physique n’était connecté lors du dernier contrôle : les essais terrain, Samsung et Bluetooth restent à faire. Voir [le journal de vérification](docs/verification.md) et [PLAN.md](PLAN.md).

## Démarrer sur Windows

Pour un premier essai pas à pas, suivez le **[guide de démarrage et simulation sur PC / Samsung](docs/startup-guide.md)** : création de l’émulateur Android, préparation de la voix, démo sans courir, installation sur téléphone et passage au GPS réel.

### Ce PC

Les outils nécessaires sont déjà présents dans `.tools/` sur le PC de développement. Ouvrez PowerShell dans le dépôt et passez aux commandes ci-dessous. Android Studio n’est pas nécessaire pour compiler avec le SDK local déjà installé; il reste utile pour gérer le SDK par interface graphique ou créer un émulateur. `flutter doctor` peut montrer des avertissements de PATH ou signaler Visual Studio : ils ne bloquent pas le build Android avec le wrapper local.

### Préparer un nouveau PC Windows

Suivez **[le guide complet d’installation sur un nouveau PC](docs/new-pc-setup.md)**. Il couvre Git, VS Code, Flutter 3.47.6, JDK 17, Android Studio, les composants SDK, les chemins locaux, l’émulateur, la première modification et la validation. Les outils et l’APK ne sont pas fournis par Git; aucun script ne télécharge automatiquement tous ces prérequis.

Le wrapper local configure les chemins quand les dossiers `.tools/` sont installés :

Depuis PowerShell, à la racine du dépôt :

```powershell
.\scripts\flutter.ps1 doctor -v
.\scripts\flutter.ps1 pub get
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 build apk --debug
```

Le wrapper configure les caches et les chemins Flutter, Android SDK et Java pour chaque commande. Pour `build` ou `run`, il crée automatiquement `.tools/debug.keystore` si nécessaire. Cette clé de développement standard est ignorée par Git et ne sert pas à signer une version de publication. Les versions connues sont Flutter 3.47.6, Dart 3.13.5 et Java Temurin 17.0.20.1. Android est configuré avec compile/target SDK 36, minimum 26, Android Gradle Plugin 9.1, Kotlin 2.4 et NDK 28.2.13676358. Les dépendances de l’application sont déclarées dans `pubspec.yaml` et verrouillées dans `pubspec.lock`.

Pour essayer l’application sur un téléphone Android :

1. Activez les Options pour les développeurs puis le Débogage USB sur le téléphone.
2. Branchez-le et acceptez la demande d’autorisation affichée sur le téléphone.
3. Dans PowerShell, vérifiez qu’il est visible, puis lancez l’application :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe devices
.\scripts\flutter.ps1 run -d DEVICE_ID
```

Remplacez `DEVICE_ID` par l’identifiant affiché par la première commande. Pour générer puis installer manuellement l’APK de débogage :

```powershell
.\scripts\flutter.ps1 build apk --debug
.\.tools\android-sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
```

L’APK debug final du 4 octobre 2026 se trouve à `build/app/outputs/flutter-apk/app-debug.apk`. Il porte le nom de paquet `be.mapfollow.mapfollow`, version `0.1.0` (code 1), cible Android 26 minimum et SDK compile/target 36. Il ne s’agit pas d’une version de publication.

## Dans l’application

Les onglets sont **Parcours**, **Course**, **Historique** et **Réglages**. Un parcours de démonstration `assets/demo.gpx` est inclus. La simulation se lance depuis l’onglet **Course** et fait avancer la position sur le même flux que les mises à jour GPS, à 3 m/s. Le bouton de test des réglages vérifie la voix.

Lisez [docs/android.md](docs/android.md) avant les essais avec écran verrouillé ou les annonces vocales. Consultez [docs/routes-and-storage.md](docs/routes-and-storage.md) pour l’import, l’enregistrement et l’export, et [docs/privacy-and-testing.md](docs/privacy-and-testing.md) pour les données et les précautions terrain.

## Limites et confidentialité

Les parcours et les points d’enregistrement restent en local dans SQLite. Il n’y a ni compte, ni serveur, ni partage de position en direct, ni carte hors ligne. L’affichage des tuiles nécessite Internet. Le service de tuiles reçoit les demandes de carte, qui révèlent notamment la zone consultée et l’adresse IP au service réseau concerné; l’attribution OpenStreetMap reste visible dans l’application.

Les données d’itinéraire sont sensibles. Pour les exemples, journaux, captures ou rapports de bogue, utilisez des coordonnées synthétiques et n’écrivez jamais de vraies traces GPS dans le dépôt ou les logs. L’application ne comporte pas encore d’écran de suppression durable des données. Le manifeste Android désactive les sauvegardes automatiques complètes; le comportement après installation/restauration reste à confirmer sur les versions ciblées. Un GPX partagé suit aussi les règles de l’application qui le reçoit.

## Guides

- [docs/new-pc-setup.md](docs/new-pc-setup.md) : installer tous les prérequis sur un nouveau PC et commencer à modifier le code.
- [docs/startup-guide.md](docs/startup-guide.md) : premier lancement, simulation sur PC et Samsung, résultats attendus et dépannage.
- [PLAN.md](PLAN.md) : fonctions réalisées, limites, vérification.
- [STRUCTURE.md](STRUCTURE.md) : architecture du code.
- [docs/android.md](docs/android.md) : installation, permissions, voix et dépannage Samsung.
- [docs/routes-and-storage.md](docs/routes-and-storage.md) : formats de fichiers, SQLite et GPX.
- [docs/privacy-and-testing.md](docs/privacy-and-testing.md) : confidentialité et essais manuels.
- [docs/verification.md](docs/verification.md) : résultats datés des contrôles réalisés.
- [docs/field-validation.md](docs/field-validation.md) : fiche vierge de compte rendu terrain.
- [Skill MapFollow](.agents/skills/mapfollow-development/SKILL.md) : consignes pour les agents de développement.
