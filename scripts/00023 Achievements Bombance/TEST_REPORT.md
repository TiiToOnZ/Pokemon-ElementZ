# Vérification V1 finalisée — 7 octobre 2026

Runtime : **Ruby Studio 3.0.6 i386-mingw32**, PSDK **6716**.
Aucune sauvegarde personnelle n'est chargée ou écrite par les tests.

## Résultats

| Suite | Résultat |
|---|---|
| Régressions Succès existantes, run.rb | **27 tests, 264 assertions, 0 échec, 0 erreur** |
| Contenu final / intégration, finalization.rb | **25 tests, 232 assertions, 0 échec, 0 erreur** |
| Total Succès | **52 tests, 496 assertions, 0 échec, 0 erreur** |
| Rendu natif LiteRGSS, native_ui.rb | **243 contrôles réussis** |
| SaveLoadTweaks, suite séparée | **34 tests, 263 assertions, 0 échec** |
| Apricorn, suite séparée | **71 tests, 745 assertions, 1 échec, 2 erreurs**, préexistants |
| Audit Studio, audit_data.rb | 828 espèces ; 197 alternatives ; 39 alternatives dans les zones ; 27 zones ; 72 quêtes secondaires |

Les 27 scénarios historiques sont conservés dans run.rb. Leur ancien contenu
à six paliers est isolé dans legacy_content.rb, car ils testaient explicitement
Général vide et les seuils 50/75. Seule l'attente du schéma est adaptée à version 2.
La nouvelle suite teste les vraies définitions livrées.

## Couverture A–W demandée

| Cas | Vérification |
|---|---|
| A | Général immédiat, six succès, total 26 |
| B | Chercheur fermé : pas de progression visible ni de gain, même à 700 espèces |
| C | Démarrage natif de la quête 49 ; reconnaissance d'une ancienne quête 69 terminée |
| D | Collectionneur à 0 puis juste avant et sur chaque seuil 5/15/30/60/100/175/275/400/550/700 |
| E | Ancien GameState sans état Succès à 320 : sept paliers une seule fois |
| F | Sauvage, défaite, fuite ignorés ; victoire Dresseur une fois, même via plusieurs handlers du même BattleInfo |
| G | Quêtes secondaires terminées uniquement ; transfert via check_up_signal natif ; principales/actives/échouées exclues |
| H | Œuf acquis sans gain ; retour d'éclosion réussi +1 ; répétition/reload sans doublon ; Pokémon non possédé ignoré |
| I | Rencontre shiny seule sans gain ; acquisition équipe/PC ; relecture, déplacement et reload sans doublon ; deux personnalités identiques distinctes comptent |
| J | Amitié 254 ne suffit pas ; setter natif clamp à 255 ; Pokémon adverse ignoré ; répétition sans gain |
| K | 99 puis 100 via setter et level_up_stat_refresh natifs ; copie battler/original ; rétroactivité PC ; reload sans gain |
| L | Bit d'une nouvelle forme valide vue ; base/forme spéciale/forme inexistante exclues ; répétition/reload stables |
| M | Collection exactement égale à la page Zone ; zone incomplète/complète ; plusieurs zones ; vide ignorée ; groupes tous inactifs gardés |
| N | Total réel puis catalogue simulé de deux zones ; zéro ne récompense pas ; reçu acquis conservé après agrandissement du catalogue |
| O | Nom/description secrets masqués puis révélés ; ligne invisible et exclusion du total ; preuve manuelle conservée dans une catégorie fermée |
| P | Récompense ??? avant obtention, visible ensuite ; ancien test de récompense individuelle cachée conservé |
| Q | Sac verrouillé, dette pending sauvegardée, réessai unique ; anciens tests sac plein/erreur/callback réentrant conservés |
| R | 100 ouvertures : sérialisation GameState identique, ressources détruites |
| S | File absente après reload, aucune réémission des gains déjà reçus |
| T | État absent ou V1 incomplet ; anciens 50/75 conservés ; dette de 50 payée une seule fois ; ancien 100 non redonné |
| U | Six succès sur trois lignes ; dix paliers sur six lignes ; défilement et position au retour |
| V | Unique « Non obtenu / Obtenu », pas de 1/1 ni barre numérique artificielle |
| W | 3/26 Général = 11 % ; Chercheur ouvert, 3/48 global = 6 % ; secrets configurables |

Contrôles additionnels : store annonçant un succès sans réellement ajouter le
Pokémon ne compte pas ; éclosion interrompue (retour false) ignorée ; état
calculé refusé par increment ; changement de récompense sans réécriture d'une
dette ; copies de sauvegarde sans attribution ; 100 frames sans vérification
de succès ; catégories supplémentaires et longues listes.

## Rendu natif inspecté

Les vraies polices et textures LiteRGSS sont chargées dans une fenêtre temporaire
320×240. Contrôles de largeur, limites écran, ressources et libellés ; captures :

