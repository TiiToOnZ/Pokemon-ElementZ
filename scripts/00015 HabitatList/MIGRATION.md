# HabitatList — migration vérifiée sur PSDK 26.60

Le projet démarre avec PSDK **26.60**, et non 26.58 : le `version.txt` situé au-dessus du dossier réel de `psdk_scripts` contient `6716` (`0x1A3C`). `../psdk.bat` désigne le Ruby 3.0.6 livré par Pokémon Studio. Le lien `psdk_scripts` pointe vers `C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/pokemonsdk/scripts`. Le journal `../Error.log` du 23 septembre 2026 confirme cette version et la cause du crash.

Cette migration ajoute trois scripts custom et conserve le moteur. Le code complet est dans ces fichiers, chargés dans cet ordre :

| Fichier | Rôle |
| --- | --- |
| [54100 ZoneEncounterCatalog.rb](54100%20ZoneEncounterCatalog.rb) | Modèles de présentation et calcul des rencontres de la zone, sans écriture dans la sauvegarde. |
| [54200 ZoneEncounterPage.rb](54200%20ZoneEncounterPage.rb) | Composant `UI::Dex::ZoneEncounterPage` et scène enfant `GamePlay::ZoneEncounters`. |
| [54300 DexZoneExtension.rb](54300%20DexZoneExtension.rb) | `prepend` de deux méthodes : libellé de X et action de X dans la liste. |
| [54000 Dex_Zones.rb](54000%20Dex_Zones.rb) | Ancien script déjà entièrement commenté avant intervention ; conservé sans modification. |
| [tests/habitat_test.rb](tests/habitat_test.rb), [tests/support.rb](tests/support.rb) | Tests hors jeu ; le sous-dossier non numéroté n'est pas chargé par PSDK. |
| [tools/disable_legacy_archive.rb](tools/disable_legacy_archive.rb) | Opération reproductible de neutralisation de l'archive historique. Déjà exécutée. |
| [migration.patch](migration.patch) | Diff intégral de cette intervention, y compris les binaires et leur sauvegarde. |

## Diagnostic et points d'extension vérifiés

Tous les chemins ci-dessous sont relatifs à `scripts/`. Les numéros de ligne désignent les sources locales inspectées, pas une documentation d'une autre version.

