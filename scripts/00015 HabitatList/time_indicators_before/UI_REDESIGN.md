# Interface HabitatList — grille et ajustements

Cette note décrit l'interface actuelle. `MIGRATION.md` et `migration.patch` documentent l'étape antérieure de migration, avec son ancienne liste.

## Périmètre

Seul `54200 ZoneEncounterPage.rb` change dans le code chargé par le jeu. Les tests et les outils d'aperçu sont adaptés. Le catalogue `54100`, l'extension X → Zone `54300`, le script historique `54000`, les archives du plugin, `plugins.dat`, les données Studio et les ressources graphiques restent inchangés par cette refonte.

## Ressources examinées

- Résolution logique : **320 × 240**, agrandissement configuré ×2 ; les dimensions ci-dessous sont en pixels du jeu.
- `graphics/pokedex/pokefront` contient des PNG statiques de **96 × 96** et des GIF d'animation de dimensions variables. La page utilise les PNG via `RPG::Cache.poke_front`, dont le chargeur `Texture` prend en charge les PNG. Elle n'utilise ni `b_icon` ni le découpage des icônes de stockage.
- `PFM::Pokemon.front_filename(espèce, forme, false, false, false)` résout les ressources de la forme Studio exacte, sans construire un Pokémon et sans recalculer sa forme. Exemple : Mistigrix forme 1 → `0678_01.png`.
- Pour une entrée inconnue, aucun nom ni fichier d'espèce n'est résolu : seul **`pokefront/000.png`** est chargé. Il mesure 96 × 96, avec un contenu visible de 62 × 62. Il est distinct du `pokedex/000.png` situé un niveau plus haut.
- L'indicateur natif du Pokédex est **`graphics/pokedex/catch.png`**, 16 × 16, chargé par le même identifiant `Catch` que le Pokédex PSDK. Aucun asset créé ou modifié.
- Le composant `UI::PokemonFaceSprite` gère des origines et animations propres aux fiches ; la grille utilise des `Sprite` simples dans un `SpriteStack`. Le fond et les boutons restent ceux de `GenericBase`.
- Les API locales `Bitmap#to_png`, `Image.new(bytes, true)` et `Image#get_pixel_alpha` permettent de mesurer les marges transparentes une seule fois par texture et par ouverture. L'image temporaire est libérée ; les textures partagées du cache restent intactes.

## Disposition

| Élément | Position / taille logique |
| --- | --- |
| Nom de zone | x=8, y=0, largeur 304, hauteur 16 |
| Ensemble / environnement | x=8, y=16, largeur 304, hauteur 16 |
| Disponibilité / données incomplètes | x=8, y=32, largeur 304, hauteur 16 |
| Grille | **4 colonnes × 3 lignes**, 12 entrées ; x=8..311, y=52..191 |
| Pas des emplacements | **76 × 46** ; centres x=46/122/198/274, y=75/121/167 |
| Compteurs Vus / Capturés | x=8, y=192, largeur 218, hauteur 16 |
| Numéro de page | x=230, y=192, largeur 82, hauteur 16 |
| Bandeau des commandes | y=214 ; boutons à y=219 |

`SpriteStack#add_text` applique le décalage natif FOY=2 : le code fournit donc y+2 pour ces textes.

Les sprites gardent **zoom_x = zoom_y = 1**, sans découpe ni déformation. Le contenu opaque est centré dans l'emplacement, puis décalé si nécessaire pour rester dans la zone de grille. Les marges transparentes peuvent dépasser cette zone sans masquer le texte. Les sujets volumineux passent derrière les petits lorsque leurs silhouettes se chevauchent. La petite Ball reste au premier plan, en bas à droite de l'emplacement.

Les compteurs portent sur tous les couples espèce/forme de la sélection, pas seulement la page visible. « Ensemble » conserve l'union dédupliquée des groupes actifs fournie par le catalogue. Aucun nom, statut individuel ou liste d'habitats n'est ajouté sous les sprites.

## Fusion des environnements

Le catalogue distingue les contextes de rencontre par `[system_tag, terrain_tag, tool]` pour reproduire la priorité native de PSDK. L'ancienne navigation affichait chaque groupe de ce catalogue séparément.

Cas réel de la Grotte cristalline, carte 29, `zone_22` :

| Groupe | system_tag | terrain_tag | vs_type | Outil / condition |
| --- | --- | --- | --- | --- |
| group_35 | cave | 0 | simple | aucun / map_id=29 |
| group_55 | cave | 1 | double | aucun / map_id=29 |
| group_56 | cave | 2 | triple | aucun / map_id=29 |

