# Démarrage : simuler sur PC et tester sur Android

Ce guide permet d’essayer MapFollow sans courir, puis de passer au GPS réel sur votre S23 Ultra ou S21 5G. Sur PC, l’application Android tourne dans un **émulateur Android**. Le POC n’a pas de version Windows native ni de version navigateur.

Deux choses sont distinctes : l’émulateur remplace le téléphone; le bouton **Simuler ce parcours** remplace les positions GPS par un déplacement automatique sur le tracé. Le même scénario de simulation fonctionne aussi sur le téléphone physique.

## 1. Préparer le projet sur Windows

Sur le PC où MapFollow a été développé, ouvrez PowerShell et placez-vous dans le dossier existant :

```powershell
Set-Location C:\Users\vdh_m\sources\repo\MapFollow
.\scripts\flutter.ps1 doctor -v
.\scripts\flutter.ps1 pub get
```

Résultat attendu : la partie **Android toolchain** fonctionne et les dépendances sont récupérées. Les outils de compilation sont déjà dans `.tools/` sur ce PC. L’émulateur et Android Studio n’ont pas été installés lors de la préparation du POC; suivez la section suivante pour les ajouter.

Sur un autre PC, clonez d’abord le dépôt :

```powershell
git clone https://github.com/michaelvdh84/MapFollow.git
Set-Location MapFollow
```

Installez ensuite les prérequis selon [le guide complet pour un nouveau PC Windows](new-pc-setup.md). Vous avez déjà effectué son étape de clonage : poursuivez avec Flutter et Java. `.tools/` et l’APK ne sont pas fournis par Git. Revenez aux deux commandes `doctor` et `pub get` après l’installation. Gardez les versions du projet indiquées dans le README.

## 2. Créer le téléphone virtuel sur PC

