# HabitatList — catégories horaires et bandeaux

## Périmètre

Seul `54200 ZoneEncounterPage.rb` change dans le code exécuté par le jeu. Le catalogue `54100`, l'intégration X → Zone `54300`, le script historique `54000`, les archives du plugin, `plugins.dat`, les PNG et les données Studio ne sont pas modifiés par cette intervention. Les tests, outils d'aperçu et cette note sont adaptés.

## Environnements et ordre d'affichage

La fusion reste générique par **`[system_tag, tool]`**, sans reconnaître un nom comme Grotte. Terrain technique, combat simple/double/triple et conditions ne créent pas de pages d'environnement supplémentaires. Les méthodes différentes restent séparées. Les groupes originaux, leurs conditions et leurs statuts sont conservés dans le catalogue et dans `members`. Les environnements configurés restent consultables sans promesse de disponibilité immédiate.

Catégories actuelles : Herbes, Hautes herbes, Grotte, Sable, Sol, Lac, Mer, Pêche · Canne / Lac, Pêche · Super Canne / Lac, Pêche · Canne / Mer, Pêche · Super Canne / Mer, Coup de Boule / Arbres, Éclate-Roc / Grotte.

Après l'union et la déduplication **`[espèce, forme]`**, les périodes de chaque couple sont réunies, puis les entrées sont triées AVANT pagination :

1. Quatre périodes : toute la journée, sans bandeau.
2. Matin, Jour, Matin + Jour, ou majorité diurne sur trois périodes : bandeau `MATIN / JOUR`.
3. Soir, Nuit, Soir + Nuit, ou majorité nocturne sur trois périodes : bandeau `SOIR / NUIT`.

L'ordre initial reste stable à l'intérieur de chaque catégorie. La majorité compte les périodes distinctes, sans pondération par durée, taux ou nombre de groupes. Les paires équilibrées exclues des données par le projet n'ont aucun traitement visuel spécifique.

Les conditions temporelles restent les `enabled_switch` Matin=13, Jour=11, Soir=14, Nuit=12, avec conservation de l'ordre AND/OR. Les prérequis non temporels sont supposés satisfaits uniquement pour calculer cette préférence ; le catalogue et le moteur continuent à les évaluer normalement. Un inconnu ne charge que `000.png`, sans résolution de son nom ou de son sprite d'espèce. Sa position indique sa catégorie collective ; aucun indicateur horaire individuel n'est affiché.

Ensemble conserve l'union des groupes actifs, son ordre initial et sa pagination de douze entrées. Aucun classement horaire ni bandeau n'y est ajouté.

## Disposition réelle : 320 × 240

| Élément | Dimensions / position |
| --- | --- |
| Grille | 4 colonnes de 76 px, de x=8 à x=312 ; jusqu'à 3 lignes |
| Zone des milieux | y=32 à y=192 ; y=52 si une alerte de données est affichée |
| Ensemble | grille y=52 à y=192, pas vertical 46 px |
| Bandeau | **304 × 18 px**, x=8 ; marge de 2 px avant les Pokémon |
| Séparation entre catégories | 4 px avant le bandeau suivant |
| Compteurs et pagination | y=194, hauteur 16 px |
| Barre / boutons | y=214 / y=219, inchangés |

Chaque bandeau contient un dégradé généré en mémoire, la véritable ressource 32 × 18 `daytime.png` ou `nighttime.png` à x=108, puis un court texte noir à x=140. Les deux bandeaux utilisent exactement la même structure. Le dégradé diurne va du jaune pâle à l'orange rouge ; le nocturne du bleu clair au bleu nuit. Aucun PNG n'est modifié.

La pagination des milieux mesure la silhouette visible des fronts et réserve réellement la hauteur des bandeaux. Elle conserve le plus grand préfixe possible de la liste triée, jusqu'à douze entrées et trois lignes. Le pas des lignes reste aussi proche que possible de 46 px, avec un minimum de 32 px. Les grands sprites peuvent se chevaucher dans une même catégorie, mais jamais recouvrir les bandeaux ou les compteurs. Une catégorie commence sur sa propre ligne.

