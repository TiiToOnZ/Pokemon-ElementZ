# HabitatList — environnements et préférences horaires

Cette note décrit la version actuelle. `MIGRATION.md` décrit la migration historique. Les dossiers `ui_redesign_before`, `ui_adjustments_before`, `time_indicators_before` et `tjn_access_before` conservent les étapes antérieures.

## Périmètre

Seul `54200 ZoneEncounterPage.rb` change dans le code exécuté par le jeu. Le catalogue `54100`, l'intégration X → Zone `54300`, le script historique `54000`, les archives du plugin, `plugins.dat`, les fichiers graphiques et les données Studio ne sont pas modifiés par cette intervention. Les tests, outils d'aperçu et cette note sont adaptés.

## Environnements et agrégation

Une seule sélection est créée par **`[system_tag, tool]`**, sans utiliser le nom affiché. `terrain_tag`, `vs_type`, les horaires, les autres conditions et les statuts ne créent plus de sélections supplémentaires. Les membres originaux et leurs statuts restent accessibles dans la présentation et inchangés dans le catalogue. La scène n'annonce plus « actif » pour une sélection mixte ; les conditions non temporelles ne sont pas affichées.

Les entrées sont dédupliquées par **`[espèce, forme]`** avant les compteurs et l'affichage. Les groupes inactifs ou masqués restent consultables dans cette union configurée ; les horaires ne promettent pas une disponibilité immédiate. Le moteur conserve ses conditions et sa priorité de sélection habituelles.

Exemples réels vérifiés : Grotte cristalline, carte 29, groupes 35/55/56 → 12 couples ; Herbes carte 36, groupes 39/32/46 → 35 couples ; Herbes carte 35, groupes 36/33/34 → 21 couples malgré des conditions de carte différentes. Les Hautes herbes actives et masquées de Prairie ruisselante sont désormais réunies.

« Ensemble » conserve l'union des groupes **actifs** fournie par le catalogue, ses compteurs et les Balls, sans indicateur horaire individuel. Les sélections d'environnement réunissent tous leurs groupes configurés.

Catégories actuelles : Herbes, Hautes herbes, Grotte, Sable, Sol, Lac, Mer, Pêche · Canne / Lac, Pêche · Super Canne / Lac, Pêche · Canne / Mer, Pêche · Super Canne / Mer, Coup de Boule / Arbres, Éclate-Roc / Grotte. Les horaires ne sont plus des suffixes créant des sélections différentes.

## Préférence horaire

Les quatre périodes originales sont conservées : Matin = interrupteur 13, Jour = 11, Soir = 14, Nuit = 12. Seules ces conditions typées `enabled_switch` sont temporelles. Une condition de carte de valeur 11 n'est pas un horaire ; les interrupteurs de scénario 402/403 non plus.

La présentation projette les restrictions temporelles en conservant l'ordre AND/OR, puis réunit les périodes de toutes les occurrences d'un même couple espèce/forme. Les autres prérequis sont supposés satisfaits pour cette projection uniquement ; ils restent évalués normalement par le catalogue et le moteur. Sans restriction horaire, un groupe contribue aux quatre périodes. Aucun interrupteur de jeu n'est modifié pour ce calcul.

| Périodes distinctes après union | Indicateur |
| --- | --- |
| Davantage de périodes Matin/Jour | `daytime` |
| Davantage de périodes Soir/Nuit | `nighttime` |
| Autant dans chaque famille, ensemble non vide | Les deux |

Cela couvre les 15 ensembles non vides : une seule période donne sa famille ; une paire croisée donne les deux ; trois périodes donnent la famille majoritaire ; **les quatre périodes donnent les deux**. Aucune pondération par taux de rencontre, nombre de groupes ou durée en heures. Aucune lettre M/J/S/N affichée.

Un inconnu affiche uniquement `pokefront/000.png`, sans résolution de nom ou de sprite d'espèce, ni Ball ni horaire individuel. Un Pokémon vu affiche son sprite et sa préférence ; un capturé ajoute la Ball.

## Ressources et disposition 320 × 240

Les fronts statiques sont résolus par `PFM::Pokemon.front_filename`, puis `RPG::Cache.poke_front`, avec la forme Studio exacte. `b_icon` n'est pas utilisé. Les PNG actuels sont en 96 × 96 ; leurs marges transparentes sont mesurées via `Bitmap#to_png`, `Image.new` et `get_pixel_alpha`, puis mises en cache par ouverture. Aucun pixel du Pokémon n'est découpé ou redimensionné.

Ressources existantes réutilisées sans modification :