- [Catégories verrouillées](tests/categories_locked.png)
- [Général](tests/general_v1.png)
- [Général après défilement](tests/general_scrolled.png)
- [Unique non obtenu](tests/unique_not_obtained.png)
- [Chercheur à 23 espèces](tests/researcher_23.png)
- [Dix paliers / défilement](tests/tiers_scrolled.png)
- [Secret masqué](tests/secret_hidden.png)
- [Unique obtenu](tests/unique_obtained.png)
- [Bandeau unique](tests/notification_unique.png)
- [Bandeau de catégorie](tests/notification_category.png)
- [Bandeau de palier](tests/notification_tier.png)
- [Menu principal](tests/main_menu.png)

Les anciennes captures sont conservées ; general_empty.png représente l'ancien
contenu, pas la V1 finale. Les boutons natifs sans rapport avec cette tâche ont
le libellé de fixture « Menu » ; Quêtes/Succès et leur position sont réels.

## Régressions externes

SaveLoadTweaks reste au vert. La suite Apricorn est autonome et ne charge pas
Succès. Elle retrouve exactement les problèmes du précédent rapport :

- apr_White.png absent du dossier source ../../Noigrumes ;
- apr_background.png absent du même dossier ;
- position de la main : attendu [53,147], code courant [77,118].

Aucun fichier Apricorn n'a été corrigé dans ce chantier. Les autres plugins
(SOS, CaptureChain, BBBB, Battle Bases, Triple Position, InfoBars, Boss,
Battlebacks, GTS, QuestUI, Zone) sont préservés ; cela n'est pas une certification
de tous leurs parcours en jeu.

## Périmètre et limites des tests

Les vraies classes PSDK GameState, Bag, Pokedex, Quests, Pokemon et Storage,
les classes de menu/lifecycle et le vrai catalogue/agrégateur Zone sont utilisés.
Les champs des données Studio sont lus depuis les JSON du projet. Les conditions
de rencontres sont représentées par une fixture booléenne, puis testées toutes
inactives : elles n'affectent pas l'union que la page affiche.

Le monde, l'audio, les messages et les entrées physiques sont isolés. Les
frontières du résultat de combat, de la scène d'éclosion et de la copie battler
sont simulées ; le hook appelle bien super et conserve son résultat.
La logique native de niveau/amitié/Pokédex/quêtes/stockage est exécutée.
Un combat complet, SOS, GTS réseau et la cinématique d'éclosion complète
n'ont pas été joués. La manette physique et les vraies sauvegardes restent
à vérifier avec la checklist. Aucun gain n'a été injecté dans une partie réelle.

## Reproduction

Depuis scripts, sans installer de gem :

```powershell
$rubyStudio = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
$minitestPath = '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib'
& $rubyStudio $minitestPath '00023 Achievements Bombance/tests/run.rb'
& $rubyStudio $minitestPath '00023 Achievements Bombance/tests/finalization.rb'
& $rubyStudio $minitestPath '00023 Achievements Bombance/tests/audit_data.rb'
& $rubyStudio $minitestPath -r 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/lib/LiteRGSS.so' '00023 Achievements Bombance/tests/native_ui.rb'
& $rubyStudio $minitestPath '00008 SaveLoadTweaks/tests/run.rb'
& $rubyStudio $minitestPath '00017 ApricornTrees/tests/run.rb'
```

## Checklist courte dans le vrai jeu

- [ ] Ouvrir Succès ; voir les six Général ; Chercheur verrouillé avant le métier.
- [ ] Débloquer Chercheur chez le professeur ; vérifier les trois succès et les anciens gains.
- [ ] Naviguer au clavier puis à la manette, défiler Général et les dix paliers, revenir.
- [ ] Capturer une nouvelle espèce puis un doublon ; vérifier Collectionneur.
- [ ] Voir une forme alternative ; vérifier Formes et la même entrée dans le Pokédex Zone.
- [ ] Finir les entrées d'une zone, y compris celles d'une autre période ; vérifier Expert local.
- [ ] Gagner un combat Dresseur, puis un sauvage ; seul le premier augmente Combattant.
- [ ] Rencontrer puis capturer un shiny ; seule l'obtention compte ; déplacer au PC sans recompter.
- [ ] Faire éclore un œuf ; vérifier +1 et un seul bandeau ; vérifier aussi un œuf shiny si disponible.
- [ ] Terminer une quête secondaire ; une principale/échouée ne doit pas faire progresser Bienfaiteur.
- [ ] Passer 99→100 et 254→255 d'amitié ; contrôler les uniques et leurs récompenses.
- [ ] Vérifier qu'un bandeau attend la fin d'un dialogue/combat et reste seul à l'écran.
- [ ] Sauvegarder, recharger, rouvrir plusieurs fois : pas de nouveau gain ni d'anciens bandeaux.