Un bandeau n'est jamais isolé en bas de page : il est reporté avec les premiers Pokémon de sa catégorie. Une catégorie diurne/nocturne poursuivie sur une autre page retrouve son bandeau en haut, pour rendre cette page compréhensible seule. Il n'est affiché qu'une fois par catégorie et par page, sans consommer de case ni entrer dans les compteurs. La capacité peut donc être inférieure à douze sans passer systématiquement à deux lignes.

Les vrais fronts restent à l'échelle **1:1**, avec résolution de la forme par `PFM::Pokemon.front_filename`, puis `RPG::Cache.poke_front`. Les marges transparentes sont mesurées via l'alpha ; aucun pixel visible n'est découpé. `b_icon` n'est pas utilisé.

- Poké Ball : ressource 16 × 16 affichée à 75 %, soit **12 × 12 px**, uniquement pour un Pokémon capturé. Position près du coin supérieur droit de la silhouette visible, légèrement au-dessus, limitée à sa zone pour protéger les bandeaux.
- Inconnu : `pokefront/000.png` affiché à **83 %** ; son bitmap 96 × 96 occupe 79,68 × 79,68 px avant rastérisation et sa silhouette 62 × 62 environ 52 × 52 px. Aucune Ball.

## Accès public TJN et légende

La correction du crash est conservée :

```ruby
key = PFM.game_state.tint_time_set
(Yuki::TJN::TIME_SETS[key] || Yuki::TJN::TIME).dup
```

`current_time_set` est une méthode singleton privée, définie sous `class << self; private` dans PSDK 26.60. Le bloc `module_function` précédent ne rend pas cette définition publique. Les sources locales, la copie projet sous `00001 Scene_Title` et le moteur installé de Studio conservent la même définition et visibilité ; quelques commentaires diffèrent.

Les méthodes publiques propres à TJN sont `init_variables`, `update`, `force_update_tone`, `current_tone` et `update_timed_events`. Aucune ne fournit les seuils. `PFM::Environment#morning?`, `day?`, `sunset?`, `night?` donnent l'état courant, pas les heures. Le moteur récupère le réglage par l'accesseur public `PFM.game_state.tint_time_set`, puis son helper privé sélectionne `TIME_SETS` avec repli sur `TIME`. La page utilise ces mêmes données publiques, sans `send`, changement de visibilité ou modification de TJN.

L'événement de `Data/Map002.rxdata` choisit `:platinum_daynight`, défini dans les teintes mais pas dans `TIME_SETS` : le repli natif s'applique.

| Réglage | Matin | Jour | Soir | Nuit |
| --- | --- | --- | --- | --- |
| default / summer / repli platinum_daynight | 07–11 | 11–19 | 19–22 | 22–07 |
| winter | 10–12 | 12–16 | 16–17 | 17–10 |
| fall / spring | 09–11 | 11–17 | 17–19 | 19–09 |

La légende compacte d'Ensemble conserve les quatre transitions : **Matin/Jour 07h–11h–19h**, **Soir/Nuit 19h–22h–07h** avec les icônes originales. Elle est recalculée lorsque le réglage change. Une alerte de données incomplètes remplace exceptionnellement cette légende dans la même bande.

L'ancien banc rendait accidentellement publique la méthode isolée de TJN. Il charge désormais le module natif complet avec sa visibilité réelle. La régression a reproduit le crash avant correction ; elle vérifie maintenant l'ouverture de la scène avec huit réglages, le maintien de la méthode privée et l'absence de mutation des constantes.

## Navigation conservée

Suivant (A/droite) et Précédent (X/gauche) parcourent Ensemble et les environnements en boucle, en revenant à leur première page. Haut/bas et molette parcourent les pages de la sélection courante, désormais selon leurs tailles réelles. Ensemble (Y) revient à Ensemble page 1 ; Retour (B) retrouve le Pokédex.