- `graphics/pokedex/pokefront/000.png` : 96 × 96, contenu visible 62 × 62.
- `graphics/pokedex/catch.png` : 16 × 16, identifiant de cache natif `Catch`.
- `graphics/pokedex/daytime.png` : 32 × 18, soleil visible sur x=7..25.
- `graphics/pokedex/nighttime.png` : 32 × 18, lune étoilée visible sur x=10..22.

L'ancien HabitatList commenté utilisait les icônes pour Jour et Nuit seuls. La convention élargie aux familles Matin/Jour et Soir/Nuit est celle validée pour cette interface.

| Élément | Position / dimensions réelles |
| --- | --- |
| Zone / sélection | x=8, y=0 / 16 ; largeur 304 |
| Légende d'Ensemble | y=32..49 ; soleil x=8, lune x=164 |
| Textes de légende | x=40 / 196, y=32, largeur 116 ; police native 20 |
| Grille | **4 × 3**, 12 entrées ; x=8..311, y=52..191 |
| Pas des cases | 76 × 46 ; centres x=46/122/198/274, y=75/121/167 |
| Compteurs / pagination | y=192..207 |
| Bandeau / boutons | y=214 / 219 |

Le code fournit y+2 aux textes car `SpriteStack#add_text` applique FOY=2. Fond et boutons natifs conservés ; texte noir.

Tous les sprites restent à **1:1**. Les grands Pokémon passent derrière les petits lors des chevauchements. Pour une case d'origine `(x,y)`, les horaires sont à y+28 et la Ball à y+30. Avec deux horaires : Ball x+16, soleil x+26, lune x+44. Seules leurs marges transparentes se chevauchent ; les pixels visibles sont côte à côte. Avec un seul horaire : Ball x+34 et horaire x+44. Sans horaire, notamment dans Ensemble, la Ball conserve x+56.

La légende d'Ensemble montre les vraies ressources et « Matin/Jour HH:MM–HH:MM » / « Soir/Nuit HH:MM–HH:MM ». Une alerte de données incomplètes remplace exceptionnellement cette légende dans la même bande.

## Horaires TJN réellement utilisés

La scène lit **`PFM.game_state.tint_time_set`**, puis **`Yuki::TJN::TIME_SETS[réglage] || Yuki::TJN::TIME`** et copie le tableau retourné. Il s'agit de l'accesseur public du réglage et des constantes publiques de configuration, avec le même repli que le moteur. Aucune heure n'est recopiée en dur. La légende se rafraîchit si le réglage change, même si les rencontres restent identiques.

### Correction du crash à l'ouverture de Zone

Dans PSDK 26.60, `current_time_set` est définie dans `class << self; private` : c'est une méthode singleton privée, pas un getter public. Le bloc `module_function` situé plus haut ne s'applique pas aux définitions de ce bloc singleton. La copie moteur locale, la copie du projet sous `00001 Scene_Title` et le moteur installé de Studio présentent la même définition et la même visibilité.

Les méthodes publiques propres à TJN sont `init_variables`, `update`, `force_update_tone`, `current_tone` et `update_timed_events`. Aucune ne retourne les seuils horaires. Les méthodes publiques `PFM::Environment#morning?`, `day?`, `sunset?`, `night?` donnent des booléens d'état courant, pas les heures de début/fin.

Le moteur récupère son réglage via `PFM.game_state.tint_time_set` (`GameState` expose un `attr_accessor`, nil signifiant le défaut). Son `update_tone_internal` appelle `current_time_set` depuis le module, sans récepteur explicite, puis compare l'heure aux seuils dans l'ordre Nuit/Soir/Jour/Matin. Aucune autre API publique de lecture des seuils n'a été trouvée dans ces sources. Pour un script extérieur, la correction utilise donc les données de configuration publiques ci-dessus, sans `send`, sans modification de visibilité et sans changer TJN.

Le premier banc de tests extrayait la méthode isolément et lui appliquait `module_function`, ce qui la rendait publique par erreur. Le banc charge maintenant le **module TJN complet**, avec les déclarations de visibilité originales ; seuls les objets graphiques Tone et le support Spriteset_Map sont remplacés. Le test de régression a reproduit le même NoMethodError, via `create_graphics → refresh_catalog → schedule`, avant correction. Il vérifie ensuite l'ouverture avec nil, default, les quatre saisons, platinum_daynight et un identifiant inconnu, la conservation de la visibilité privée et l'absence de mutation des constantes. Aucun changement visuel n'accompagne cette correction.

Un événement de `Data/Map002.rxdata` sélectionne `:platinum_daynight`. Ce nom existe dans les teintes, mais pas dans `TIME_SETS` : le TJN utilise alors son repli natif `TIME`, identique à default/summer.

