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

Résultat attendu : une phrase française est audible. La voix française est nécessaire aux courses guidées (y compris la simulation d’un parcours); une course libre n’utilise pas la voix. Voir [le dépannage vocal](android.md#voix-et-podcasts).

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

Pour essayer l’enregistrement sans itinéraire, dans **Parcours** ou **Course**, touchez **Lancer un Run libre** pour recevoir le GPS réel, ou **Simuler un Run libre** pour employer le trajet synthétique déterministe. La simulation fait deux passages aller-retour sur le même tracé en utilisant le pipeline de positions normal. Le mode libre ne demande aucune voix et n’annonce pas de guidage. Le GPS réel affiche la notification Android habituelle; ses avertissements de qualité restent visibles dans l’écran. La simulation ne démarre pas le service Android au premier plan. Une course libre terminée dont un même segment contient au moins deux positions distinctes apparaît dans l’historique et comme parcours enregistré; les sessions trop courtes restent dans l’historique sans parcours. Les pauses et reprises créent des segments distincts.

Après **Terminer**, l’écran affiche **Run terminé**. Si un parcours a été créé, touchez **Voir le parcours** pour le retrouver dans Parcours. **Renommer** met aussi à jour le nom de la session; pour une simulation, le préfixe `SIMULATION` est conservé. **Exporter / partager** ouvre la feuille de partage avec un GPX enrichi. Si la trace ne contient pas assez de points, elle reste disponible dans l’historique, mais l’export n’est pas proposé.

Dans **Réglages**, le menu **Profil GPS de la prochaine course** propose **Précision · 1 s / 0 m** (défaut des nouveaux réglages), **Équilibré · 2 s / 3 m** et **Autonomie · 5 s / 5 m**. Une préférence déjà enregistrée est conservée. Ce sont des demandes à Android, pas des garanties d’intervalle ni de durée de batterie. La session garde le choix fait à son démarrage. Pendant une course, les commandes **Auto**, **Aller** et **Retour** classent les prochains points enregistrés; dans le mode guidé, elles ne retournent pas le sens du parcours importé. La carte permet de masquer les couches Aller et Retour. L’écran présente vitesse et allure live à partir des vitesses GPS récentes; le résumé utilise distance et durée active. Le mode batterie Normal/Diagnostic se choisit avant le départ ; la préparation OSM et la suppression de l’historique sont décrites dans [le guide dédié](gps-guidance-and-diagnostics.md).

Pendant un Run GPS réel, ouvrez **Diagnostics GNSS** pour voir les satellites vus/utilisés par constellation lorsque Android les fournit. Le téléphone choisit ses constellations; ce panneau observe le GNSS déjà actif, ne démarre pas une autre requête de position et ne conserve aucun relevé. Il ne s’ouvre pas en simulation et signale les données périmées après 10 s. Ces nombres ne sont pas une mesure de précision GPS.

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

La simulation guidée suit le tracé importé; la simulation du Run libre fait deux passages aller-retour synthétiques. L’interface ne permet pas d’injecter une sortie de parcours, du bruit GPS ou une perte de signal; les règles correspondantes sont couvertes par des tests automatisés, mais ceux de la version courante restent à consigner dans [le journal](verification.md). Aucune simulation n’utilise le service GPS persistant; la verrouiller ne valide donc pas le maintien du GPS en poche.

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
- **La voix manque / démarrage guidé refusé** : installez une voix française hors connexion et relancez le test vocal. Une course guidée (y compris sa simulation) exige la voix; le Run libre ne l’utilise pas.
- **Carte vide** : vérifiez Internet et utilisez le bouton de nouvelle tentative proposé par la carte; le déplacement simulé ne dépend pas des tuiles.
- **Boutons de démarrage grisés** : terminez la session active ou traitez la proposition de récupération d’une course interrompue.
- **Suivi arrêté en poche** : consultez [le dépannage Samsung](android.md#samsung--dépannage) et notez Android/One UI et les réglages observés.

Consultez [le journal de vérification](verification.md) et [la fiche terrain](field-validation.md) pour les résultats de `0.4.0+4`. Les contrôles des versions précédentes restent historiques ; les essais de course comparative et de partage réel demandent une validation terrain.