| Couche | Fichier et lignes | API / rôle constaté |
| --- | --- | --- |
| Chargement de version | `psdk_scripts/tools/GameLoader/1_setupConstantAndLoadPath.rb:38` | Lecture de `version.txt`, puis conversion en chaîne de version. |
| Données du Pokédex | `psdk_scripts/4_Systems_101_Dex.rb:12` | `PFM::Pokedex`, déjà persistant dans `PFM::GameState`. |
| Statuts | même fichier, `149`, `177`, `206`, `218` | `mark_seen(db_symbol, form = 0, forced: false)`, `mark_captured(db_symbol, form = 0)`, `creature_seen?(db_symbol, form = false)`, `creature_caught?(db_symbol, form = false)`. Les formes sont des bits distincts. |
| Présentation | même fichier, `1185`, `1194` | `GamePlay::Dex::CreatureView` et `GamePlay::Dex::Presenter` : visibilité, listes, compteurs, formes et description. |
| Composants UI | même fichier, `335`, `361`, `392`, `414`, `459`, `516`, `643` | `UI::Dex::{FacePanel, SeenGot, InfoPanel, Button, MapPanel, CreaturePage, DexListComposition}`. Les compteurs passent par `update_counts` / `update_seen_got`. |
| Scène principale | même fichier, `797`, `811`, `938`, `951` | `GamePlay::Dex < BaseCleanUpdate::FrameBalanced` ; `initialize(pokedex = $pokedex)` ; `generate_selected_pokemon_array` **sans argument** ; états liste `0`, fiche `1`, carte `2`. |
| Commandes | même fichier, `866`, `1017`, `1079`, `1084`, `1112` | `button_texts`, actions **minuscules** `action_a/x/y/b`, touches et contrôles souris. X n'a aucune action en liste ; X change la forme en fiche et le zoom sur la carte. Y conserve filtre/cri/changement de carte. |
| Fiche seule | même fichier, `1351`, `1451` | `GamePlay::DexInfo`, distincte de `Dex`, enregistrée dans `GamePlay.dex_info_class`. Elle n'est pas modifiée. |
| Scène enfant | `psdk_scripts/4_Systems_000_General_2_GamePlay__Base.rb:168` | `call_scene` gère masquage, reprise de la scène parente et transitions. Le Pokédex conserve sa sélection. |
| Zone | `psdk_scripts/4_Systems_202_Environment.rb:55`, `103` | `Environment#update_zone`, `get_current_zone_data` (alias). Une carte non répertoriée peut laisser l'ancienne zone en mémoire : vérification de `Zone#maps`, puis recherche dans `each_data_zone` sans modifier l'environnement. |
| Modèles Studio | `psdk_scripts/3_Studio.rb:410`, `453`, `484`, `1528` | `Studio::Group`, `Group::CustomCondition`, `Group::Encounter`, `Studio::Zone`. `wild_groups` contient des Symbol ; `specie` est un Symbol et `form` un Integer. |
| Conditions et priorité | `psdk_scripts/4_Systems_999_Wild.rb:48`, `68`, `90`, `321` | Réduction de toutes les conditions avec `reduce_evaluate`, puis premier groupe correspondant à `[system_tag, terrain_tag, tool]`. Marche et pêche sont des contextes distincts. |
| Formes automatiques | `psdk_scripts/3_Studio.rb:510` | `Encounter#generic_form_generation` choisit parmi les formes `< 30` si `form == -1` et sans hook spécifique. Le catalogue énumère cet ensemble sans `sample`, sans `reject!` et sans fabriquer de Pokémon. |
| Images exactes | `psdk_scripts/4_Systems_000_General_1_PFM.rb:1303`, `1412` | `PFM::Pokemon.icon_filename` et `RPG::Cache.b_icon`. Le rendu consulte la forme Studio exacte sans `Pokemon#form=` (qui recalibre certaines espèces). |
| Fin de combat / capture | `psdk_scripts/5_Battle_04_Logic.rb:3126`, `3162` ; `psdk_scripts/5_Battle_01_Scene.rb:344` | Enregistrement natif du vu/capturé. Aucun hook de combat supplémentaire. |
| Chargement custom | `psdk_scripts/ScriptLoad.rb:80`, `91` | Répertoires numérotés et scripts de 3 à 5 chiffres ; chargement des scripts custom après PSDK. |

La casse immédiate de `Code collé.rb` est l'appel `generate_selected_pokemon_array(page_id)` à sa ligne 11. Le journal donne `ArgumentError: wrong number of arguments (given 1, expected 0)` dans le moteur à la ligne 938. L'initialisation ancienne ignore également le nouveau présentateur. Ensuite, `@frame`, `@list`, `@seen_got`, `@pokeface`, les méthodes `create_face`, `create_info`, et les actions majuscules ne correspondent plus à la composition et au routage actuels. `UI::DexSeenGot` a été remplacé par `UI::Dex::SeenGot` ; redéfinir l'ancien nom ne modifie pas les compteurs actuels. Les états 3/4 n'existent pas dans la scène actuelle.

La logique récupérable est la relation `Zone#wild_groups -> data_group -> Group#encounters` et la consultation des statuts natifs. La liste de toutes les zones visitées, le filtrage limité à la première condition, l'exclusion des interrupteurs 13/14 et le plafond de douze sprites ne sont pas repris. La nouvelle fonction concerne **la zone actuelle**.

## Comportement installé

Ouvrir le Pokédex, puis utiliser **X / Zone depuis la liste**. Il s'agit de la touche logique X de PSDK, donc de la touche clavier/manette configurée pour X.