| Réglage TJN | Matin | Jour | Soir | Nuit |
| --- | --- | --- | --- | --- |
| default / summer ; repli platinum_daynight | 07:00–11:00 | 11:00–19:00 | 19:00–22:00 | 22:00–07:00 |
| winter | 10:00–12:00 | 12:00–16:00 | 16:00–17:00 | 17:00–10:00 |
| fall / spring | 09:00–11:00 | 11:00–17:00 | 17:00–19:00 | 19:00–09:00 |

La légende par défaut est **Matin/Jour 07:00–19:00** et **Soir/Nuit 19:00–07:00**, cette dernière plage traversant minuit. Seuils inclus au début et exclus à la fin, comme dans le moteur.

## Navigation

Suivant (A/droite) et Précédent (X/gauche) parcourent Ensemble et les environnements en boucle, avec retour à leur première page. Haut/bas et molette parcourent les pages de la sélection courante. Ensemble (Y) revient à Ensemble page 1 ; Retour (B) retrouve le Pokédex.

## Tests et aperçus

Résultat après correction de l'accès TJN, sous Ruby 3.1.2 et Ruby Studio 3.0.6 : **44 tests, 1 500 assertions, zéro échec/erreur, aucun test ignoré**. `Data/Studio/psdk.dat` est de nouveau présent et la comparaison JSON/cache compilé a été exécutée. Lorsqu'il manque, comme pendant l'étape précédente, le banc utilise les JSON via Studio2PSDK **en mémoire seulement**, sans écrire de cache, et signale explicitement que seule la comparaison avec le cache manque.

Les tests couvrent les 15 combinaisons horaires, l'union sans pondération par doublons, les conditions non temporelles, l'absence d'horaires pour les inconnus et dans Ensemble, la réutilisation des cases, les formes, compteurs, catégories génériques, navigation, données réelles et changement de réglage TJN. Les anciens tests de logique et d'intégration X restent exécutés ; les attentes d'affichage suivent la fusion par milieu/méthode.

Depuis `scripts/` :

```powershell
ruby '.\00015 HabitatList\tests\habitat_test.rb'
& 'C:\Users\thiba\AppData\Local\Programs\pokemon-studio\resources\psdk-binaries\ruby.exe' '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' '.\00015 HabitatList\tests\habitat_test.rb'
```

Six aperçus actuels sont décrits dans `ui_previews/draw_commands.json` : `ensemble_1`, `ensemble_2`, `milieu_fusionne`, `formes_et_inconnu`, `horaires_et_capture`, `grotte_fusionnee`. Les autres images éventuellement présentes sont historiques. Le contrôle des pixels vérifie taille native, absence de débordement, absence de sprite entièrement masqué et absence de recouvrement entre les pixels des Balls et indicateurs horaires.

```powershell
& '.\00015 HabitatList\tests\render_grid_preview.ps1' -PrepareBounds
ruby '.\00015 HabitatList\tests\grid_preview.rb'
& '.\00015 HabitatList\tests\render_grid_preview.ps1'
& '.\00015 HabitatList\tests\check_grid_preview.ps1'
```

Ces aperçus System.Drawing utilisent les vrais assets et polices, mais **ne sont pas des captures LiteRGSS**. Restent à contrôler en jeu : lisibilité et association des indicateurs sur les trois lignes, police de légende, chevauchement des grands sprites, changements de milieu/page et retour au Pokédex. La scène n'a pas été lancée dans le jeu pendant cette intervention.

## Diff réversible

**`tjn_access.patch`** isole cette correction du crash et les tests/documentation associés, avec la base `tjn_access_before/`. Son inverse restaure la version qui plante ; il sert à la revue et à un retour arrière explicite. Vérification depuis la racine : `git apply --reverse --check 'scripts/00015 HabitatList/tjn_access.patch'`.

**`time_indicators.patch`** annule uniquement cette étape, à partir de `time_indicators_before/`. Depuis la racine du projet :

```powershell
git apply --reverse --check 'scripts/00015 HabitatList/time_indicators.patch'
git apply --reverse 'scripts/00015 HabitatList/time_indicators.patch'
```

Deux autres points de retour sont actualisés : `ui_adjustments.patch` revient à la grille à deux lignes approuvée ; `ui_redesign.patch` revient à la liste initiale de la migration. Choisir un seul patch, ne pas appliquer leurs inversions successivement. Les quatre vérifications inverses ont été effectuées sans annuler les fichiers actifs. Les aperçus régénérables et dossiers de sauvegarde sont exclus des patches.
