# Pokémon Bombance — Livraison Succès V2

Projet définitif : **E:/Pokemon_ElementZ/Pokemon_ElementZ**.
Le système existant est amélioré dans **scripts/00023 Achievements Bombance**.
Aucun second système et aucun commit ne sont créés.

## Fonctionnement livré

Les deux syntaxes reward: Hash et reward: [Hash, ...] sont conservées.
Chaque composante a un reçu persistant indépendant. Une composante bloquée ne
bloque pas les autres ; après sauvegarde/rechargement, seuls les gains encore
dus sont repris. Le bandeau est émis lorsque tout le lot est payé.

L'insertion d'objet est contrôlée sur un clone des collections du sac avant
commit. Une insertion native incomplète simulée est rejetée entièrement, sans
crédit partiel dans le sac actif. Les callbacks de quête viennent après le reçu,
pour éviter les doublons lors d'une réentrance. Les récompenses de la définition
sont copiées profondément à l'obtention.

## Architecture et fichiers

| Fichier | Modification |
|---|---|
| 00001 Definitions.rb | Exactement 18 seuils Collectionneur ; récompenses centralisées |
| 00002 StateAndEngine.rb | Migration, reçus par composante, distribution et lecture des lots |
| 00003 Notifications.rb | Popup bleu/or, deux récompenses par page, pagination temporisée, fondu natif |
| **00003 Panel.rb — nouveau** | Cadres Message 12, coupe, icônes, lignes de récompenses, scrollbar et textes |
| 00004 Scene.rb | Trois écrans, viewports découpés, sélection/page mémorisées et navigation |
| 00005 Integration.rb | Seul le chargement de l'icône Succès change |
| 00002 ProgressSources.rb | **Inchangé** |
| README.md / TEST_REPORT.md | Configuration V2, migration, reproduction, résultats et checklist |
| **FINAL_REPORT.md / GIT_STATE.txt / INTEGRATION_CHECKS.txt — nouveaux** | Rapport, état Git et preuve d'exécution dans le projet définitif |
| tests/support.rb / run.rb / native_ui.rb | Harnais restauré, attentes V2 et contrôles graphiques réels |
| **tests/source_support.rb — nouveau** | Adapteurs de données actuelles et chargement des vraies classes PSDK |
| **tests/legacy_content.rb — restauré localement** | Configuration historique retrouvée dans la copie avant finalisation |
| **tests/v2.rb / all.rb — nouveaux** | Scénarios V2 et point d'entrée de toute la suite |
| **tests/build_trophy.rb — nouveau** | Source reproductible de la silhouette pixel art approuvée |
| **graphics/interface/achievements/trophy.png — nouveau** | Coupe dorée 22×22, fond transparent |
| tests/*.png | Captures régénérées et nouveaux cas de contrôle ; liste ci-dessous |

Les helpers absents ne sont présents dans aucun historique Git disponible ;
l'origine exacte de leur omission ne peut pas être établie. La configuration
legacy provient du répertoire local avant finalisation ; les dépendances de
source_support ont été reconstruites et exécutées sur le PSDK installé.

Le fichier GIT_STATE.txt contient la liste exhaustive des fichiers intégrés,
leur SHA-256, le diff --stat et le statut Git. Il est généré après copie et
vérification dans le projet définitif. Les PNG existants régénérés sont
categories_locked, categories_unlocked, main_menu, notification_category,
notification_tier, researcher_23 et tiers_23. general_empty.png est conservé
comme ancienne capture, sans valeur de validation V2.

## Migration du schéma 2 vers 3

migrate_state est appelée par le getter de GameState et ne distribue rien.
Les sauvegardes sans version ou de version 1 sont également prises en charge.
Catégories, compteurs, preuve manuelle, identité de partie, historique des
paliers et preuves d'acquisition sont préservés.

| Reçu existant | Résultat |
|---|---|
| Hash payé | Une composante payée, aucun complément de la nouvelle définition |
| Hash en attente | Exactement sa promesse historique, toujours due |
| Array en attente | Une composante par récompense enregistrée |
| Lot partiellement normalisé | Les composantes payées restent payées |
| Lot globalement payé | Le statut global payé est autoritaire |
| Promesse manquante | Conservée en attente ; aucune récompense inventée |
| Migration répétée | État stable, sans gain ni notification |

Les données restent sérialisables par Marshal dans GameState, avec le sac et
l'argent. SaveLoadTweaks ne change pas.

## Collectionneur : les 18 seuils définitifs

**5, 15, 30, 50, 75, 105, 140, 180, 225, 275, 330, 390, 455, 525, 600, 680, 765, 855.**

Le compteur reste Pokedex#creature_caught : une espèce ne compte qu'une fois,
quelle que soit sa forme. La progression actuelle est relue, pas réinitialisée.

La correspondance se fait par ID publié species_N, jamais par index :
les IDs communs restent identiques ; les anciens reçus archivés de 50 et 75
sont réutilisés. Les seuils retirés 60/100/175/400/550/700 restent archivés,
hors du total visible, et leurs dettes sont honorées sans ancien bandeau.

Les autres nouveaux IDs sont de nouveaux objectifs indépendants. Ils peuvent
donner des récompenses rétroactives supplémentaires, explicitement distinctes
des paliers archivés ; aucun ancien ID n'est renommé ou repassé à pending.
Exemple testé : un ancien 60 en attente reçoit sa promesse de 17 $, tandis que
105 et 140 peuvent donner chacun leur nouvelle récompense de 100 $.

Récompenses existantes conservées pour 5/15/30/275 ; récompenses historiques
compatibles réutilisées pour 50/75. Les douze nouveaux objectifs reçoivent
**100 $ temporaires** chacun, à équilibrer dans Definitions. Aucun objet rare
ou nouveau type de récompense n'est introduit. Tout reçu sauvegardé prime sur
la définition actuelle.

## Navigation et graphismes

Style des maquettes : bleu nuit, crème, or, PokemonDS, cadre Message 12 et
trophée dédié. Les autres ressources graphiques et icônes ne sont pas modifiées.

Les catégories, succès et paliers ont des viewports réellement découpés.
Deux cartes, trois succès ou cinq paliers sont visibles ; seules ces lignes
sont instanciées. La scrollbar a un curseur proportionnel avec minimum 8 px,
des butées visibles et un index de sélection. La position est mémorisée au
retour et lors d'une réouverture dans la même scène.

Le détail comporte deux colonnes : objectifs à gauche, récompenses séparées
avec icône/nom/quantité/statut à droite. ←/→ parcourt les pages de deux
récompenses. ↑/↓ continue de parcourir les paliers. Un unique utilise un statut,
sans artificiel 1/1 ; secrets et récompenses cachées conservent leurs masques.

La popup reste non bloquante, séquentielle, suspendue lors des dialogues,
combats et panneaux incompatibles. Deux récompenses par page, 2,4 s de lecture
par page, au moins 3,5 s au total, fondus de 0,18 s et un seul son à l'ouverture.
Le bandeau courant est détaché lors d'un changement de scène, comme en V1 ;
les événements encore en file attendent le retour sur la carte.

## Captures définitives

| Écran | Capture |
|---|---|
| Catégories | [categories_unlocked.png](tests/categories_unlocked.png) |
| Liste des succès | [general_v1.png — rendu V2](tests/general_v1.png) |
| Détail avec deux objets | [tiers_23.png](tests/tiers_23.png) |
| Popup | [notification_tier.png](tests/notification_tier.png) |
| Menu avec trophée | [main_menu.png](tests/main_menu.png) |
| Asset trophée transparent | [trophy.png](../../graphics/interface/achievements/trophy.png) |

Contrôles supplémentaires :
[catégories supplémentaires](tests/categories_scroll.png),
[scroll milieu](tests/tiers_middle.png),
[palier 18](tests/tiers_scrolled.png),
[récompenses page 1](tests/rewards_page_1.png),
[page 2](tests/rewards_page_2.png),
[page 3](tests/rewards_page_3.png),
[lot partiellement payé](tests/detail_partial_payment.png),
[popup page 1](tests/popup_page_1.png),
[page 2](tests/popup_page_2.png),
[page 3](tests/popup_page_3.png),
[secret masqué](tests/secret_hidden.png),
[unique non obtenu](tests/unique_not_obtained.png),
[unique obtenu](tests/unique_obtained.png),
[popup unique](tests/notification_unique.png),
[popup catégorie](tests/notification_category.png),
[catégories verrouillées](tests/categories_locked.png),
[liste Chercheur](tests/researcher_23.png),
[liste défilée](tests/general_scrolled.png).

## Résultats exécutés

- **50 tests Succès, 513 assertions, aucun échec ni erreur** : les 49 tests acquis
  sont conservés, avec un test supplémentaire du mapping natif des commandes.
- **616 contrôles LiteRGSS réussis**, vraies textures/polices, captures 320×240,
  limites des textes/viewports, pagination, transparence, menu et destruction.
- **34 tests SaveLoadTweaks, 263 assertions, aucun échec**.
- Syntaxe des sept fichiers de production correcte sous Ruby Studio 3.0.6.
- Suite Noigrumes indépendante : 71 tests, 745 assertions, mêmes **1 échec et
  2 erreurs préexistants**, détaillés dans TEST_REPORT.

## Périmètre préservé et limites connues

Aucun script PSDK installé ni fichier de scripts/00000 Plugins n'est modifié.
Quêtes, métiers, Pokédex, SaveLoadTweaks, Noigrumes et autres systèmes gardent
leur implémentation. Les sources de progression et hooks existants sont
conservés ; le seul changement d'Integration concerne la texture Succès.

Le dépôt contient déjà des changements du créateur, dont données Studio,
cartes, TripleBattlePosition et Weather. Ils sont laissés en place ; le statut
Git global ne représente donc pas uniquement cette livraison.

La base actuelle contient 828 espèces hors __undef__ : le seuil demandé de
855 anticipe du contenu futur. Les tests 855/901 utilisent le Pokédex natif
alimenté avec des espèces de fixture, pas une partie réelle.

La manette physique, les cinématiques et le parcours complet dans le vrai jeu
restent à valider. Les tests exécutent les actions virtuelles et les mappings
natifs clavier/croix/stick/boutons ; ils ne certifient pas le matériel.
Le son est appelé et son nombre d'émissions est testé, sans écoute physique.
Les tests ne chargent aucune sauvegarde personnelle.

Les fichiers et captures sont intégrés à E:/Pokemon_ElementZ/Pokemon_ElementZ.
Le log INTEGRATION_CHECKS.txt atteste la nouvelle exécution des 50 tests et du
rendu natif depuis ce chemin, sans variable pointant sur la copie temporaire.

## Checklist manuelle courte

1. Charger une copie de sauvegarde ancienne ; comparer argent/sac et historique des reçus.
2. Naviguer au clavier puis à la manette : catégories, succès, 18 paliers et pages de récompenses.
3. Obtenir un lot avec un objet bloqué, sauvegarder/recharger, libérer la place et vérifier le paiement unique du reliquat.
4. Observer les pages et fondus de la popup ; ouvrir un dialogue, menu et combat pour vérifier la suspension.
5. Vérifier métier Chercheur, doublon d'espèce/forme, secret et unique.
6. Recharger puis rouvrir plusieurs fois : aucun nouveau paiement déjà reçu.

Le [README](README.md) contient les exemples complets de catégorie, succès,
palier, lot mixte, secret, compteur custom et changement de seuil.
[GIT_STATE.txt](GIT_STATE.txt) fournit git diff --stat, statut et inventaire.
Aucun commit automatique.
