# Comparaison S21 5G — 12 octobre 2026

## Données et référence

Sortie fournie explicitement par l'utilisateur : GPX Garmin, GPX MapFollow et export Diagnostic contenant les positions. Les trois fichiers sont lus en mémoire ; aucune coordonnée, carte ou copie de trace n'est ajoutée au dépôt. Appareil MapFollow : Galaxy S21 5G, version installée `0.5.0+5`, filtre déclaré `kalman-cadence-2`, Précision, intervalle personnalisé 500 ms et mode Diagnostic. La montre et le téléphone étaient portés par la même personne ; le téléphone était dans une poche du vêtement au niveau de la jambe. Le téléphone a été lancé dans la maison, puis la montre au début effectif de la course.

La montre affichait **5,03 km**, selon l'utilisateur. Le GPX Garmin reconstruit par somme des distances géodésiques entre points donne **5 067,2 m** : le compteur de la montre et la longueur géométrique du GPX sont deux références distinctes. Le compteur est arrondi et les deux récepteurs ne constituent pas une vérité terrain absolue.

## Distances comparables

La période commune aux points des deux GPX dure **2 049 s** (34 min 09 s). Les extrémités MapFollow sont interpolées aux instants Garmin avant de sommer les segments. Cela exclut **15,6 s avant Garmin** et **23,5 s après** ; le Run complet dure environ 34 min 50 s. Les pauses ou pertes GPS ne sont pas reliées artificiellement.

| Mesure | Distance | Écart face au compteur Garmin 5 030 m |
|---|---:|---:|
| MapFollow complet exporté | 5 277,0 m | +4,91 % ; départ/arrêt différents |
| MapFollow filtré, période commune | 5 208,3 m | **+3,54 %** |
| Positions brutes Android, période commune | 5 068,3 m | +0,76 % |
| Intégrale de vitesse GNSS, période commune | 5 087,3 m | +1,14 % |
| GPX Garmin reconstruit | 5 067,2 m | +0,74 % |

L'écart GPX-à-GPX filtré est **+2,78 %**. La cible utilisateur ≤2 % n'est donc pas atteinte sur cette sortie. L'intégrale de vitesse est un contrôle indépendant du calcul géométrique, pas une distance de remplacement validée.

## Cadence, qualité et batterie

- Demande 0,5 s ; cadence des mesures médiane **0,673 s**, percentile 95 **0,951 s**. La réception présente presque les mêmes valeurs (0,674 / 0,952 s). La demande Android n'est pas une garantie de fréquence.
- **3 134 mesures reçues et acceptées**, 3 129 points enregistrés, un segment ; aucune rupture supérieure à 10 s ni mesure non monotone. Toutes les décisions sont `filtered`. L'absence de rejet ne prouve pas l'absence de bruit ou de biais.
- Précision annoncée médiane **6,26 m**, percentile 95 **8,65 m** ; il s'agit d'une estimation Android, pas d'une erreur mesurée contre une référence au sol.
- Vitesse GNSS médiane **2,478 m/s**, incertitude médiane **0,266 m/s** ; trois mesures n'ont pas de vitesse disponible.
- Batterie **47 → 42 %**, soit **5 points** sur le téléphone entier ; 36 relevés, pas de recharge, d'interruption ni de mesure manquante signalée. Les autres applications actives n'ont pas été précisées pour cette sortie.
- L'export est cohérent : les segments contiennent exactement les 3 129 points annoncés. Les positions ont été explicitement incluses dans ce fichier.

La séparation spatiale entre GPX interpolés aux mêmes instants est **13,1 m en médiane / 27,1 m au percentile 95**. Un décalage exploratoire de quatre secondes améliore la correspondance des deux traces, brutes comme filtrées : cela ne suffit pas à attribuer ce décalage au filtre ou à corriger arbitrairement les distances.

## Inflation introduite par le filtre

Le filtre ajoute **140,0 m** aux positions brutes sur la période commune, alors que celles-ci ont presque la même longueur que le GPX Garmin. Cette somme n'est pas due à un double comptage du controller : celui-ci additionne les cordes des points filtrés enregistrés. Le rejeu du filtre courant reproduit la longueur commune exportée à l'arrondi près.

Après exclusion des deux premières minutes communes, le filtre ajoute encore **131,9 m** ; après exclusion des cinq premières minutes, **132,8 m**. Le démarrage dans la maison ne suffit donc pas à expliquer cette inflation. Cette sortie ne permet pas de conclure que la poche ou le S21 sont à eux seuls responsables des écarts.