## Vérifications et aperçus

**50 tests, 1 337 assertions, aucun échec/erreur, un test ignoré**, sous Ruby 3.1.2 et le Ruby 3.0.6 fourni avec Studio. `Data/Studio/psdk.dat` est absent lors de cette vérification : seule la comparaison JSON/cache compilé est ignorée. Les autres tests chargent les vrais JSON via Studio2PSDK en mémoire, sans écrire de cache.

Sont couverts : catégories et stabilité du tri, union dédupliquée, ordre avant pagination, trois lignes avec deux bandeaux, continuation et report d'un bandeau, navigation sur des pages de huit puis quatre Pokémon, compteurs indépendants des bandeaux, absence d'icônes individuelles, tailles et position des badges, non-révélation des inconnus, formes, catalogue, intégration X et accès public TJN.

Depuis `scripts/` :

```powershell
ruby '.\00015 HabitatList\tests\habitat_test.rb'
& 'C:\Users\thiba\AppData\Local\Programs\pokemon-studio\resources\psdk-binaries\ruby.exe' '-IC:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' '.\00015 HabitatList\tests\habitat_test.rb'
& '.\00015 HabitatList\tests\render_grid_preview.ps1' -PrepareBounds
ruby '.\00015 HabitatList\tests\grid_preview.rb'
& '.\00015 HabitatList\tests\render_grid_preview.ps1'
& '.\00015 HabitatList\tests\check_grid_preview.ps1'
```

Douze aperçus 320 × 240 sont régénérés dans `ui_previews/` :

- `ensemble_1`, `ensemble_2` : légende et pagination.
- `trois_categories_1` : toute la journée → diurne → nocturne, douze Pokémon, trois lignes.
- `jour_vers_nuit_1` : bandeau dès le début et transition diurne/nocturne.
- `suite_categorie_1`, `suite_categorie_2` : catégorie poursuivie, bandeau rappelé et plusieurs inconnus.
- `bandeau_reporte_1`, `bandeau_reporte_2` : grands sprites ; bandeau et catégorie reportés ensemble.
- `formes_et_inconnu`, `horaires_et_capture` : formes, petites et grandes silhouettes, badges et inconnu.
- `milieu_fusionne`, `grotte_fusionnee` : sélections réelles du projet.

Le contrôle indépendant des pixels PNG vérifie les échelles, les limites de chaque zone, l'absence de recouvrement des bandeaux par les Pokémon/Balls, les indicateurs distincts et la visibilité de chaque sprite sur les douze aperçus.

Ces images System.Drawing utilisent les vrais assets et polices, mais **ne sont pas des captures LiteRGSS**. Restent à contrôler en jeu : ouverture de Zone sans crash TJN, rendu des dégradés et textes, finesse des réductions 75/83 %, chevauchement des grands Pokémon dans une catégorie, navigation et retour au Pokédex.

## Diff réversible

`category_bands_before/` conserve l'état précédant les bandeaux, **avec l'accès TJN déjà corrigé**. `category_bands.patch` contient uniquement cette dernière étape, les tests et la documentation. Depuis la racine du projet :

```powershell
git apply --reverse --check 'scripts/00015 HabitatList/category_bands.patch'
git apply --reverse 'scripts/00015 HabitatList/category_bands.patch'
```

Trois patches cumulatifs sont également actualisés : `time_indicators.patch` revient à l'état précédant les horaires, `ui_adjustments.patch` à la grille deux lignes approuvée, `ui_redesign.patch` à la liste initiale de la migration. Choisir un seul point de retour, sans inverser successivement ces patches. Leurs vérifications inverses sont effectuées sans annuler les fichiers actifs. Les dossiers de sauvegarde et aperçus régénérables sont exclus des patches. `tjn_access_before/` conserve séparément le code qui provoquait le crash pour revue historique.