1. Installez et ouvrez [Android Studio](https://developer.android.com/studio).
2. Dans **SDK Manager**, vérifiez le chemin du SDK. Pour utiliser le SDK existant avec le wrapper, choisissez le chemin absolu `C:\Users\vdh_m\sources\repo\MapFollow\.tools\android-sdk` (adaptez-le si le dépôt est ailleurs). Dans **SDK Tools**, ajoutez **Android Emulator**.
3. Ouvrez **Device Manager** depuis **More Actions** sur l’accueil, ou depuis le menu **Tools** / **View > Tool Windows** selon la version.
4. Cliquez sur **+ / Create Virtual Device** et choisissez un téléphone Pixel avec prise en charge de Google Play. Ce profil ne reproduit pas One UI Samsung.
5. Téléchargez une image **Android API 36 avec Google Play**, en `x86_64` pour un PC Intel/AMD, ou adaptée à l’architecture du PC. Le Play Store permet, si nécessaire, d’installer un moteur vocal et vos lecteurs audio.
6. Nommez l’appareil, par exemple `MapFollow_API_36`, terminez sa création, puis démarrez-le avec le bouton ▶. Attendez que l’écran d’accueil Android apparaisse.

Ces étapes suivent les guides officiels [Android Device Manager](https://developer.android.com/studio/run/managing-avds) et [Flutter pour Android](https://docs.flutter.dev/platform-integration/android/setup). Si l’émulateur signale un problème de virtualisation, consultez son diagnostic et [l’accélération de l’émulateur](https://developer.android.com/studio/run/emulator-acceleration).

Dans PowerShell, à la racine de MapFollow :

```powershell
.\scripts\flutter.ps1 emulators
.\scripts\flutter.ps1 devices
```

Résultat attendu : `devices` affiche un appareil de plateforme **android**, par exemple `emulator-5554`. Utilisez son identifiant exact pour lancer MapFollow :

```powershell
.\scripts\flutter.ps1 run -d emulator-5554
```

Remplacez `emulator-5554` si l’identifiant est différent. La première compilation peut prendre plusieurs minutes. Gardez cette fenêtre PowerShell ouverte pendant l’essai; la touche `q` termine la session Flutter. Si aucun appareil Android n’apparaît, vérifiez que l’émulateur est démarré et qu’Android Studio utilise le même SDK que le wrapper. Ne choisissez pas la cible Windows ou Chrome.

## 3. Préparer la voix dans Android

Ces réglages se font **dans l’émulateur ou sur le téléphone**, pas dans Windows.

1. Ouvrez les paramètres Android et recherchez **Synthèse vocale** ou **Text-to-speech**. Sur Samsung, consultez généralement **Gestion globale > Synthèse vocale**.
2. Choisissez un moteur disponible et installez ses données vocales **françaises hors connexion**. Un moteur absent peut être installé depuis le Play Store; ses menus dépendent de l’image Android et du téléphone.
3. Augmentez le volume multimédia. Dans MapFollow, ouvrez **Réglages**, ajustez le volume et utilisez **Tester la voix enregistrée**.

Résultat attendu : une phrase française est audible. Sans voix française locale reconnue, MapFollow refuse de démarrer la course, y compris la simulation. Voir [le dépannage vocal](android.md#voix-et-podcasts).

## 4. Faire la première simulation sans courir

Le scénario est identique sur PC et sur Android physique :

1. Dans **Parcours**, touchez **Charger la démo synthétique**. L’application passe à **Course**.
2. Vérifiez le tracé, le départ, l’arrivée et les **Indications avant départ**. Internet est nécessaire pour le fond de carte.
3. Dans **Réglages**, laissez l’annonce à **20 mètres**, puis revenez à **Course**.
4. Touchez **Simuler ce parcours**. Ce mode ne demande pas la permission GPS et ne lance pas le service de localisation Android.
5. Observez la position se déplacer à **3 m/s**, la distance et la durée augmenter, et les annonces avant les virages. La démo mesure environ **330 m** : comptez environ **deux minutes**, hors pauses.
6. Touchez **Pause** : les positions et les annonces s’arrêtent. Touchez **Reprendre** : un nouveau segment d’enregistrement commence.
7. Laissez la simulation atteindre l’arrivée; elle termine automatiquement la session. Vous pouvez aussi utiliser **Terminer** et confirmer.
8. Dans **Historique**, la course porte le préfixe **SIMULATION**. Touchez **Exporter le GPX**, puis choisissez une application de destination dans la feuille de partage Android. Les possibilités de partage dépendent des applications installées.

Résultat attendu : une course simulée enregistrée, avec des points horodatés et un GPX exportable. La démo est une géométrie synthétique destinée aux essais; ne la suivez pas sur le terrain.

Pour essayer un autre fichier, transférez un GPX/TCX/PWX dans **Téléchargements** de l’appareil, puis utilisez **Importer GPX, TCX ou PWX**. Sur l’émulateur, vous pouvez par exemple copier les fichiers synthétiques depuis PowerShell :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe -s emulator-5554 push test\fixtures\route.gpx /sdcard/Download/mapfollow-route.gpx
.\.tools\android-sdk\platform-tools\adb.exe -s emulator-5554 push test\fixtures\course.tcx /sdcard/Download/mapfollow-course.tcx
.\.tools\android-sdk\platform-tools\adb.exe -s emulator-5554 push test\fixtures\workout.pwx /sdcard/Download/mapfollow-workout.pwx
```

Adaptez l’identifiant. Ces petits fichiers vérifient surtout l’import; la démo intégrée convient mieux au premier essai vocal.

## 5. Installer sur votre S23 Ultra ou S21 5G

### Depuis ce PC, en USB

1. Sur Samsung, ouvrez **Paramètres > À propos du téléphone > Informations sur le logiciel** et touchez sept fois **Numéro de version** pour activer les options développeur.
2. Activez **Options pour les développeurs > Débogage USB**.
3. Branchez un câble USB permettant le transfert de données, déverrouillez le téléphone et acceptez son dialogue d’autorisation.

Dans PowerShell :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe devices
.\scripts\flutter.ps1 devices
```

Résultat attendu : le Samsung apparaît avec l’état `device`. Remplacez `SAMSUNG_ID` par son identifiant :

```powershell
.\scripts\flutter.ps1 run -d SAMSUNG_ID
```

Si vous souhaitez uniquement installer l’APK déjà construit sur ce PC :

```powershell
.\.tools\android-sdk\platform-tools\adb.exe -s SAMSUNG_ID install -r build\app\outputs\flutter-apk\app-debug.apk
```

L’option `-s` évite d’installer sur l’émulateur par erreur lorsqu’il est également ouvert. Pour reconstruire l’APK, utilisez `.\scripts\flutter.ps1 build apk --debug`. Ne désinstallez pas l’application pour résoudre un problème de signature sans sauvegarder les courses à conserver; une désinstallation efface ses données locales.

### Sans connexion USB

Copiez `build/app/outputs/flutter-apk/app-debug.apk` du PC vers le téléphone. Ouvrez ce fichier depuis **Mes fichiers**, puis autorisez cette application à installer l’APK si Android le demande. Aucun compte Play Store développeur n’est nécessaire. L’APK est un build de test; il n’est pas inclus dans le dépôt GitHub.

Préparez la voix selon la section 3, puis refaites exactement la simulation de la section 4. Vous pouvez ainsi vérifier l’interface et les annonces depuis chez vous.

## 6. Passer aux essais réels

| Essai | Ce que vous pouvez vérifier |
|---|---|
| Simulation intégrée sur émulateur | Interface, imports, progression, virages, pause/reprise, historique et tentative de partage |
| Simulation sur Samsung, écran allumé | Même scénario; son et interaction avec un lecteur audio installé |
| GPS réel sur Samsung, écran verrouillé | Service persistant, permissions, tenue en poche et restrictions Samsung |
| Course réelle et casque Bluetooth | Qualité GPS, guidage, autonomie et comportement du lecteur audio |

La simulation suit parfaitement le tracé : aucun réglage de l’interface ne permet actuellement d’injecter une sortie de parcours, du bruit GPS ou une perte de signal. Ces cas disposent de tests automatisés. La simulation n’utilise pas le service GPS persistant; la verrouiller ne valide donc pas le maintien du guidage en poche.

Pour le GPS réel, terminez la simulation, importez un parcours réel, placez-vous près de son départ et touchez **Démarrer avec le GPS**. Accordez la localisation précise pendant l’utilisation et les notifications. Vérifiez la notification persistante et une précision exploitable, puis testez l’écran verrouillé. Avec votre lecteur musical/podcast, vérifiez la baisse du volume pendant les annonces; certains lecteurs peuvent se mettre en pause. Relevez vos observations dans [la fiche terrain](field-validation.md).

Pour les essais réseau, coupez uniquement Internet tout en gardant la localisation activée. Le fond de carte peut manquer; le GPS réel et l’enregistrement local doivent continuer. Les essais Samsung, Bluetooth et de batterie ne sont pas encore validés par les contrôles réalisés sur PC.

## 7. Vérifier la logique sur PC sans émulateur

```powershell
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 test test\navigation_test.dart
.\scripts\flutter.ps1 test test\ui_preview_test.dart
```

Les tests de navigation couvrent notamment les seuils, les croisements et les alertes GPS. Le test d’interface produit des images sous `build/previews/` : ce sont des captures de test, pas une application interactive. Les résultats connus sont consignés dans [verification.md](verification.md).

## Dépannage rapide

- **`unauthorized` dans `adb devices`** : déverrouillez le Samsung et acceptez l’autorisation USB; rebranchez si le dialogue n’apparaît pas.
- **Aucun Samsung détecté** : essayez un câble de données, vérifiez le débogage USB et, si nécessaire, installez le [pilote USB Samsung officiel](https://developer.samsung.com/android-usb-driver).
- **Aucune voix / démarrage refusé** : installez une voix française hors connexion et relancez le test vocal avant la course.
- **Carte vide** : vérifiez Internet et utilisez le bouton de nouvelle tentative proposé par la carte; le déplacement simulé ne dépend pas des tuiles.
- **Boutons de démarrage grisés** : terminez la session active ou traitez la proposition de récupération d’une course interrompue.
- **Suivi arrêté en poche** : consultez [le dépannage Samsung](android.md#samsung--dépannage) et notez Android/One UI et les réglages observés.

État de ce guide au 4 octobre 2026 : étapes alignées sur le code et les guides officiels. Aucun émulateur Android n’était installé ni aucun Samsung connecté pendant sa rédaction; le parcours interactif complet reste à exécuter sur ces appareils.