Deux mécanismes sont à corriger ou à tester davantage :

1. La contrainte EKF sur la norme de vitesse interne ne borne pas les corrections de position qui servent au calcul des distances.
2. Le maintien du mode courbe exige deux cordes de 6 m dans une fenêtre de quatre secondes. À environ 2,48 m/s, ces cordes exigent au moins 4,84 s ; le maintien devient difficile et peut alterner retard et rattrapage. Les tests antérieurs de cercle à précision 3 m ne couvrent pas ce cas.

Les expériences temporaires isolent les mécanismes sans changer le code livré : désactiver les seuls boosts de réactivité donne environ **5 167,3 m** en commun, mais rejette 101 mesures et dégrade fortement les courbes synthétiques. Retirer la contrainte de norme GNSS et utiliser la base position seule donne **5 082,8 m** en rejeu, mais présente encore de fortes erreurs sur certains cercles et dérives lentes synthétiques. Ces variantes ne sont pas des corrections validées ni de nouvelles sorties.

Avec le filtre courant, les scénarios synthétiques à précision 6,255 m, vitesse 2,478 m/s et pas 673 ms donnent environ **+13,3 %** sur une ligne droite avec dérive corrélée lente, **+14,1 %** sur un cercle sans bruit et **+10,3 %** sur un rectangle sans bruit. Ces scénarios révèlent des limites absentes des anciens tests et justifient d'élargir les critères de distance avant de choisir une correction.

## Suite de la correction

Conserver cette sortie comme référence agrégée ; ne pas la rejouer une seconde fois depuis le GPX déjà filtré. Les diagnostics bruts permettent un rejeu unique et reproductible du traitement. Évaluer distance, erreur spatiale et retard séparément, puis couvrir des lignes avec bruit corrélé sur 30–60 s, courbes et virages avec précision voisine de 6 m, vitesse 2,48 m/s et cadences 0,5–1 s. Préserver arrêts, sauts, segmentation et récupération. Une correction doit réussir ces scénarios avant une nouvelle installation et une nouvelle comparaison terrain. Aucune modification du filtre de production ni de l'ancienne course n'est réalisée lors de cette analyse.

## Correction suivante — 0.5.1+6, `kalman-passive-3`

Le défaut a ensuite été corrigé avec une régularisation de sortie et une fenêtre de mouvement de huit secondes, décrites dans [le guide du filtre](gps-guidance-and-diagnostics.md). Le rejeu en mémoire du code final applique aussi le seuil d'enregistrement de 0,75 m et les contrôles de qualité du controller. Il reproduit exactement l'ancienne distance complète de 5 277,0 m avant comparaison.

| Rejeu | Complet | Période commune | Écart commun / compteur 5 030 m |
|---|---:|---:|---:|
| Filtre 0.5.0, référence exportée | 5 277,0 m | 5 208,3 m | +3,54 % |
| Correction 0.5.1 | 5 073,7 m | 5 015,8 m | −0,28 % |

La correction enregistre 3 014 points sur 3 134 reçus, sans rejet de filtre ni de qualité sur ce rejeu. L'écart commun face à la longueur géométrique Garmin est −1,01 %. **Il s'agit d'un rejeu, pas d'une nouvelle précision terrain validée.** Le fichier GPX original et la course sur le téléphone sont conservés.

Les tests élargis vérifient cercles et rectangles à précision 3/6 m et cadence 250/500/673/1 000 ms avec distance à moins de 2 % de leur géométrie synthétique et erreur de position inférieure à 7 m. Ils couvrent les transitions d'incertitude manquante, le seuil 0,49/0,51 m/s, la rotation du repère et l'indépendance à l'orientation du téléphone. Les cas de bruit rapide antérieurs restent couverts. Pour le cas synthétique de dérive lente à précision 6 m, l'erreur passe d'environ +13,2 % à +3,8 % : amélioration, mais cette ambiguïté ne satisfait pas une garantie universelle ≤2 %.

Le contrôle spatial aux instants Garmin passe d'environ 13,2 / 27,2 m à 13,8 / 27,9 m (médiane / percentile 95). Le meilleur décalage exploratoire reste quatre secondes dans les deux cas ; à ce décalage, la séparation médiane passe de 10,2 à 10,0 m. La correction de longueur n'établit donc pas une amélioration d'erreur spatiale absolue et introduit un léger compromis de lissage. Une nouvelle sortie sur chaque téléphone reste nécessaire.