L'adaptateur de présentation regroupe les variantes par **system_tag + outil + séquence exacte de conditions (type, valeur, relation) + statut actif/inactif/masqué**. `terrain_tag` et `vs_type` ne divisent plus la présentation d'un même environnement. Le nom affiché n'intervient pas dans cette décision.

Ces trois groupes deviennent une seule **Grotte de 12 couples espèce/forme**, incluant les formes de Racaillou et Sabelette, sans tripler les entrées ni les statistiques. La fusion conserve l'ordre de première apparition. Elle travaille sur une copie de la présentation, sans modifier les groupes ni la sélection de combat.

Les system tags distincts, les outils distincts et les conditions distinctes restent séparés. Les horaires usuels sont nommés dans l'en-tête. Un groupe masqué n'est pas fusionné avec un groupe actif ; un groupe inactif reste consultable avec son indication. « Groupe actif · selon terrain / outil » n'affirme pas une disponibilité sur la case du joueur.

### Audit du caractère générique

La règle est générique : aucun test sur `:cave`, `Grotte`, un préfixe de nom ou une liste d'environnements autorisés ne décide de la fusion. `TERRAIN_NAMES` et `TOOL_NAMES` servent uniquement à traduire les libellés. Un system tag absent de ces tables est également regroupé, et utilise son identifiant comme libellé.

Deux exemples réels supplémentaires :

- `zone_32`, carte 36 : Herbes `group_39` (terrain 0/simple), `group_32` (terrain 1/double) et `group_46` (terrain 2/triple), tous sans outil et avec la même condition, donnent **une sélection Herbes de 35 couples espèce/forme**. Chenipotte commun aux trois groupes n'apparaît qu'une fois ; les 20 formes de Prismillon restent distinctes. Ses 35 entrées occupent plusieurs pages de grille.
- `zone_7`, carte 8 : Herbes `group_15` et `group_17` fusionnent malgré deux terrains numériques différents et le même format simple. Les Hautes herbes `group_16`, de system tag distinct, restent séparées.

**Limite actuelle : cette règle n'est pas strictement « un environnement = une seule sélection », indépendamment des conditions et statuts.** Elle conserve des sélections distinctes pour ces différences. Exemple réel : dans `zone_25` (carte 35), `group_36` simple et `group_34` triple fusionnent, mais `group_33` double reste une seconde sélection Herbes : sa condition est carte 35 OU carte 36, contre carte 35 seule pour les deux autres. Le résultat vrai des conditions ne suffit pas : leur séquence doit être identique. De même, les Hautes herbes actives et masquées de `zone_5` restent deux sélections.

Cet audit n'a pas modifié le code d'affichage. Une fusion stricte par milieu/méthode, avec disponibilité détaillée à l'intérieur d'une seule sélection, nécessiterait un changement supplémentaire de présentation ; ce n'est pas le comportement actuel.

### Catégories présentes dans les données actuelles

Inventaire de la base compilée du jeu : **59 groupes distincts rattachés à 43 zones**, soit **13 catégories milieu/méthode** possibles en plus d'Ensemble. Les quatre groupes non rattachés (`group_40`, `group_41`, `group_45`, `group_48`) n'ajoutent aucune catégorie supplémentaire.

| system_tag | tool | Libellé de catégorie |
| --- | --- | --- |
| grass | aucun | Herbes |
| tall_grass | aucun | Hautes herbes |
| cave | aucun | Grotte |
| sand | aucun | Sable |
| regular_ground | aucun | Sol |
| pond | aucun | Lac |
| sea | aucun | Mer |
| pond | old_rod | Pêche · Canne / Lac |
| pond | good_rod | Pêche · Super Canne / Lac |
| sea | old_rod | Pêche · Canne / Mer |
| sea | good_rod | Pêche · Super Canne / Mer |
| headbutt | headbutt | Coup de Boule / Arbres |
| cave | rock_smash | Éclate-Roc / Grotte |

Les libellés Herbes peuvent également être suffixés **Matin, Jour, Soir ou Nuit** selon les groupes configurés. On obtient donc 17 libellés distincts d'environnement, hors Ensemble, en comptant ces suffixes. Le nombre de sélections d'une zone dépend aussi des conditions et statuts séparés décrits ci-dessus ; ce tableau n'annonce pas 13 sélections dans chaque zone.

Les rencontres aquatiques sans outil, que le joueur associe à Surf, sont nommées **Lac** ou **Mer** par cette interface. Il n'y a pas de catégorie littérale « Surf » dans les groupes rattachés actuels. Elles restent séparées de la pêche via `tool = nil` contre `old_rod`/`good_rod`. Montagne, Herbes denses et Méga Canne figurent dans les traductions possibles mais ne sont pas utilisées par ces groupes actuels.