- **Ensemble** : espèces/formes distinctes des premiers groupes actifs pour chaque contexte terrain/outil de la zone.
- **A ou droite** : groupe suivant ; **X ou gauche** : groupe précédent. Les groupes inactifs sont consultables, avec « Inactif : conditions non remplies » ou « Inactif : un autre groupe est prioritaire ».
- **Haut/bas ou molette** : page précédente/suivante, cinq entrées par page, sans plafond total.
- **Y** : retour à l'ensemble des milieux actifs.
- **B** : retour à la liste normale du Pokédex. Les quatre boutons du bas répondent aussi à la souris.

L'état vu/capturé vient **exclusivement du Pokédex global**, pour le couple espèce/forme. Un Pokémon vu dans une autre zone est révélé ici, mais voir une forme ne révèle pas automatiquement les autres. Un statut capturé révèle également l'entrée. Tant que l'entrée n'est ni vue ni capturée, seul `?` apparaît ; aucun nom, nom de forme ou sprite de cette entrée n'est demandé au moteur graphique. Les compteurs de cette page comptent les couples espèce/forme dédupliqués ; les compteurs natifs gardent leur définition et leur comportement habituels.

La liste représente les **possibilités des groupes Studio**, avec leur terrain et leur outil, pas une garantie de déclencher un combat sur la case où le joueur ouvre le menu. Par exemple, une rencontre à la canne exige toujours un lieu de pêche et la canne correspondante. Le catalogue ne simule ni un tirage aléatoire, ni le Repousse, ni les talents, ni l'accès physique aux cases. Les Pokémon errants ou les combats forcés par événements absents des groupes Studio ne sont pas ajoutés.

Toutes les conditions sont évaluées exactement par `Studio::Group::CustomCondition#reduce_evaluate`. Les interrupteurs horaires vérifiés dans `psdk_scripts/0_Dependencies.rb:436` sont `Yuki::Sw::TJN_DayTime = 11`, `TJN_NightTime = 12`, `TJN_MorningTime = 13`, `TJN_SunsetTime = 14`. Le catalogue n'utilise pas ces numéros en dur et ne change aucun interrupteur. Les conditions de carte et les interrupteurs custom 402/403 du projet sont conservés, avec la sémantique AND/OR du moteur.

Un groupe vide peut masquer un groupe suivant : c'est aussi le comportement du `find` du moteur. Les entrées de poids nul sont exclues. Les groupes référencés plusieurs fois et les couples espèce/forme répétés sont dédupliqués. Une référence de groupe, d'espèce ou de forme invalide est signalée au journal et n'est pas remplacée silencieusement par les données `__undef__` ou la forme 0.

Le catalogue est relu à l'ouverture et toutes les 250 ms pendant l'affichage ; la vue n'est redessinée que lorsque le résultat change. La zone, les résultats des conditions, les formes et les statuts font partie du résultat comparé. La réouverture après un combat utilise donc immédiatement le Pokédex mis à jour. La page ne fait pas avancer l'horloge du jeu : elle respecte les changements que PSDK applique réellement à ses conditions.

Les formes automatiques présentes dans les données du projet sont celles de Rattata, Racaillou, Sabelette, Taupiqueur et Prismillon. Elles n'utilisent pas de hook `FORM_GENERATION` spécifique et sont couvertes par l'énumération générique. Pour un futur groupe `form = -1` d'une espèce à génération spéciale, le catalogue signale une résolution nécessaire au lieu d'inventer ses formes possibles. `Catalog::FORM_RESOLVERS[db_symbol]` permet alors d'ajouter un calcul exact adapté à ce hook. Les formes explicites, y compris les deux formes de Mistigrix, restent prises telles quelles. Cette réserve ne concerne aucun groupe actuellement configuré.

