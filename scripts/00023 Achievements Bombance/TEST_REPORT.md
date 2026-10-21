# Vérification Succès V2 — 8 octobre 2026

Runtime réellement exécuté : **Ruby Studio 3.0.6 i386-mingw32**, PSDK **6716**.
Aucune sauvegarde personnelle chargée ou modifiée. Données Studio lues uniquement.

## Résultats exécutés

| Suite | Résultat |
|---|---|
| 27 régressions historiques, run.rb | 264 assertions, 0 échec, 0 erreur |
| 23 scénarios V2, v2.rb | 249 assertions, 0 échec, 0 erreur |
| Ensemble Succès, all.rb | **50 tests, 513 assertions, 0 échec, 0 erreur, 0 skip** |
| Rendu natif LiteRGSS, native_ui.rb | **616 contrôles réussis**, captures 320×240 |
| SaveLoadTweaks, suite indépendante | **34 tests, 263 assertions, 0 échec** |
| Noigrumes, suite indépendante | **71 tests, 745 assertions, 1 échec, 2 erreurs préexistants** |
| Syntaxe des 7 fichiers Ruby de production | **Syntax OK** |

Les 49 tests précédemment réussis sont conservés. Un cinquantième teste les
mappings réels clavier/croix/stick/boutons du module Input PSDK installé.

Ces résultats remplacent les chiffres V1 non reproductibles dans la copie
initiale. Ni finalization.rb ni audit_data.rb n'étaient présents ; aucun résultat
d'exécution de ces fichiers n'est revendiqué pour la V2.

## Couverture

| Domaine | Cas exécutés |
|---|---|
| Récompenses | Hash unique, deux objets, objets + argent, quantités répétées du même objet |
| Capacité | sac verrouillé, plafond 99, composante entière qui ne tient pas |
| Atomicité | simulation d'insertion partielle sur le clone : rejet sans crédit réel |
| Lot partiel | premier objet payé, second dû ; sauvegarde/rechargement ; seul le dû est repris |
| Réentrance | callback de quête qui synchronise, callback en erreur, capture du reçu entre deux composantes |
| Configuration | snapshot ancien conservé, ajout de composantes sans complément rétroactif |
| Migration | schémas absents/1/2/3, répétition, version future non abaissée, clés manquantes |
| Reçus | vieux Hash payé ou en attente, vieux Array, lot partiellement normalisé, promesse absente |
| Collectionneur | exactement 18 seuils ; IDs communs, anciens 50/75, retrait 60/100/175/400/550/700 |
| Progression | 0, 5, 15, 30, 855, 901 espèces ; import en lot, doublons et formes |
| Secrets/uniques | preuve manuelle en catégorie fermée, masquage, révélation, rechargement sans nouveau gain |
| Sources | Pokédex natif, formes valides, catalogue Zone réel, quêtes secondaires, équipe/PC |
| Navigation | catégories supplémentaires, succès, 18 paliers, retour et réouverture avec sélection conservée |
| Récompenses UI | 9 composantes en 5 pages, boucle ←/→, page mémorisée par palier |
| Scrollbar | positions haut/milieu/bas, 18/30/1000 lignes, taille minimale du curseur |
| Clavier/manette | méthodes natives de mapping clavier/croix/stick/boutons exécutées ; actions transmises à la scène |
| Popup | 5 composantes sur 3 pages, durée suffisante, un seul son, pause en dialogue, file séquentielle |
| Ressources | 100 ouvertures logiques, ouvertures répétées natives, destruction des panneaux/viewports |
| Isolation | aperçu de sauvegarde sans attribution, 100 frames sans vérification de progression |

Le test de mapping envoie des événements aux méthodes natives d'Input. Il ne
branche pas une manette réelle et ne certifie pas son pilote ou la répétition
physique des touches. La scène utilise toujours les actions natives PSDK.

## Contrôles graphiques réellement exécutés

Polices PokemonDS et textures du projet, vrais Sprite/Text/Shape/Viewport et
boutons du menu natif. Résolution de capture vérifiée 320×240, présence de pixels
vérifiée, largeurs de textes et limites des viewports contrôlées. Les deux buffers
de fenêtre sont synchronisés avant capture pour éviter une image de l'écran
précédent.

Les captures ont été inspectées visuellement : détail initial, palier 18,
catégories supplémentaires, texte long, pages de récompenses et de popup,
état partiellement payé, secret masqué et menu avec la coupe.

La vérification native a détecté puis permis de corriger l'animation :
Shape n'expose pas opacity= ; son alpha est modifié via color, celui du Text via
fill_color, et les sprites via opacity. Le test de popup multipage exerce cette
animation, sans erreur journalisée.