## Commandes conservées

- **Suivant** (A / droite) et **Précédent** (X / gauche) parcourent les sélections en boucle : Ensemble → environnements. Chaque changement revient à la première page.
- **Haut / bas** et **molette** parcourent uniquement les pages de la sélection courante, en boucle.
- **Ensemble** (Y) revient à Ensemble, page 1.
- **Retour** (B) referme cette scène et retrouve le Pokédex.

## Vérifications

Les **38 tests, 1 336 assertions** passent sous Ruby 3.1.2 et sous **Ruby 3.0.6 livré avec Studio**. Les anciens tests de logique sont conservés ; les attentes d'interface suivent la grille de 12 cases. La syntaxe du script est aussi vérifiée sous Ruby Studio.

Le banc vérifie notamment les groupes réels 35/55/56, une union de groupes à contenus différents, la déduplication espèce/forme, les trois états inconnu/vu/capturé, les formes de Mistigrix, les douze cases occupées, les pages supplémentaires, les marqueurs réutilisés, la navigation, les conditions, les priorités et l'absence de mutation du catalogue et des données. Les tests de logique des rencontres, de sauvegarde et d'intégration au Pokédex restent exécutés.

L'audit ajoute le cas réel Herbes 39/32/46, avec déduplication, formes, pagination et navigation, puis un test paramétré des variantes simple/double/triple pour chacune des 13 catégories du projet. Un system tag fictif absent des traductions et des noms affichés volontairement différents prouvent aussi que le regroupement ne dépend pas d'une liste autorisée ou des libellés. Les groupes de ce test paramétré sont construits uniquement en mémoire ; les données du projet restent intactes.

Depuis `scripts/` :

```powershell
ruby '.\00015 HabitatList\tests\habitat_test.rb'
& 'C:\Users\thiba\AppData\Local\Programs\pokemon-studio\resources\psdk-binaries\ruby.exe' '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' '.\00015 HabitatList\tests\habitat_test.rb'
```

Cinq aperçus **320 × 240**, examinés avec les véritables images et polices du projet, sont dans `ui_previews/`. Ils couvrent les 15 entrées de Prairie ruisselante, une sélection masquée, la Grotte fusionnée, Wailord, Méga-Steelix, Mistigrix forme 1, Prismillon et un inconnu. Le contrôle des pixels vérifie l'échelle native, l'absence de pixels opaques hors de la grille et l'absence de sprite ou de marqueur entièrement masqué dans ces cinq cas.

Pour les régénérer sans modifier les données du jeu :

```powershell
& '.\00015 HabitatList\tests\render_grid_preview.ps1' -PrepareBounds
ruby '.\00015 HabitatList\tests\grid_preview.rb'
& '.\00015 HabitatList\tests\render_grid_preview.ps1'
& '.\00015 HabitatList\tests\check_grid_preview.ps1'
```

Ces aperçus utilisent System.Drawing et des primitives simulées, **pas une capture du moteur LiteRGSS**. La présence de pixels visibles ne suffit pas à garantir à elle seule l'identification confortable de toutes les silhouettes. Il reste à contrôler en jeu : lisibilité des chevauchements sur les trois lignes, placement et association des Balls, rendu des textes et touches réellement mappées, défilement des pages et retour X → Zone → B. Aucun nouveau parcours visuel dans le jeu n'a été exécuté pour ces ajustements.

## Diff réversible

`ui_adjustments.patch` contient les ajustements depuis la grille à deux lignes approuvée : code, tests et outils/documentation. Sa base est conservée dans `ui_adjustments_before/`.

Depuis la racine du projet, vérifier puis annuler **ces derniers ajustements uniquement** :

```powershell
git apply --reverse --check 'scripts/00015 HabitatList/ui_adjustments.patch'
git apply --reverse 'scripts/00015 HabitatList/ui_adjustments.patch'
```

`ui_redesign.patch` est une autre possibilité : il contient l'ensemble de la refonte visuelle depuis la liste initiale de la migration, avec la base `ui_redesign_before/`. **Ne pas appliquer les deux inversions successivement** : choisir le point de retour souhaité. Les patches excluent les PNG/JSON d'aperçu régénérables et les dossiers de sauvegarde ; ceux-ci restent disponibles après annulation. Les deux vérifications inverses ont été exécutées sans modifier les fichiers actifs.

Les changements préexistants du projet restent conservés. Les anciens patches de migration correspondent à leurs étapes historiques ; revenir directement à cette étape exige d'abord d'annuler la refonte complète avec `ui_redesign.patch`.