Un suivi **par zone où le Pokémon a effectivement été rencontré** serait une autre fonctionnalité : il faudrait persister une table de couples espèce/forme par zone et enregistrer la zone de départ du combat. Le Pokédex global ne permet pas de reconstruire rétroactivement ce lieu. Cette variante n'est pas implémentée ; aucune nouvelle donnée de sauvegarde n'est introduite. Les effets custom qui modifient eux-mêmes le Pokédex restent reflétés tels quels (par exemple le script DexBall du projet marque une capture à l'utilisation de cette Ball).

## Ancien plugin et réversibilité

`scripts/HabitatList.psdkplug` contenait encore une copie active de l'ancien script, même si le fichier custom était commenté et l'ancienne extraction supprimée. `PluginManager#load_plugins` aurait pu la réextraire lors d'un changement de plugins ou de version.

L'archive a été conservée dans **`scripts/HabitatList.psdkplug.disabled`**, bit pour bit, puis sa version installée a été reconstruite avec le script historique commenté. Toutes ses ressources et métadonnées fonctionnelles restent identiques ; seule la source Ruby et sa signature SHA-512 changent. La signature a été validée par `PluginManager::LoadedPlugin` avant remplacement. Le suffixe `.disabled` exclut la copie originale de la recherche `*.psdkplug` du gestionnaire.

SHA-256 de l'archive originale sauvegardée : `12f2c54b439af2b3d21311420aed8eb8bf614d399f7933076fff25f0b316cd73`.

`plugins.dat` et les autres plugins n'ont pas été modifiés par cette intervention. Ses modifications Git déjà présentes sont celles de l'état initial. Aucun moteur PSDK, JSON Studio, CSV, carte ou fichier de sauvegarde n'a été modifié. Aucun commit n'a été créé. Les nombreux changements préexistants du projet sont conservés.

Le diff inclut seulement les fichiers créés ici et la neutralisation de l'archive. Il exclut le fichier historique déjà commenté, préexistant et inchangé. Depuis la racine du projet, il est vérifiable avec :

```powershell
git apply --reverse --check 'scripts/00015 HabitatList/migration.patch'
```

Pour annuler immédiatement toute cette intervention après avoir vérifié ce résultat :

```powershell
git apply --reverse 'scripts/00015 HabitatList/migration.patch'
```

Attention au sens de cette annulation : elle restaure aussi l'archive historique incompatible. Si elle est réextraite ensuite, elle peut réintroduire le crash. Pour **désactiver seulement la nouvelle page** et garder le Pokédex natif fonctionnel, renommer simplement `54300 DexZoneExtension.rb` en `54300 DexZoneExtension.rb.disabled` suffit ; laisser l'archive neutralisée.

## Ressources et configuration Studio

Aucune nouvelle image et aucune nouvelle entrée CSV ne sont nécessaires. Le composant emploie `UI::GenericBase`, déjà utilisé par le Pokédex, donc les ressources communes existantes `graphics/interface/team/fond.png`, `graphics/interface/tcard/button_background.png`, `graphics/pokedex/buttons.png`, `graphics/pokedex/key_short.png` (et les variantes de raccourcis prévues par PSDK). Les sprites d'espèces proviennent des noms configurés dans `CreatureForm#resources`, sous `graphics/pokedex/pokeicon/`, via le cache `b_icon`.

Une icône d'espèce manquante laisse le nom et le statut visibles ; une erreur de chargement de cette icône est interceptée et journalisée. Aucun `WinZone`, icône de terrain, `daytime`, `nighttime` ou image `000` spécifique à l'ancien plugin n'est requis par cette page. Les ressources communes du Pokédex natif restent naturellement nécessaires à son ouverture.

Les nouveaux libellés français sont dans les trois scripts : « Zone », « Suivant », « Précédent », « Ensemble », « Retour », états actif/inactif et messages de données manquantes, compteurs « Vus »/« Capturés », « Vu »/« Capturé », `?`, ainsi que les noms des terrains et outils. Les noms de zones, espèces et formes utilisent les textes Studio existants. Pour localiser l'extension dans une autre langue, remplacer ces libellés par des entrées de texte du projet ; aucune modification de texte n'est requise pour l'usage français actuel.

Dans Studio, aucune reconfiguration n'est requise pour les groupes existants. Pour ajouter des rencontres, rattacher la carte à sa zone, rattacher les groupes à cette zone **dans l'ordre de priorité voulu**, puis renseigner terrain système, terrain numérique, outil, conditions et espèces/formes. Conserver ou choisir `-1` uniquement quand la génération automatique est souhaitée. Sauvegarder les données avec Studio pour actualiser la base compilée normale.

## Vérifications et limites

Commande depuis `scripts/` :

```powershell
ruby '.\00015 HabitatList\tests\habitat_test.rb'
```

Résultat : **25 tests, 983 assertions, zéro échec, zéro erreur**, sous Ruby 3.1.2 du poste et sous **Ruby 3.0.6 livré avec Studio**. Le Ruby Studio n'embarque pas Minitest ; sa vérification a utilisé la bibliothèque Ruby pure Minitest 5.15.0 déjà installée sur le poste, sans téléchargement ni installation :

```powershell
& 'C:\Users\thiba\AppData\Local\Programs\pokemon-studio\resources\psdk-binaries\ruby.exe' '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' '.\00015 HabitatList\tests\habitat_test.rb'
```

Le banc charge les vraies classes Studio, `PFM::Pokedex`, `PFM::Wild_Battle`, `GamePlay::Dex` et son présentateur depuis les sources locales, ainsi que le vrai `Data/Studio/psdk.dat`. Il vérifie toutes les cartes des zones locales aux quatre horaires et la concordance JSON/base compilée des configurations de zones et de groupes. Les primitives graphiques/audio/entrée, le changement de scène et l'objet Pokémon d'affichage sont simulés. Le test de sauvegarde est un aller-retour `Marshal` du véritable `PFM::Pokedex` dans un état de jeu de test, pas l'ouverture d'un fichier de sauvegarde joueur.

| Cas demandé | Vérification automatisée effectuée | Essai en jeu restant |
| --- | --- | --- |
| Ouverture du Pokédex | Initialisation native et création de l'écran complémentaire dans le banc ; X en liste | Ouvrir depuis le menu et vérifier le rendu/transitions. |
| Zone courante | Données réelles, changement de carte, cache de zone périmé | Ouvrir dans deux zones différentes. |
| Pokémon inconnu | `?`, aucune résolution de nom/forme ni chargement d'image | Contrôler visuellement une entrée jamais vue. |
| Vu après combat | Appel réel `mark_seen(..., forced: true)`, rafraîchissement de la page | Jouer un combat puis rouvrir le Pokédex. |
| Capturé | `mark_captured`, statut, compteurs | Capturer puis vérifier « Capturé ». |
| Jour/nuit/matin/soir | Conditions natives pour les quatre interrupteurs | Changer l'horaire selon le fonctionnement normal du projet. |
| Pêche | Outils distincts et priorité comparée au vrai `any_fish?` | Vérifier les trois cannes et leurs milieux. |
| Formes | Formes explicites, formes automatiques, Mistigrix, statuts par forme | Vérifier les sprites et textes des formes du projet. |
| Groupes vides / zone inconnue | Absence de division par zéro, navigation et messages | Ouvrir depuis une zone vide / une carte sans zone. |
| Doublons / plus de douze entrées | Déduplication, pagination sur les formes de Prismillon | Parcourir les pages au clavier, à la manette et à la souris. |
| Sauvegarde/rechargement | Sérialisation des statuts existants, aucune donnée ajoutée | Sauvegarder réellement, quitter, recharger puis rouvrir. |
| Retour au Pokédex normal | Deux méthodes étendues seulement ; délégation X fiche/carte ; `DexInfo` inchangé | B vers la liste, filtre Y, fiche, formes, cri, carte, zoom, compteurs et fermeture. |
| Ressource absente | Icône absente : nom conservé, fermeture toujours possible | Contrôler l'apparence du remplacement sans icône. |

Les essais visuels et les parcours complets de jeu ci-dessus **n'ont pas été exécutés**. Les tests automatisés ne sont pas présentés comme une validation du rendu LiteRGSS, du chargement complet de tous les plugins ou du cycle réel combat/sauvegarde.