### Captures courantes

- [Catégories](tests/categories_unlocked.png), [catégories verrouillées](tests/categories_locked.png).
- [Liste Général](tests/general_v1.png), [liste après défilement](tests/general_scrolled.png).
- [Liste Chercheur](tests/researcher_23.png).
- [Détail, première page](tests/tiers_23.png), [milieu](tests/tiers_middle.png), [palier 18](tests/tiers_scrolled.png).
- [Catégories supplémentaires](tests/categories_scroll.png).
- [Récompenses page 1](tests/rewards_page_1.png), [page 2](tests/rewards_page_2.png), [page 3](tests/rewards_page_3.png).
- [Lot partiellement payé](tests/detail_partial_payment.png).
- [Popup standard](tests/notification_tier.png), [catégorie](tests/notification_category.png), [unique](tests/notification_unique.png).
- [Popup page 1](tests/popup_page_1.png), [page 2](tests/popup_page_2.png), [page 3](tests/popup_page_3.png).
- [Secret masqué](tests/secret_hidden.png), [unique non obtenu](tests/unique_not_obtained.png), [unique obtenu](tests/unique_obtained.png).
- [Menu principal](tests/main_menu.png).
- [Trophée 22×22](../../graphics/interface/achievements/trophy.png).

Le nom historique general_v1.png est conservé mais son contenu est rendu par la
V2. general_empty.png est une ancienne capture non régénérée et n'est pas une
preuve V2. Les libellés hors périmètre dans main_menu.png valent « Menu » dans
la fixture ; Quêtes/Succès, icônes et placement proviennent des classes réelles.

## Régressions externes et limites

SaveLoadTweaks passe sans modification. La suite Noigrumes ne charge pas Succès
et retrouve les problèmes déjà décrits avant V2 : sources externes
../../Noigrumes/apr_White.png et apr_background.png absentes ; position de main
attendue [53,147], actuelle [77,118]. Aucun fichier Noigrumes n'a été modifié.

Le harnais charge les classes natives GameState/Bag/Pokedex/Quests/Pokemon/
Storage, les classes de menu et le catalogue/agrégateur Zone du projet.
Les données Studio sont adaptées depuis leurs JSON actuels. Les conditions de
groupes hors interrupteurs sont simplifiées dans la fixture : elles n'enlèvent
aucune entrée à l'union utilisée par le succès de zone.

Le monde, les scènes de combat/éclosion, l'audio et les entrées physiques sont
isolés. Aucun parcours complet en jeu, réseau GTS ou sauvegarde personnelle
n'a été exécuté. Les 855 espèces sont simulées dans le Pokédex natif, car la
base actuelle contient 828 espèces hors __undef__. Le seuil 855 reste celui
demandé par le créateur.

## Reproduction depuis le projet définitif

```powershell
Set-Location 'E:/Pokemon_ElementZ/Pokemon_ElementZ'
$rubyStudio = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
$minitestPath = '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib'
& $rubyStudio $minitestPath 'scripts/00023 Achievements Bombance/tests/all.rb'
& $rubyStudio $minitestPath 'scripts/00023 Achievements Bombance/tests/native_ui.rb'
& $rubyStudio 'scripts/00008 SaveLoadTweaks/tests/run.rb'
& $rubyStudio $minitestPath 'scripts/00017 ApricornTrees/tests/run.rb'
```

Les variables facultatives BOMBANCE_SCRIPTS et BOMBANCE_GRAPHICS servent
uniquement à tester une copie temporaire. Elles doivent être absentes pour
la vérification du projet définitif. native_ui.rb écrit ses PNG dans son propre
dossier tests ; les autres tests Succès n'écrivent aucune partie réelle.

## Checklist courte dans le vrai jeu

- [ ] Ancienne sauvegarde : ouvrir Succès, vérifier les reçus déjà payés et Quêtes séparé.
- [ ] Clavier puis manette physique : ↑/↓, A/B, 18 paliers et ←/→ sur un lot de plus de deux récompenses.
- [ ] Débloquer Chercheur par son métier ; vérifier la progression rétroactive du Pokédex.
- [ ] Sac proche de 99 Potions : obtenir le premier palier, vérifier Balls reçues / Potions en attente.
- [ ] Sauvegarder puis recharger, libérer la place, rouvrir Succès : Potions seules, un bandeau complet.
- [ ] Capturer une espèce nouvelle puis une autre forme de la même espèce : pas de doublon Collectionneur.
- [ ] Observer une popup multipage, ouvrir dialogue/menu/combat et vérifier attente/nettoyage.
- [ ] Contrôler uniques/secrets, puis sauvegarder/recharger et ouvrir dix fois sans nouveau gain.
