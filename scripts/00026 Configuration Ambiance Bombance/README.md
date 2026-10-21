# Configuration Ambiance Bombance — V6 : calque nocturne par map

V6 affiche un **PNG complet ancré au décor**, indépendant de la Plane de fog
native. Seule **Bourg-guignon (23)** est configurée. Aucun halo supplémentaire,
éclairage de fenêtre individuel ou système WindowLights n'est créé.

## Dimensions et alignement V6

Les dimensions des fichiers présents diffèrent de celles annoncées dans la demande :

| Élément | Valeur vérifiée |
|---|---|
| `Data/Tiled/Maps/023 BourgGuignon.tmx` | 74 × 59 tuiles de 32 × 32 px |
| `Data/Map023.rxdata` | 74 × 59 tuiles |
| `graphics/fogs/BourgGuignon_Light.png` | **2368 × 1888 px, RGBA**, pas 2048 × 1632 |
| Origine / offsets de couches et groupes Tiled | (0, 0), aucun décalage |
| Affichage PSDK | 16 px par tuile ; PNG affiché en **1184 × 944 px** |

Le zoom **0,5** découle de `16 / pixels_per_tile`, sans étirement automatique.
Un `Sprite::WithColor` affiche le PNG entier, sans répétition ni parallaxe :

```text
caméra = display / 8 + ancre_MapLinker * 16
origine_image = ancre_de_la_map * 16 + offset_source * zoom
écran = origine_image - caméra
zoom = 16 / pixels_per_tile * scale
```

Les offsets sont exprimés en pixels du PNG, avant zoom. Lors d'un raccord,
le même sprite reste aligné avec Bourg-guignon. Depuis Route 1, **seule la portion
visible de Bourg-guignon** conserve ce calque ; les pixels de Route 1 ne sont
pas recouverts. Hors champ ou hors voisinage MapLinker chargé, le sprite est libéré.

## Configuration V6

Tout se règle dans `00000 AmbiancesConfig.rb`. Les defaults désactivent l'effet.
Trois clés ont été ajoutées à l'entrée existante de map 23, sans remplacer ses
réglages V1–V4 :

```ruby
map_ambient_overlay: true,
map_ambient_overlay_texture: 'BourgGuignon_Light', # graphics/fogs, sans .png
map_ambient_overlay_profile: :village_night
```

Le profil `MAP_AMBIENT_OVERLAY_PROFILES[:village_night]` expose :

| Paramètre | Réglage et rôle |
|---|---|
| `max_opacity` | **128**, maximum global entre 0 et 255 |
| `blend_type` | **0**, mélange alpha normal, sans addition |
| `z` | **2900**, dans le viewport de carte |
| `pixels_per_tile` | **32**, résolution de l'export PNG |
| `scale` | **1.0**, éventuelle correction manuelle du zoom |
| `offset_x`, `offset_y` | **0, 0**, éventuelle correction manuelle d'origine |
| `time_points` | Couples `[minutes_depuis_minuit, pourcentage]`, triés |

```ruby
time_points: [
  [0, 100], [420, 100], [540, 50], [660, 0],
  [1140, 0], [1200, 50], [1230, 100], [1440, 100]
]
```

L'interpolation est linéaire entre points, avec raccord cyclique à minuit.
Seules les variables heure/minute de **TJN** sont lues : aucune nouvelle horloge,
aucun changement du Tone ni des périodes. À l'entrée, au chargement et au retour
de combat, l'intensité est immédiatement correcte, sans fondu de démarrage.
Un changement direct de l'heure applique directement sa valeur. **TJN désactivé
rend V6 invisible.** La météo ne modifie pas cette courbe.

| Heure | Intensité | Opacité du profil actuel |
|---|---:|---:|
| 11 h–19 h | 0 % | 0, aucun sprite |
| 20 h | 50 % | 64 |
| 20 h 30–07 h | 100 % | 128 |
| 09 h | 50 % | 64 |

Pour une autre map, exporter son PNG complet dans `graphics/fogs`, vérifier
dimensions et origine, puis ajouter ces trois clés à son entrée existante :

```ruby
42 => {
  # Conserver ici les autres réglages existants de cette map.
  map_ambient_overlay: true,
  map_ambient_overlay_texture: 'MonVillage_Nuit',
  map_ambient_overlay_profile: :village_night
}.freeze
```

Pour un autre rythme ou une autre opacité, dupliquer l'entrée `village_night`
dans `MAP_AMBIENT_OVERLAY_PROFILES` sous un nouveau nom et référencer ce nom.
Pour un export à 16 px par tuile, utiliser `pixels_per_tile: 16`. Aucun changement
du moteur n'est nécessaire. Les points horaires doivent être triés, sans
doublons, avec des pourcentages entre 0 et 100 ; si 0 et 1440 figurent tous deux,
leurs valeurs doivent concorder.

Priorité : defaults → groupes → map → override temporaire. Un événement peut
utiliser les méthodes existantes, sans modification des données de map :

```ruby
BombanceAmbiance.override_effects(map_ambient_overlay: false)
BombanceAmbiance.clear_overrides
```

## Rendu, alpha et ressources V6

Le viewport natif de carte est à Z=0 et porte le Tone TJN. À l'intérieur : V2
est à Z=1, météo/feuilles à 1000, rayons à 2000, **V6 à 2900**, fog natif à
3000, lucioles à 3100. Les nuages peuvent donc toujours assombrir le calque,
et les lucioles restent au-dessus. Les personnages sous le calque sont teintés
comme le décor, sans masque individuel. Les viewports des interfaces, notamment
Z=200, et les dialogues restent au-dessus. Menus et dialogues ont été capturés.

L'alpha effectif reste **alpha PNG × opacité globale / 255**. Le PNG est intact :
alpha réel de **77 à 233**, médiane **207**. Les centres des trois fenêtres
testées ont un alpha proche de **79** : leur teinte orangée reste **discrète**,
mélangée aux vitrages bleus et au Tone nocturne. Le système ne renforce pas
artificiellement ces pixels et ne crée pas de plaques jaunes opaques. Les
lampadaires ne reçoivent que ce qui est effectivement dessiné dans le PNG.

Le maximum de **128** limite le cumul avec TJN et V2. À 23 h, la luminance
moyenne de la capture passe de **99,68 à 54,85 / 255** ; routes, bâtiment et
personnages restent identifiables. Augmenter ce réglage renforce également les
zones sombres. Aucune seconde couche d'assombrissement n'est créée.

`00009 MapAmbientOverlay.rb` contient la courbe horaire, la résolution des
maps et le renderer. Il utilise `Manager#sync_context` et les méthodes natives
`Spriteset_Map#update_sprites` / `dispose_sprites` par `prepend`. Les sources
sont recalculées quand la map, son ancre, la configuration ou le voisinage change.
Aucun hook de combat supplémentaire n'est nécessaire.

Un sprite par map configurée actuellement visible, seulement à opacité positive.
Pas de bitmap par frame ni d'objet V6 dans les sauvegardes. Les sprites sont
libérés hors champ, en journée, au retrait de l'effet, au changement de session
ou à la destruction du spriteset. La texture est **empruntée à `RPG::Cache.fog`** :
PSDK conserve et libère ses textures selon son propre cycle. V6 ne détruit
jamais une texture potentiellement partagée. Cette mise en cache n'est pas un
sprite résiduel sur les autres maps.

## Tests et captures V6

Lancement réel réussi via **Game.rb / Ruby Studio 3.0.6 / PSDK 26.60**.
`tests/ambient_overlay_game.rb` lit une sauvegarde sans l'écrire, prépare les
scénarios en RAM et interdit les écritures hors de son dossier de captures.
Les événements sont suspendus dans ce processus de test ; combat, transferts,
menus et dialogues utilisent le moteur natif.

- **V6 : 8 tests, 1 505 assertions**, sans échec.
- **V5 : 15 tests, 779 assertions**, sans échec.
- **V1–V4 : 68 tests, 24 281 assertions**, sans échec, via les références
  historiques chargées uniquement en mémoire par `legacy_regression.rb v4`.
- **581 contrôles** des nouvelles captures, de l'alpha, de la géométrie et des horaires.
- **60 états V1–V4 identiques** sur 23/27/36/80/30, quatre périodes/trois météos.
  Toutes les anciennes valeurs de configuration sont inchangées, comparées
  séparément des nouvelles clés V6.
- Combat sauvage natif terminé : opacité 128 dès le premier affichage au retour.
  Menu/dialogue, scrolling, raccord 23 → 27, transferts 36/80/35 puis 23,
  et nouveau chargement de sauvegarde vérifiés.
- Nuages `clouds`, opacité 90, zoom 0,5 et mouvement V1 conservés, également
  sous la pluie native. Fog reste actif sur 36/80, sans V6.
- Les validateurs de captures historiques V2/V3/V4 et Forêt Enchantée passent.
  `check_leaves_continuity.py` atteint son dernier contrôle puis signale une
  **empreinte globale de configuration devenue obsolète** après l'ajout V6.
  Les captures et la texture des feuilles passent les contrôles précédents.
  Le test historique et les réglages utilisateur n'ont pas été réécrits pour
  masquer cette différence.

Rapport : `tests/ambient_overlay_preservation.json`. Télémétrie et contrôles :
`tests/captures_ambient_overlay/results.json` et `checks.json`.
Les **30 PNG** sont des captures natives sans retouche. Dans chaque paire,
seul le sprite V6 est temporairement masqué pour la référence : les autres
effets restent identiques, au même instant.

| Heure | Avant V6 | Avec V6 |
|---|---|---|
| 12 h | [Avant](tests/captures_ambient_overlay/00_12h00_before.png) | [Après](tests/captures_ambient_overlay/00_12h00_after.png) |
| 19 h | [Avant](tests/captures_ambient_overlay/01_19h00_before.png) | [Après](tests/captures_ambient_overlay/01_19h00_after.png) |
| 20 h | [Avant](tests/captures_ambient_overlay/02_20h00_before.png) | [Après](tests/captures_ambient_overlay/02_20h00_after.png) |
| 20 h 30 | [Avant](tests/captures_ambient_overlay/03_20h30_before.png) | [Après](tests/captures_ambient_overlay/03_20h30_after.png) |
| 23 h | [Avant](tests/captures_ambient_overlay/04_23h00_before.png) | [Après](tests/captures_ambient_overlay/04_23h00_after.png) |
| 04 h | [Avant](tests/captures_ambient_overlay/05_04h00_before.png) | [Après](tests/captures_ambient_overlay/05_04h00_after.png) |
| 07 h | [Avant](tests/captures_ambient_overlay/06_07h00_before.png) | [Après](tests/captures_ambient_overlay/06_07h00_after.png) |
| 09 h | [Avant](tests/captures_ambient_overlay/07_09h00_before.png) | [Après](tests/captures_ambient_overlay/07_09h00_after.png) |
| 11 h | [Avant](tests/captures_ambient_overlay/08_11h00_before.png) | [Après](tests/captures_ambient_overlay/08_11h00_after.png) |

Autres captures : [pluie/nuages](tests/captures_ambient_overlay/rain_clouds_after.png),
[scrolling](tests/captures_ambient_overlay/camera_moved_after.png),
[MapLinker](tests/captures_ambient_overlay/linked_route_border.png),
[retour de combat](tests/captures_ambient_overlay/battle_first_return.png),
[menu](tests/captures_ambient_overlay/menu.png), [dialogue](tests/captures_ambient_overlay/dialogue.png),
[chargement nocturne](tests/captures_ambient_overlay/loaded_night.png).

Limites : déplacements automatisés par les méthodes natives, pas un parcours
manuel exhaustif ; un combat sauvage testé pour V6, pas tous les combats
scénarisés/Safari. La force des lumières dépend du PNG fourni et du Tone existant.

```powershell
$ruby = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
& $ruby -I 'C:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' 'scripts/00026 Configuration Ambiance Bombance/tests/ambient_overlay.rb'
$env:PSDK_BINARY_PATH = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/'
& $ruby --disable=gems,rubyopt,did_you_mean 'scripts/00026 Configuration Ambiance Bombance/tests/ambient_overlay_game.rb'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_ambient_overlay.py'
```

Fichiers V6 ajoutés : `00009 MapAmbientOverlay.rb`, les tests
`ambient_overlay.rb`, `ambient_overlay_game.rb`, `check_ambient_overlay.py`,
le rapport de préservation et `captures_ambient_overlay/`. Modifications ciblées
de `00000 AmbiancesConfig.rb` et de ce README. Aucun changement des moteurs
V1–V5, PNG, Tiled, maps, événements, tilesets, TJN, FogFix, Weather Bombance ou
scripts PSDK. Aucun commit.

---

# Configuration Ambiance Bombance — V5 : Forêt Enchantée

La V5 concerne uniquement la **Forêt Enchantée actuelle, map 35**. Elle ajoute
une pluie légère de feuilles et configure les moteurs V3/V4 existants. La map
78 (« Passé »), Route 1 (27), Bourg-guignon (23), les maps 36/80 et leurs
réglages personnalisés restent inchangés. L'ancien éclairage des fenêtres a
été supprimé ; aucun de ses fichiers ou hooks n'est réutilisé.

## Carte, canopée et repères

La map réelle mesure **130 × 100 tuiles**, tileset **30 / `_30`**. Son raccord
ouest mène à Cocovin (25), où les feuilles sont désactivées. Les placements ont
été choisis à partir des données de la carte, des clairières et des massifs
visibles, puis contrôlés dans le véritable rendu PSDK.

Le fog **`graphics/fogs/eterna-forest-style-fog2.png` est conservé intact** :
nom, opacité 70, zoom 100, blend normal, vitesses 0/0. Il présente déjà des
ouvertures irrégulières utilisables dans plusieurs clairières. La composition
est adaptée par le placement des rayons et des lucioles, sans nouvelle texture
de fog ni couche lumineuse supplémentaire. La comparaison « canopée retenue »
montre donc volontairement le même fog que la référence originale.

Cette image est RGB opaque : ses ouvertures sont des pixels clairs, pas des
trous alpha. C'est l'opacité native de la Plane qui mélange l'image au décor.
FogFix applique un zoom effectif de **0,5** et une origine
`display_x / 4 + fog_ox`, `display_y / 4 + fog_oy`. À vitesse nulle, un point
de map `(x, y)` en tuiles correspond à `(x * 32, y * 32)` dans cette texture,
modulo **1024 × 640**. Le motif se répète tous les **32 × 20 tuiles** et reste
ancré au décor pendant le scrolling. Ni FogFix ni V1 ne sont modifiés.

## Rayons et lucioles

Le profil indépendant **`enchanted_forest_sunlight`** reprend la texture et le
moteur V3 : un sprite par rayon, largeur 20, longueur 90, angle 24° vers le bas
droit. L'opacité de base est 65 le matin, 82 le jour, 52 le soir et 0 la nuit.
La densité évolue selon les périodes réelles TJN ; les transitions restent
celles de V3. Aucun rayon lunaire n'est activé ici. La pluie atténue les rayons,
la météo **Fog** les éteint. Le fog de canopée ne constitue pas la météo Fog et
n'est pas confondu avec `clouds.png` par le masque nuageux V3.

Les pieds des huit rayons, en tuiles locales, sont tous à l'intérieur d'une
ouverture claire mesurée après transformation FogFix :

| Zone | X | Y |
|---|---:|---:|
| Clairière ouest | 35.52 | 66.46 |
| Prairie de la maison | 81.07 | 55.49 |
| Carrefour est | 100.22 | 36.85 |
| Clairière nord-est | 71.29 | 34.44 |
| Sous-bois central | 50.49 | 52.06 |
| Sous-bois sud | 50.28 | 82.75 |
| Chemin fleuri nord-ouest | 35.04 | 34.07 |
| Clairière de la souche | 18.28 | 62.75 |

Les ouvertures restantes conservent leurs seuls contrastes natifs. La lumière
diffuse V2 n'est pas activée sur cette map, pour éviter d'aplatir les ombres.

Les lucioles utilisent **exactement le profil `natural_fireflies` existant** :
aucun changement de taille, couleur, intensité, mouvement ou période. Leurs
rectangles `(x, y, largeur, hauteur, nombre maximal)` sont :

```text
(23,33,8,5,5)   (42,32,4,4,4)   (33,64,7,5,7)   (19,64,8,4,5)
(50,51,4,6,5)   (47,80,6,4,6)   (75,52,4,7,5)   (84,52,3,8,4)
(76,33,6,3,5)   (104,36,4,6,4)
```

Elles s'éteignent progressivement le matin, restent absentes en journée,
apparaissent au crépuscule et atteignent leur activité maximale la nuit.

## Feuilles : configuration et fonctionnement

Tout se règle dans **`00000 AmbiancesConfig.rb`**. Les maps non configurées ont
`falling_leaves: false`. Pour ajouter des feuilles à une autre map, ajouter
uniquement ces clés à son entrée existante, en conservant les autres valeurs :

```ruby
falling_leaves: true,
falling_leaves_profile: :enchanted_leaves
```

Le réglage `outdoor` existant doit autoriser un extérieur. Aucune coordonnée ni
zone de feuilles n'est nécessaire. Le profil **`FALLING_LEAVES_PROFILES`** expose :

| Paramètre | Valeur initiale / rôle |
|---|---|
| `texture`, `frame_size`, `variants` | Atlas partagé 48 × 16, trois cellules de 16 px |
| `count` | Pool fixe de 24 sprites, environ 18–24 feuilles visibles |
| `fall_speed` | 0,40 pixel par update logique, soit environ 24 px/s à 60 Hz |
| `drift_x` | 0,09 pixel par update, vers la droite ; valeur négative possible |
| `sway_amplitude`, `sway_steps` | Oscillation de 3,5 px, période de 330 updates |
| `speed_variation` | ±22 % de vitesse individuelle |
| `scale`, `scale_variation` | Taille nominale 1, variation ±12 % |
| `opacity`, `opacity_variation` | 205, atténuation individuelle jusqu'à 18 % |
| `rotation` | Oscillation d'orientation de ±18° |
| `colors`, `tint` | Palette pondérée verte, vert-jaune et dorée, mélange 210/255 |
| `fade_steps` | Fondu individuel de 90 updates |
| `respawn_steps` | Attente de 0 à 90 updates avant de retomber par le haut |
| `weather_transition_steps` | Lissage météo sur 180 updates |
| `z` | 1000, comme les particules météo natives, sous la canopée et les interfaces |
| `seed` | Distribution reproductible, générateur privé sans effet sur le hasard du jeu |

Les silhouettes visibles occupent seulement quelques pixels dans chaque
cellule. La texture a été créée avec imagegen puis réduite au plus proche
voisin ; elle n'a ni halo ni éclairage additionnel. Les variations de couleur
se règlent dans le profil. Répéter une couleur dans `colors` augmente sa fréquence.

Les feuilles vivent en **pixels du monde**, dans le même repère MapLinker que
V1/V3/V4. Leur projection est `écran = monde - caméra`, avec
`caméra_x = display_x / 8.0 + anchor_x * 16` (idem pour Y). PSDK utilise 128
unités de déplacement par tuile et affiche une tuile sur 16 pixels. Le scrolling
déplace donc leur affichage comme le décor, sans modifier leur trajectoire.
Même un redessin sans update logique recalcule cette projection.

La chute reste à **0,40 px/update** et la dérive à **+0,09 px/update**, soit
22,5 % vers la droite, avec les variations individuelles et oscillations déjà
présentes. Aucun paramètre artistique ni facteur météo n'a été changé.

Le pool apparaît progressivement **par le haut** à l'entrée normale de la forêt.
Seules les particules complètement hors champ peuvent être recyclées, avec
une marge tenant compte de l'oscillation. Au repos elles renaissent en haut ;
pendant le scrolling, elles peuvent entrer par le bord nouvellement découvert.
Dans ce dernier cas, elles n'attendent pas avant de bouger : une attente qui
finirait au milieu de l'écran provoquerait une apparition brusque. Le nombre
de renouvellements est limité à un par update logique. Les naissances en haut
sont bornées à la largeur réelle de la map. Le pool reste fixé à 24 sprites,
sans accumulation dans les zones invisibles. Après une téléportation rapide,
la couverture se reconstitue progressivement ; aucune feuille visible n'est
déplacée artificiellement pour remplir l'écran.

Les sprites sont conservés lors d'un raccord MapLinker utilisant le même profil,
et libérés en quittant une map autorisée. La texture est empruntée au cache PSDK
et n'est jamais libérée par le renderer.

### Retour de combat

L'extension intercepte les points natifs `Scene_Map#setup_start_battle` et
`Battle::Scene#return_to_last_scene`, sans modifier les fichiers PSDK. Après un
lancement de combat réussi, le manager conserve une seule copie des particules
(coordonnées mondiales, vitesses, phases, variantes, indices de couleur, attente
et fondu), de l'état du générateur privé et des facteurs météo interpolés.
Aucun Sprite, Color, bitmap, viewport ou objet de combat n'est conservé.

Le retour natif autorise une reprise uniquement pour le même combat, la même
map, le même emplacement du joueur et le même profil. Le nouveau renderer
consomme cet état **une seule fois** : dès sa construction, les feuilles
retrouvent exactement leurs positions et leurs opacités, sans rattrapage du
temps passé en combat. La chute reprend au prochain update logique.

Une défaite avec téléportation, une désactivation de l'effet, un changement de
map/profil ou un chargement invalide cet état. Une reconstruction ordinaire de
scène n'est jamais assimilée à un combat. Le retour de menu et la fermeture de
dialogue conservent le renderer existant. Cet état est limité à la session,
hors sauvegarde, et ne constitue pas un cache permanent de toutes les maps.

Le compteur suit les updates logiques de `Game_Map`, pas `Graphics.update` :
un redessin de menu ne fait pas avancer les feuilles. Aucun bitmap n'est créé
par frame. Les feuilles utilisent le viewport natif de carte, son Tone TJN et
son ordre de rendu : devant le joueur, sous le fog et les interfaces. Aucun
objet graphique n'est enregistré dans les sauvegardes.

### Météo et priorité

Seule la météo effective PSDK est lue. Chaque entrée règle indépendamment
`density`, `fall` et `wind` :

| Météo | Densité | Vitesse de chute | Dérive |
|---|---:|---:|---:|
| Calme / soleil | 1,0 | 1,0 | 1,0 |
| Soleil intense | 0,8 | 1,0 | 1,0 |
| Pluie | 0,7 | 1,15 | 1,5 |
| Forte pluie | 0,4 | 1,35 | 2,4 |
| Vent fort | 0,8 | 1,3 | 3,5 |
| Fog | 0,85 | 1,0 | 0,7 |
| Neige / grêle / sable / inconnu | 0 | 1,0 | 1,0 |

Le facteur météo modifie les feuilles, jamais la météo ni les fogs. TJN colore
naturellement les feuilles la nuit sans arrêter leur chute. L'interaction
lumineuse facultative feuille/rayon n'est pas ajoutée : le Tone de la carte
suffit, sans masque ni calcul supplémentaire par feuille.

La priorité reste défaut → groupes → map → activation/désactivation temporaire
par événement ; les facteurs météo s'appliquent ensuite. Aucune modification
d'événement n'a été faite. Pour un futur événement :

```ruby
BombanceAmbiance.override_effects(falling_leaves: false)
BombanceAmbiance.clear_overrides # Rétablit la configuration de la map courante.
```

## Validation de la correction des feuilles

Le lanceur **`tests/leaves_continuity_game.rb`** exécute `Game.rb` sous Ruby
Studio 3.0.6 / PSDK 26.60. La sauvegarde est lue uniquement. Les Pokémon et
paramètres nécessaires aux combats sont préparés en mémoire ; les choix de
combat et la validation des textes sont automatisés. Les attaques, animations,
captures, fins de combat, destructions de scènes et retours sont ceux de PSDK.
Les événements sont suspendus dans ce seul processus de test. Les écritures
sont limitées à son dossier de captures ; le cache de compilation est en RAM.

Résultats de la correction :

- **15 tests V5, 779 assertions**, sans échec, sur la configuration actuelle :
  projection, scrolling dans les deux axes et en diagonale, demi-tour, redessins
  sans tick, scrolling prolongé, quatre bords, raccord MapLinker avec origine
  conservée, pool borné, météo, session, reprise unique et invalidations.
- **68 tests historiques V1–V4, 24 281 assertions**, sans échec, via
  `legacy_regression.rb v4`. Les anciennes références sont chargées en mémoire
  dans les tests ; aucun réglage utilisateur n'est réécrit.
- **60 états** des maps 23/27/36/80/30, sur quatre périodes et trois météos,
  identiques à la référence antérieure. Configuration complète, moteurs V1–V4,
  fog de forêt et atlas de feuilles identiques octet pour octet à l'avant-correction.
  Empreintes : `tests/leaves_continuity_preservation.json`.
- **Cinq combats natifs terminés** : victoires sauvage et dresseur, fuite,
  capture réussie, défaite avec téléportation sur 23. Pour les quatre retours
  en forêt, l'état des 24 particules est vérifié exactement à la construction
  du renderer, avant son premier update ; les feuilles sont déjà réparties
  sur plusieurs hauteurs. La défaite invalide l'état et n'affiche aucune feuille
  sur 23. Le code résultat natif de capture vaut `-1` dans ce scénario ; le
  champ `caught: true` confirme la capture effective.
- Menu, dialogue et transferts natifs 35 → 25 → 23 → 27 → 36 → 80 → 35
  réussis. Fog reste actif sur 36/80 ; l'entrée normale sur 35 recommence en haut.
  Le menu et le dialogue conservent les particules et les sprites.
- **2 301 contrôles** des nouvelles captures/télémétries, plus les **102 contrôles**
  des captures historiques, réussis. Le validateur de préservation fige les
  empreintes de la configuration au moment de cette correction : une future
  modification volontaire nécessite de renouveler cette référence, pas de
  restaurer d'anciens réglages utilisateur.
- Performance native : **0,174 ms/update en moyenne sur 3 055 updates**, maximum
  **2,317 ms**, instrumentation active. La précédente mesure était 0,205 ms ;
  ces mesures indicatives ne constituent pas un benchmark GPU complet.

Les **31 PNG natifs** et leur télémétrie sont dans
[`tests/captures_leaves_continuity/`](tests/captures_leaves_continuity/).
Les vues utiles à la comparaison sont :

| Vérification | Captures |
|---|---|
| Entrée progressive | [Entrée](tests/captures_leaves_continuity/entry.png), [retour normal](tests/captures_leaves_continuity/normal_reentry.png) |
| Chute immobile, intervalles de 15 updates | [Début](tests/captures_leaves_continuity/stationary_00.png), [15](tests/captures_leaves_continuity/motion_15.png), [30](tests/captures_leaves_continuity/motion_30.png), [45](tests/captures_leaves_continuity/motion_45.png) |
| Caméra | [Droite](tests/captures_leaves_continuity/camera_right.png), [gauche](tests/captures_leaves_continuity/camera_left.png), [haut](tests/captures_leaves_continuity/camera_up.png), [bas](tests/captures_leaves_continuity/camera_down.png), [diagonale](tests/captures_leaves_continuity/camera_diagonal.png) |
| Combat sauvage | [Avant](tests/captures_leaves_continuity/wild_before.png), [premier affichage au retour](tests/captures_leaves_continuity/wild_first_return.png) |
| Dresseur | [Avant](tests/captures_leaves_continuity/trainer_before.png), [retour](tests/captures_leaves_continuity/trainer_first_return.png) |
| Fuite / capture | [Retour de fuite](tests/captures_leaves_continuity/flee_first_return.png), [retour de capture](tests/captures_leaves_continuity/capture_first_return.png) |
| Défaite | [Retour sur 23 sans feuilles](tests/captures_leaves_continuity/defeat_first_return.png) |
| Interfaces | [Dialogue](tests/captures_leaves_continuity/dialogue.png), [menu](tests/captures_leaves_continuity/menu.png), [retour du menu](tests/captures_leaves_continuity/menu_return.png) |

Les fichiers `*_battle.png` montrent le début de la transition vers le combat,
avant que le décor de combat ne remplace la carte. Les comparaisons de continuité
utilisent bien `*_before.png` et `*_first_return.png`. La caméra est déplacée
par les méthodes natives, pas par un parcours manuel au clavier. Le chargement
réel est testé au lancement ; l'invalidation de session est aussi testée sans
interface. Les événements spécifiques du projet, combats multiples et Safari
ne font pas partie de ces cinq scénarios automatisés.

Fichiers modifiés pour cette correction uniquement :

- `00008 FallingLeaves.rb` — seul fichier de production modifié.
- `tests/enchanted_forest.rb` — attentes mondiales et tests supplémentaires.
- `README.md` — comportement, résultats et limites.

Fichiers ajoutés : `tests/leaves_continuity_game.rb`,
`tests/check_leaves_continuity.py`, `tests/leaves_continuity_preservation.json`,
et les 31 PNG / `results.json` dans `tests/captures_leaves_continuity/`.
Aucun fichier supprimé, aucun changement des paramètres, textures, maps,
événements, scripts PSDK ou systèmes V1–V4 ; aucun commit.

Pour relancer les nouveaux tests (en complément des commandes historiques) :

```powershell
$ruby = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
$env:PSDK_BINARY_PATH = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/'
& $ruby --disable=gems,rubyopt,did_you_mean 'scripts/00026 Configuration Ambiance Bombance/tests/leaves_continuity_game.rb'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_leaves_continuity.py'
```

## Captures initiales de la V5 (avant correction spatiale)

Le lanceur `tests/enchanted_game.rb` démarre **Game.rb avec le Ruby de Studio**,
charge une sauvegarde en lecture seule et place le joueur sur la map 35 en
mémoire. Il suspend uniquement l'exécution des événements dans ce processus
de capture. Il interdit les écritures des sauvegardes et données du projet.
Les transitions sont attendues en **updates logiques**, indépendamment du
nombre de rendus GPU. Les fichiers suivants sont des captures PSDK, pas des
montages ni des rendus générés :

| Vue | Capture |
|---|---|
| Fog original | [01](tests/captures_enchanted/01_original_fog.png) |
| Canopée retenue, inchangée | [02](tests/captures_enchanted/02_retained_canopy.png) |
| Fog et rayons | [03](tests/captures_enchanted/03_canopy_rays.png) |
| Fog et feuilles | [04](tests/captures_enchanted/04_canopy_leaves.png) |
| Fog et lucioles | [05](tests/captures_enchanted/05_canopy_fireflies.png) |
| Tous les effets, journée | [06](tests/captures_enchanted/06_all_day.png) |
| Tous les effets, crépuscule | [07](tests/captures_enchanted/07_all_sunset.png) |
| Tous les effets, nuit | [08](tests/captures_enchanted/08_all_night.png) |
| Caméra déplacée | [14](tests/captures_enchanted/14_camera_moved.png) |
| Prairie est, jour / nuit | [15](tests/captures_enchanted/15_eastern_meadow.png), [16](tests/captures_enchanted/16_eastern_night.png) |
| Dialogue et menu natifs | [17](tests/captures_enchanted/17_dialogue.png), [18](tests/captures_enchanted/18_native_menu.png) |

Mouvement sur une seconde logique : [0](tests/captures_enchanted/09_motion_00.png),
[15](tests/captures_enchanted/10_motion_15.png),
[30](tests/captures_enchanted/11_motion_30.png),
[45](tests/captures_enchanted/12_motion_45.png),
[60](tests/captures_enchanted/13_motion_60.png) updates.
Les mesures et observations sont dans `tests/captures_enchanted/results.json`.

## Tests initiaux de la V5 (historique)

- `tests/enchanted_forest.rb` : **10 tests, 303 assertions** avec la configuration
  actuelle. Chute/recyclage, variations, pool/texture, redessins, caméra,
  regroupement des ticks, météo, transferts, retour de scène, reset de session,
  générateur aléatoire privé, priorité événementielle, TJN et fog natif.
- `tests/legacy_regression.rb v4` : **68 tests, 24 281 assertions** réussis avec
  les jeux de référence historiques chargés seulement dans le processus de test.
- Les 60 états map/horaire/météo des maps 23/27/36/80/30 sont identiques avec
  et sans la nouvelle V5. Tous les réglages antérieurs et profils partagés
  ont été comparés, ainsi que les empreintes des moteurs V1–V4 et du fog original.
  Le relevé est conservé dans `tests/enchanted_preservation.json`.
- `tests/check_enchanted_captures.py` : **102 vérifications** réussies sur les
  captures réelles, les huit ouvertures, l'atlas, les périodes, le pool et les
  transferts. **19 captures PSDK** ont été examinées, dont le dialogue et le menu.
- Lancement réel avec `Game.rb` réussi. Transferts natifs vers 25/23/27/36/80 puis
  retour sur 35 réussis : aucun sprite de feuille hors forêt, Fog toujours actif
  sur 36/80, nouveau pool correct au retour. Menu natif : état et sprites conservés.
- Coût des feuilles mesuré en jeu sur 4 917 updates : **0,205 ms en moyenne**,
  maximum **1,312 ms**, avec l'instrumentation `TracePoint` active. Cette mesure
  inclut le surcoût du lanceur et ne prétend pas mesurer tous les effets de la map.
- Les anciens tests lancés directement avec les personnalisations actuelles
  gardent leurs anciennes hypothèses de placement/densité et de map 23 désactivée.
  Aucune configuration de production n'est remplacée pour satisfaire ces tests.
- Le cycle destruction/recréation utilisé lors d'un retour de scène est testé ;
  aucun combat complet n'est automatisé par le lanceur de captures.

Pour relancer sous le Ruby 3.0.6 fourni par Studio (adapter son chemin local et
le chemin de minitest si nécessaire) :

```powershell
$ruby = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
& $ruby -I 'C:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' 'scripts/00026 Configuration Ambiance Bombance/tests/enchanted_forest.rb'
& $ruby -I 'C:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib' 'scripts/00026 Configuration Ambiance Bombance/tests/legacy_regression.rb' v4
$env:PSDK_BINARY_PATH = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/'
& $ruby --disable=gems,rubyopt,did_you_mean 'scripts/00026 Configuration Ambiance Bombance/tests/enchanted_game.rb'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_enchanted_captures.py'
```

Le lanceur graphique nécessite `Saves/Pokemon_Party-1` pour lire une partie
existante ; il ne sauvegarde jamais. Aucun commit, aucun changement de map,
tileset, événement, TJN, FogFix, Weather Bombance ou système de combat.

## Documentation historique V1–V4

Les exemples ci-dessous décrivent leurs scènes de référence historiques.
**Les réglages actuels dans `00000 AmbiancesConfig.rb` font foi**, notamment
pour les personnalisations de Route 1 et de Bourg-guignon.

### V4 : lucioles

La V4 ajoute des lucioles localisées sur **Route 1 (27)**, dans trois petites zones
de fleurs, d'herbes et de clairière. Elles sont indépendantes des rayons et des
ombres nuageuses. Maps 36/80 et autres maps : OFF par défaut. Aucun commit.

Les positions et densités V3 personnalisées présentes à l'arrivée ont été
conservées. Les exemples et mesures V3 plus bas décrivent le **profil historique
de régression**, pas ces réglages personnalisés ; le fichier
[00000 AmbiancesConfig.rb](00000%20AmbiancesConfig.rb) reste la source effective.

## V4 — configuration complète

Tout se règle dans `00000 AmbiancesConfig.rb`, sans modifier le rendu.
Redémarrer le jeu après un changement de configuration.

Valeurs par défaut :

```ruby
fireflies: false,
fireflies_profile: :natural_fireflies,
fireflies_zones: [].freeze
```

Ajouts livrés dans l'entrée existante de Route 1 :

```ruby
fireflies: true,
fireflies_profile: :natural_fireflies,
fireflies_zones: [
  { x: 39.5, y: 24.3, width: 3.5, height: 1.6, count: 7 }.freeze,
  { x: 42.0, y: 18.7, width: 4.0, height: 2.8, count: 6, intensity: 0.9 }.freeze,
  { x: 47.5, y: 24.0, width: 3.2, height: 2.0, count: 8 }.freeze
].freeze
```

`x/y` désignent le **coin supérieur gauche**, en tuiles locales de la map.
`width/height` sont en tuiles (une tuile = 16 pixels logiques). Ces rectangles
ont été vérifiés sur les vraies tuiles de Route 1 : massif fleuri au sud de la
clairière, intérieur de la clairière centrale, herbes/fleurs côté est.
Ils remplacent les coordonnées provisoires de la demande ; aucun fichier map
ou tileset n'a été modifié. `count` est la capacité maximale, `intensity` un
multiplicateur d'opacité (1 par défaut). Le profil limite chaque zone à 8 individus.
Une liste vide n'alloue aucun sprite ; les zones de taille/quantité nulle sont ignorées.

Profil livré, dans `FIREFLIES_PROFILES` :

```ruby
natural_fireflies: {
  texture: 'bombance_ambiance/firefly', z: 3100,
  max_per_zone: 8, scale: 1.0, halo_strength: 0.65,
  rgb: [250, 255, 150].freeze,
  drift_x: 4.0, drift_y: 3.0, move_steps: 960.0,
  pulse_steps: 260.0, pulse_min: 0.25, intensity_variation: 0.15,
  transition_steps: 240, weather_transition_steps: 180,
  periods: {
    morning: { density: [0.45, 0.0].freeze, opacity: [115, 0].freeze }.freeze,
    day:     { density: [0.0, 0.0].freeze, opacity: [0, 0].freeze }.freeze,
    sunset:  { density: [0.25, 0.50].freeze, opacity: [100, 155].freeze }.freeze,
    night:   { density: [1.0, 1.0].freeze, opacity: [220, 220].freeze }.freeze
  }.freeze,
  weather: {
    none: 1.0, sunny: 1.0, hardsun: 0.5, rain: 0.25, hardrain: 0.0,
    strong_winds: 0.0, sandstorm: 0.0, fog: 0.55, snow: 0.0, hail: 0.0
  }.freeze,
  unknown_weather: 0.0
}.freeze
```

| Paramètre                  | Sens / unité                                                                     |
| -------------------------- | -------------------------------------------------------------------------------- |
| `rgb`                      | Couleur commune ; une période peut aussi préciser son propre `rgb`               |
| `scale`                    | Taille du sprite, 1 = texture 7×7 et cœur d'un pixel                             |
| `halo_strength`            | Force des pixels du halo, sans modifier le cœur opaque                           |
| `max_per_zone`             | Plafond appliqué à chaque `count`                                                |
| `drift_x/y`                | Amplitudes maximales en pixels, réduites si la zone est étroite                  |
| `move_steps`               | 960 updates logiques pour l'oscillation principale (~16 s à 60 Hz)               |
| `pulse_steps`              | 260 updates pour la pulsation principale (~4,3 s), vitesse individuelle variable |
| `pulse_min`                | Minimum relatif de luminosité durant une pulsation                               |
| `intensity_variation`      | Variation stable entre individus, ici de 85 à 100 %                              |
| `transition_steps`         | Fondu horaire/couleur : 240 updates, environ 4 s                                 |
| `weather_transition_steps` | Fondu météo : 180 updates, environ 3 s                                           |
| `density`, `opacity`       | Paires [début, fin] de période ; densité × capacité de zone                      |

Conserver des dimensions positives (au moins une tuile recommandée), des quantités
entières positives, des densités entre 0 et 1 et des durées positives.
Augmenter légèrement `opacity` avant d'agrandir `scale` : le halo doit rester minuscule.

Exemples indépendants des rayons :

```ruby
# Ajouter à MAPS : lucioles seules sur une autre map extérieure.
28 => {
  outdoor: true, fireflies: true, rays: false,
  fireflies_profile: :natural_fireflies,
  fireflies_zones: [{ x: 12, y: 18, width: 4, height: 3, count: 5 }]
}.freeze,

# Exceptions explicites :
36 => { diffuse_light: false, rays: false, fireflies: false }.freeze,
80 => { diffuse_light: false, rays: false, fireflies: false }.freeze,
```

Pour un futur profil différent, copier le profil complet sous un autre nom,
modifier sa palette/mouvement/densité, puis choisir `fireflies_profile` par map.
Aucun autre système de particules n'est implémenté.

Les priorités existantes restent : défauts → groupes → map → forçage événementiel.
La météo et le caractère extérieur continuent à limiter l'effet. L'API accepte
maintenant `fireflies` :

```ruby
BombanceAmbiance.override_effects(fireflies: false)
BombanceAmbiance.override_effects(28, fireflies: true)
BombanceAmbiance.clear_overrides
```

Ces commandes restent facultatives, limitées à la session et à la map choisie.
Un forçage ne crée aucune zone manquante, ne contourne pas un intérieur ni TJN
désactivé. Aucun événement existant n'a été modifié.

## V4 — densités horaires et météo

Aucune nouvelle horloge : lecture de la période effective des interrupteurs TJN,
des variables natives heure/minute et des bornes de `Yuki::TJN.current_time_set`.
Le profil natif par défaut vaut matin 7–11 h, jour 11–19 h, soir 19–22 h,
nuit 22–7 h. Les bornes saisonnières sont lues, pas recopiées dans la configuration.

Le matin, densité et luminosité descendent progressivement jusqu'à zéro.
Le soir, elles augmentent ; la nuit, elles atteignent le maximum. Les paires
[début, fin] sont interpolées par une courbe douce sur la période réelle.
Une seconde interpolation temporelle évite un saut aux frontières, lors d'un
changement d'horaire ou d'une météo rapide. Un fondu interrompu repart de sa valeur
courante. Les couleurs sont interpolées de la même façon.

La sélection est individuelle : pour une densité de 0,45 sur une zone de 7,
trois lucioles sont pleinement autorisées, la quatrième à 15 %, les trois autres
cachées. Les pulsations individuelles modulent ensuite cette intensité.

| Capture / période | Zone 7 | Zone 6 | Zone 8 | Total après fondu          |
| ----------------- | ------ | ------ | ------ | -------------------------- |
| 7 h 15            | 4      | 3      | 4      | 11, dont certaines faibles |
| Journée           | 0      | 0      | 0      | 0                          |
| 20 h 30           | 3      | 3      | 3      | 9                          |
| Nuit              | 7      | 6      | 8      | 21                         |

La météo effective PSDK est seulement lue. Son facteur multiplie **activité et
luminosité** : pluie légère 0,25 (six lucioles très faibles au total la nuit),
forte pluie/tempêtes 0, brouillard 0,55 (treize individus, certains partiels).
Pour aucune luciole sous brouillard, mettre `fog: 0.0` dans le profil.
Le Fog lui-même, son apparence et ses paramètres ne sont jamais modifiés.

Aucune lecture de la texture nuageuse, aucun appel au masquage V3.
Les points lumineux sont rendus au-dessus de la Plane native des nuages/Fog ;
une ombre de nuage ne les éteint pas.

## V4 — architecture et ressources

Le fichier `00007 Fireflies.rb` est chargé après V3 :

- `FireflyConfiguration` résout le plan horaire/météo et les rectangles mondiaux.
- `FireflyManagerAdapter` ajoute un cache V4 indépendant au Manager et un compteur
  d'animation suivant les updates logiques de map. Les compteurs V1/V2/V3 restent intacts.
- `Fireflies` possède le petit pool, la texture dérivée et l'interpolation.
- `FireflyMapAdapter` met à jour les sprites après les effets existants et les nettoie.

Les zones utilisent les ancrages MapLinker V1. Des maps raccordées autorisées,
de même profil, partagent le repère mondial ; les clés map/zone/individu conservent
les sprites pendant le transfert. Une destination désactivée libère tout le pool.
Aucune donnée V4 n'est attachée à Game_Map, GameState ou aux sauvegardes.

Les positions initiales, phases et vitesses proviennent d'une graine stable
par individu, sans toucher au générateur aléatoire du jeu. Plusieurs oscillations
lentes, bornées et déphasées produisent les trajectoires. Les amplitudes et marges
gardent les sprites dans leur rectangle, sans rebond ni recadrage brutal.
L'affichage arrondit au pixel logique pour éviter le flou ; un déplacement peut
donc avancer d'un pixel à la fois, même si sa trajectoire mathématique est continue.

Une seule image partagée de **7×7** : cœur d'un pixel, halo très faible, bordure
transparente. [Texture source](../../graphics/animations/bombance_ambiance/firefly.png).
Le cache PSDK possède la source. À la création du pool, une copie minuscule ajuste
le halo selon `halo_strength` ; tous les sprites partagent cette copie.
La copie est libérée avec le pool, jamais le bitmap du cache.

Un seul `Sprite::WithColor` par luciole, mélange alpha normal (0), aucune lumière
dynamique ni second sprite de halo. **z=3100 dans le viewport de carte z=0** :
au-dessus des nuages z=3000, sous les viewports des interfaces et dialogues.
La teinte globale TJN continue à s'appliquer, pour intégrer l'effet au décor.
Les lucioles peuvent passer devant un personnage, mais leur cœur fait un pixel.

Pas de sprite/bitmap créé par frame. Le premier démarrage de jour n'alloue pas
le pool avant une période active ; ensuite le jour et les météos défavorables
le cachent et le réutilisent. Les zones hors écran ne calculent pas les sinusoïdes.
Au retour de la caméra, les positions sont évaluées à la phase courante, sans
rattrapage de simulation. Les redessins de menu n'avancent pas cette phase.

## V4 — captures natives et validation

| Période       | Avec lucioles                                           | Même frame sans lucioles                                  |
| ------------- | ------------------------------------------------------- | --------------------------------------------------------- |
| Matin, 7 h 15 | [Capture](tests/captures_v4/morning_with_fireflies.png) | [Témoin](tests/captures_v4/morning_without_fireflies.png) |
| Journée, 15 h | [Capture](tests/captures_v4/day_with_fireflies.png)     | [Identique](tests/captures_v4/day_without_fireflies.png)  |
| Soir, 20 h 30 | [Capture](tests/captures_v4/sunset_with_fireflies.png)  | [Témoin](tests/captures_v4/sunset_without_fireflies.png)  |
| Nuit, 1 h     | [Capture](tests/captures_v4/night_with_fireflies.png)   | [Témoin](tests/captures_v4/night_without_fireflies.png)   |

Mouvement nocturne : [t=0](tests/captures_v4/night_motion_0_with_fireflies.png),
[+2 s](tests/captures_v4/night_motion_2s_with_fireflies.png),
[+6 s](tests/captures_v4/night_motion_6s_with_fireflies.png).
Pluie : [faible](tests/captures_v4/rain_with_fireflies.png),
[forte](tests/captures_v4/hardrain_with_fireflies.png).
[Brouillard](tests/captures_v4/fog_with_fireflies.png).

**68 tests, 24 281 assertions, aucun échec** avec Ruby Studio 3.0.6 et Ruby 3.1.
Les 57 tests V1/V2/V3 restent exécutés ; onze tests V4 ajoutent densités, bornes
saisonnières, transitions interrompues, météo, indépendance des nuages/rayons,
bornes de mouvement sur 180 frames, phases individuelles, caméra, menus, culling,
raccords, intérieurs, maps 36/80, nouvelle session, profils et destruction.

Avant V4, neuf assertions V3 dépendant des anciens réglages échouaient déjà
avec les rayons personnalisés. `tests/rays_regression_config.rb` fournit désormais
les anciens réglages **dans le processus de test seulement**, et les restaure
entre tests. Les tests et captures V3 conservent ainsi leur référence ; les
réglages de jeu restent inchangés. Les tests V4 utilisent la configuration actuelle.

Bancs LiteRGSS : **18 + 13 + 37 + 51 = 119 vérifications natives**.
Comparaisons de pixels V4 : 92 pixels touchés le matin, 128 le soir, 212 la nuit,
zéro le jour et sous forte pluie/tempête. Tous restent dans les rectangles.
10 240 pixels des témoins d'interface/dialogue sont inchangés.
Le mélange alpha réel est vérifié contre une composition calculée : écart maximal
de seulement 1 niveau de canal, compatible avec l'arrondi GPU 8 bits.

Démarrage réel via `Game.rb` et Ruby Studio : huit fichiers chargés, écran-titre
atteint pendant 360 updates sans exception de l'extension. Les scripts existants
Configuration, SessionState, MapAdapter, DiffuseLight, SunRays et leurs textures,
ainsi que clouds.png, ont conservé leurs empreintes pendant cette V4.

### Performances V4

| Mesure                                                         | Résultat du banc |
| -------------------------------------------------------------- | ---------------- |
| 3 zones, 21 lucioles : mise à jour moyenne sur 20 000 ticks    | 0,103 ms         |
| 6 zones de stress, 42 lucioles                                 | 0,203 ms         |
| 21 lucioles hors écran                                         | 0,019 ms         |
| Rendu fenêtre avec / sans lucioles, médianes de 7 × 200 images | 0,589 / 0,552 ms |

Les phases avancent pendant la mesure CPU. Le rendu conserve les autres effets.
Ces chiffres sont locaux au banc, pas une garantie de FPS sur toutes les machines.
Résultats bruts : `tests/native_v4_results.json`, `tests/firefly_capture_checks.json`.

### Fichiers V4

Créés :

- `00007 Fireflies.rb` : système spécialisé complet ;
- `tools/build_firefly_texture.py`, `graphics/animations/bombance_ambiance/firefly.png` ;
- `tests/v4.rb`, `tests/native_v4.rb`, `tests/check_fireflies_captures.py` ;
- `tests/rays_regression_config.rb` : isolation des paramètres des tests historiques ;
- `tests/native_v4_results.json`, `tests/firefly_capture_checks.json`, `tests/captures_v4/`.

Modifiés :

- `00000 AmbiancesConfig.rb` : défauts, trois zones et profil V4 uniquement ;
- `00003 Manager.rb` : ajout de `fireflies` aux effets événementiels autorisés ;
- `tests/support.rb`, `tests/v3.rb`, bancs natifs V1/V2/V3 : support des tests
  et isolation de V4/du profil de référence ;
- README et résultats des bancs régénérés.

Aucune modification des scripts PSDK, TJN, FogFix, Weather Bombance, battlebacks,
maps, tilesets, événements ou sauvegardes. Aucun commit.

### Reproduire et vérifier en partie

Depuis la racine du projet :

```powershell
ruby 'scripts/00026 Configuration Ambiance Bombance/tests/v4.rb'
& "$env:LOCALAPPDATA/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe" 'scripts/00026 Configuration Ambiance Bombance/tests/native_v4.rb'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_fireflies_captures.py'
```

Les captures sont issues du **rendu natif**, avec les vrais graphismes et données
de Route 1. Le banc ne joue pas les événements, dialogues et menus du jeu :
leurs priorités de viewport sont testées avec des témoins opaques. Le Fog météo
est simulé comme contexte ; son rendu personnalisé complet reste à vérifier en partie.

Checklist interactive :

- [ ] Trois rectangles de Route 1 : points visibles mais discrets, halo minuscule.
- [ ] Matin en diminution, jour sans lucioles, soir progressif, nuit plus active.
- [ ] Passage des quatre frontières horaires et changement de profil saisonnier.
- [ ] Caméra mobile/immobile, traversée d'une zone, aucun saut ou flash.
- [ ] Nuage au-dessus d'un groupe : lucioles toujours présentes.
- [ ] Pluie légère, forte pluie, tempête et véritable Fog Bombance.
- [ ] Menu, dialogue et leurs transitions spécifiques : toujours au-dessus.
- [ ] Intérieur, maps 36/80 et map non configurée : aucune luciole résiduelle.
- [ ] Raccords MapLinker, retour, téléportation et session prolongée.
- [ ] Nouvelle partie/chargement : phase réinitialisée, aucun changement de sauvegarde.
- [ ] V1/V2/V3 et retours de combat toujours conformes aux versions validées.

Limites : placement rectangulaire manuel, sans collision/détection de terrain ;
pas de lumière projetée sur le sol/personnages ; la teinte globale TJN s'applique ;
une zone trop petite concentre les individus. Les effets restent suspendus quand
la map n'est pas mise à jour. La validation interactive complète reste distincte
des tests automatisés et du contrôle de démarrage.

---

## Référence et documentation V1/V2/V3

## Configurer les maps

**Un seul fichier à modifier : [00000 AmbiancesConfig.rb](00000%20AmbiancesConfig.rb).**
Les changements prennent effet au prochain démarrage du jeu.

```ruby
DEFAULTS = {
  clouds: :native, diffuse_light: false, rays: false, atmospherics: false,
  outdoor: :native, light_profile: :natural,
  rays_profile: :forest_sunlight, rays_positions: [].freeze,
  rays_max: nil, lunar_rays: false
}.freeze

MAPS = {
  27 => {
    clouds: true, diffuse_light: true, outdoor: true,
    rays: true, rays_profile: :forest_sunlight, rays_max: 10, lunar_rays: true,
    rays_positions: [
      { x: 37.4, y: 20.2, width: 0.85, length: 0.90, angle: -3 }.freeze,
      { x: 38.0, y: 26.6, width: 1.10, length: 0.80 }.freeze,
      { x: 44.7, y: 27.3, width: 0.75, length: 1.00, opacity: 0.85 }.freeze,
      { x: 50.2, y: 20.9, width: 0.90, length: 0.75, angle: 4 }.freeze,
      { x: 44.5, y: 21.1, width: 0.80, length: 0.90 }.freeze,
      { x: 48.4, y: 27.5, width: 0.85, length: 0.85, angle: 2 }.freeze,
      { x: 37.8, y: 16.3, width: 0.75, length: 0.80 }.freeze,
      { x: 40.7, y: 27.1, width: 0.75, length: 0.75, angle: -2 }.freeze,
      { x: 47.0, y: 21.5, width: 0.70, length: 0.80 }.freeze,
      { x: 50.5, y: 25.0, width: 0.75, length: 0.70 }.freeze
    ].freeze
  }.freeze,
  36 => { diffuse_light: false, rays: false }.freeze,
  80 => { diffuse_light: false, rays: false }.freeze
}.freeze
```

| Clé                         | Comportement                                                                                                                                                                 |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `clouds: :native` ou `true` | Conserver les nuages `clouds` déjà fournis par le tileset ou un événement, avec leur rendu et leur continuité V1. Ne crée jamais de nuages sur une map qui n'en possède pas. |
| `clouds: false`             | Masquer uniquement le Plane natif lorsqu'il affiche la texture `clouds`. Ne change ni les données de map, ni son opacité native, ni la météo, ni une autre texture de brume. |
| `diffuse_light: true`       | Autoriser la nouvelle lumière, sous réserve du caractère extérieur, du repli TJN et de la météo effective.                                                                   |
| `diffuse_light: false`      | Aucun Plane de lumière, suppression dès la prochaine actualisation du spriteset.                                                                                             |
| `rays: true`                | Autoriser les rayons V3, sous réserve de placements explicites, du caractère extérieur, de TJN et de la météo.                                                               |
| `rays_profile`              | Profil de rayons dans `RAYS_PROFILES`, initialement `:forest_sunlight`.                                                                                                      |
| `rays_positions`            | Liste de pieds de rayons en coordonnées locales de map ; aucune génération aléatoire.                                                                                        |
| `rays_max`                  | Taille maximale du pool de la map ; nil reprend le profil.                                                                                                                   |
| `lunar_rays`                | Autoriser la lumière lunaire la nuit ; false par défaut, true sur Route 1.                                                                                                   |
| `atmospherics`              | Réserve future. Même à `true`, aucun sprite, texture ou boucle d'effet supplémentaire.                                                                                       |
| `outdoor: :native`          | Lire l'indicateur natif `Yuki::Sw::Env_CanFly`.                                                                                                                              |
| `outdoor: true` / `false`   | Déclarer cette map extérieure / intérieure pour la lumière, sans modifier d'interrupteur.                                                                                    |
| `light_profile: :natural`   | Choisir un profil dans `PROFILES`.                                                                                                                                           |

Une map absente de `MAPS` et des groupes garde ses nuages et brumes natifs et
**ne reçoit ni lumière diffuse ni rayon**. Les maps 36 et 80 gardent leur brouillard.
Le Fog météo n'est jamais commandé par `clouds`.

Différence avec l'ancienne configuration interne V1 : `clouds: false` signifie
désormais **masquer les nuages**, et non revenir au calcul d'origine sans
correction de continuité. Le comportement par défaut reste celui de la V1 validée.

### Exemples

Ajouter une autre route, dans `MAPS`, sans toucher au rendu :

```ruby
28 => { diffuse_light: true, outdoor: true }.freeze,
```

Déclarer explicitement un intérieur :

```ruby
30 => { diffuse_light: false, outdoor: false }.freeze,
```

Garder la lumière diffuse mais masquer les nuages d'une map :

```ruby
27 => { clouds: false, diffuse_light: true, outdoor: true }.freeze,
```

Sur l'entrée Route 1 livrée en V3, changer uniquement la valeur `clouds` permet
de conserver aussi ses rayons et leurs placements ; l'exemple abrégé ci-dessus
ne contient que la lumière diffuse.

Créer un groupe optionnel (aucun groupe actif dans la livraison) :

```ruby
GROUPS = {
  routes_ensoleillees: {
    maps: [27, 28, 29],
    effects: { diffuse_light: true, outdoor: true, light_profile: :natural }
  }
}.freeze

# Exception au groupe, dans MAPS :
29 => { diffuse_light: false }.freeze,
```

### Priorités et événements

Les autorisations suivent, du moins au plus prioritaire :
**défauts → groupes dans leur ordre de déclaration → map → forçage d'effet par événement**.

La texture et les paramètres de fog restent ceux de PSDK, des tilesets et des
événements. `clouds: true` ne force pas de texture ; `clouds: false` masque
uniquement `clouds`, même si un événement vient de choisir cette texture.
Une autre texture, par exemple une brume forestière, reste intégralement native.

**La météo effective PSDK intervient ensuite comme limite de lumière.** Un
événement forçant `diffuse_light: true` ne contourne donc pas l'extinction sous
Fog. Les commandes météo existantes restent maîtresses de la météo ; le
gestionnaire la lit sans l'écrire. Le caractère extérieur reste une décision
de configuration : l'API d'événement ne contourne pas `outdoor: false`.

Commandes script facultatives dans un événement :

```ruby
# Map courante uniquement :
BombanceAmbiance.override_effects(diffuse_light: false)
BombanceAmbiance.override_effects(rays: false)
BombanceAmbiance.override_effects(clouds: false)

# Map explicitement désignée :
BombanceAmbiance.override_effects(27, clouds: true, diffuse_light: true)

# Retrouver la configuration de la map :
BombanceAmbiance.clear_overrides
BombanceAmbiance.clear_overrides(27)
```

Les forçages restent limités à la map désignée. Ils persistent pendant la session,
y compris au retour sur cette map, jusqu'à `clear_overrides`, une nouvelle partie
ou un chargement. Ils ne sont pas sauvegardés. Une scène temporaire doit appeler
`clear_overrides` à sa fin. Pour un état narratif persistant, l'événement peut
réappliquer le forçage depuis ses interrupteurs habituels.

L'API accepte les quatre clés d'effet ; `:native` est utile pour les nuages.
Pour les nouveaux effets, seule la valeur `true` autorise l'effet.

## Rayons V3 : densité horaire

Dix emplacements fixes sont définis sur Route 1, dans le secteur x=37 à 51,
y=16 à 28 : chemin nord, clairière, chemin est et bordures sud. Les quatre
emplacements précédents sont conservés. Aucun placement aléatoire ni modification
des maps. L'ordre de la liste donne l'ordre d'apparition : les trois premiers
peuvent notamment servir de rayons lunaires.

Chaque rayon reste **un seul Sprite::WithColor**, faisceau et pied dans une
texture partagée. Le cœur est renforcé (alpha maximal 214 au lieu de 176), les
contours restent transparents, la tache au sol est moins dominante (amplitude
80 au lieu de 145 dans le générateur). Aucun masque individuel de personnage.

### Heure et périodes natives

L'extension lit uniquement les variables natives `Yuki::Var::TJN_Hour` et
`TJN_Min`, utilisées par TJN en temps virtuel comme en temps réel. Elle lit aussi
`Yuki::TJN.current_time_set` (méthode privée appelée en lecture seule).
Elle ne crée pas d'horloge et ne modifie ni les variables ni les interrupteurs TJN.

Les interrupteurs TJN déterminent toujours la période effective. Le profil natif
par défaut donne matin **7–11 h**, journée **11–19 h**, soir **19–22 h**, nuit
**22–7 h**. Ainsi 18 h appartient encore à la journée. En hiver, les bornes
deviennent 10/12/16/17 h : les pics automatiques suivent ces bornes.

| Période | Minimum aux bornes | Maximum au pic | Pic configuré                   | RGB         | Opacité | Angle |
| ------- | ------------------ | -------------- | ------------------------------- | ----------- | ------- | ----- |
| Matin   | 2                  | 5              | milieu TJN : 9 h par défaut     | 255,232,176 | 92      | +18°  |
| Journée | 5                  | 10             | 15 h                            | 255,249,226 | 110     | +24°  |
| Soir    | 3                  | 6              | milieu TJN : 20 h 30 par défaut | 255,207,151 | 80      | +32°  |
| Nuit    | 1                  | 3              | 1 h                             | 183,210,255 | 58      | +24°  |

Une courbe douce monte du minimum au pic puis redescend vers le minimum.
La nuit traverse minuit sans discontinuité. Un pic explicite situé hors de la
période saisonnière est ramené près de sa borne. `peak_hour: nil` choisit son milieu.

La densité cible peut être fractionnaire : **5,78 signifie cinq rayons à pleine
intensité et un sixième à 78 %**, les quatre autres complètement éteints. Les
changements de densité sont interpolés sur 180 updates logiques ; les couleurs,
angles et intensités sur 240 updates. Un changement en cours de fondu repart
de la valeur courante. Il n'y a donc pas dix faisceaux constamment faibles.

### Réglages dans AmbiancesConfig.rb

| Réglage                                             | Sens                                                                   |
| --------------------------------------------------- | ---------------------------------------------------------------------- |
| map : `rays`, `rays_profile`                        | Autoriser les rayons et choisir le profil                              |
| map : `rays_max`                                    | Capacité de la map ; `nil` reprend `count` du profil                   |
| map : `lunar_rays`                                  | Rayons nocturnes ; défaut false, true sur Route 1                      |
| map : `rays_positions`                              | Pieds en tuiles locales, fractions autorisées, dans l'ordre de densité |
| placement : `width`, `length`, `opacity`            | Multiplicateurs, défaut 1                                              |
| placement : `angle`                                 | Degrés ajoutés à l'angle de période, défaut 0                          |
| profil : `count`                                    | Capacité par map par défaut : 10                                       |
| profil : `width`, `length`, `mask_scale`            | 24 px, 108 px, échelle globale 1                                       |
| période : `count`, `minimum`, `peak_hour`           | Maximum, minimum, pic en heures décimales ou nil                       |
| période : `rgb`, `opacity`, `angle`                 | Couleur, intensité avant masque/météo, inclinaison positive            |
| `density_transition_steps`                          | 180 ticks, environ 3 s à 60 updates/s                                  |
| `time_transition_steps`, `weather_transition_steps` | 240 et 180 ticks                                                       |
| `wave_steps`, `variation`                           | Oscillation discrète : 2400 ticks et 0,10                              |
| `sway_x`, `sway_y`                                  | Déplacement lent maximal de 0,4 et 0,15 px                             |
| `cloud_threshold`, `cloud_softness`                 | Extinction à 0,20 ; atténuation dès 0,08 (largeur 0,12)                |
| `cloud_fade_steps`                                  | Fondu nuageux complet : 36 ticks                                       |
| `cloud_sample_steps`                                | Cinq points tous les quatre ticks par rayon actif                      |

Exemple : une autre route avec trois emplacements, sans rayons lunaires :

```ruby
28 => {
  rays: true, outdoor: true, rays_max: 3, lunar_rays: false,
  rays_profile: :forest_sunlight,
  rays_positions: [
    { x: 20, y: 18 },
    { x: 25, y: 22, width: 0.8 },
    { x: 32, y: 19, length: 0.9, opacity: 0.85 }
  ]
}.freeze,
```

Exemple de période à remplacer dans le profil (les autres périodes restent définies) :

```ruby
day: {
  rgb: [255, 247, 220].freeze, opacity: 105, angle: 24.0,
  count: 8, minimum: 3, peak_hour: 14.5
}.freeze,
```

Pour un réglage différent par map, dupliquer le profil complet sous un autre nom
et choisir ce nom dans `rays_profile`. Conserver `0 <= minimum <= count` et des
capacités entières positives. La capacité et le nombre de positions limitent le
nombre affichable même si le pic de période demande davantage de rayons.

### Nuages, météo et profondeur

Le lecteur réutilise la texture de la **Plane native @fog**, après FogFix et V1,
avec ses origines persistantes, zooms, opacité, couleur et ton réels.
`clouds.png` contient des pixels transparents blancs et une ombre
RGB(37,33,30) alpha 255. Le mélange normal et l'opacité native 90/255 donnent
environ 0,306 d'obscurcissement dans une ombre opaque.

Cinq points sont pris au pied, tournés et mis à l'échelle avec le rayon.
La formule est celle du shader : `floor(origin + position / zoom) modulo taille`.
La moyenne alpha × obscurcissement RGB × opacité passe par le seuil doux puis le
fondu. Elle multiplie la densité locale × intensité TJN × météo × variation.
Les nuages absents/invisibles ou `clouds: false` donnent une transmission cible
de 1. Les autres brumes ne sont jamais échantillonnées.

La météo effective PSDK est conservée : pluie ×0,08 ; fortes pluies, Fog, neige,
grêle, tempête et météo inconnue éteignent les rayons. **Fog impose zéro**, même
avec un profil ou un événement qui demande de la lumière. `lunar_rays: false`
éteint les rayons nocturnes de la map. Sans TJN, le repli rayons est nil (OFF),
indépendamment du repli V2 qui reste `:day`.

Le sprite est à **z=2000 dans le viewport de carte z=0**, au-dessus du décor et
des personnages, sous les nuages z=3000. Menus et dialogues utilisent leurs
viewports supérieurs (200/5000 et messages 20000 par défaut). Le joueur reçoit
la lumière du même sprite ; aucun traitement individuel. Les cimes peuvent
aussi être éclairées, d'où les placements manuels.

### Continuité et ressources

Positions mondiales = (ancrage MapLinker + position locale) ×16, caméra =
display/8 + ancrage×16. Les clés map_id:index conservent les sprites lors des
raccords entre maps autorisées de même profil, y compris les placements voisins.
Chaque map possède sa capacité ; un raccord peut donc présenter les pools de
plusieurs maps. Les maps désactivées, dont 36/80, ne reçoivent jamais ces rayons.

Le pool est créé une fois pour les emplacements configurés, jusqu'à la capacité.
Une baisse de densité, la nuit ou Fog **cache les sprites, sans les détruire**.
Ils sont libérés à la sortie vers une map désactivée, au changement de profil,
à la suppression d'un emplacement ou à la destruction du spriteset. Aucun objet
graphique n'est enregistré dans les sauvegardes.

Les rayons éteints/hors champ ne lisent aucun pixel de nuage. Les autres effectuent
cinq lectures tous les quatre ticks ; les redessins supplémentaires ne relisent
pas la texture. Une copie CPU de la texture native est conservée (~1 Mio RGBA),
remplacée seulement si cette texture change. Le cache PSDK garde ses bitmaps.
Les changements de minute ne reconstruisent ni les placements ni le plan V2.

## Profils lumineux et transitions

| Période TJN | RGB           | Opacité locale maximale avant modulation |
| ----------- | ------------- | ---------------------------------------- |
| Matin       | 247, 235, 208 | 26 / 255                                 |
| Journée     | 242, 244, 232 | 24 / 255                                 |
| Crépuscule  | 245, 218, 205 | 25 / 255                                 |
| Nuit        | 181, 203, 233 | 14 / 255                                 |

Les valeurs se règlent dans `PROFILES`. Dupliquer `natural` sous un autre nom
permet un profil particulier via `light_profile`. Chaque profil doit contenir
les quatre périodes. Le masque possède de nombreuses zones transparentes :
l'intensité moyenne est beaucoup plus faible que ces maxima locaux. La nuit
reste volontairement plus faible ; aucun filtre uniforme n'est ajouté.

`LIGHT` règle la texture, la profondeur, le défilement et la modulation :

- `step_x: 0.012`, `step_y: -0.006` pixels par update logique, soit environ
  0,72 et −0,36 pixel par seconde à 60 updates/s.
- `variation: 0.06` : faible variation d'opacité par deux sinusoïdes lentes,
  dont la principale a une période `wave_steps: 1500` updates.
- `transition_steps: 180` : interpolation progressive des RGB et de l'opacité,
  environ trois secondes à 60 updates/s. Une nouvelle cible repart de la valeur
  courante, y compris lors de changements rapides de météo.
- `disabled_tjn_period: :day` : repli lorsque TJN est désactivé. Choisir une
  autre période ou `nil` pour désactiver entièrement la lumière.

Les périodes viennent exclusivement des interrupteurs TJN existants. Aucun
cycle horaire supplémentaire n'est créé ; aucun ton d'écran ou de viewport n'est
modifié par le code de production. Les ticks servent seulement à l'animation.
La lumière suit les updates logiques de `Game_Map`, pas le taux de rendu du
moniteur. Redessiner un menu sans mettre à jour la map ne fait pas avancer sa phase.

`WEATHER_LIGHT` multiplie l'intensité : ciel dégagé `1`, pluie `0.3`, forte pluie
`0.15`, Fog `0`, soleil `0.8`, fort soleil `0.5`, sable `0`, grêle `0.2`, neige
`0.3`, vent fort `0.25`. Une météo inconnue prend `UNKNOWN_WEATHER_LIGHT`, ici `0`.
Les changements météo sont interpolés comme les périodes. Après extinction
complète sous Fog, le Plane est libéré ; au retour du ciel dégagé, il revient
progressivement depuis zéro, avec la phase de session conservée. Un changement
d'heure ou de météo pendant une transition ne recrée pas le Plane encore actif.

Une sortie vers une map désactivée supprime immédiatement le Plane au reload,
avant son premier rendu : le fondu ne continue pas sur la map voisine. Au retour,
l'apparition est progressive et la phase reprend celle de la session.

## Architecture, continuité et superposition

Le gestionnaire unique conserve un contexte réutilisé (map, zone, période,
météo, extérieur), les autorisations résolues et un profil cible immuable.
Ces deux derniers objets sont recalculés uniquement si leur contexte change.

La V1 reste responsable des nuages natifs : phase intégrée depuis les offsets
PSDK, vitesse inchangée, et ancrages spatiaux déduits des offsets MapLinker
**avant** leur réinitialisation. Un raccord a pour ancrage de destination
`ancrage_source - offset_MapLinker`. La lumière réutilise ces mêmes ancrages.

Origines : nuages = `display / 4 + phase_native + ancrage * 32` avec le zoom
FogFix inchangé de 0,5 ; lumière = `display / 8 + phase_lumiere + ancrage * 16`
avec zoom 1. Entre deux maps configurées raccordées, le Plane est conservé et
la coordonnée mondiale reste continue. Les transferts sans raccord réutilisent
l'ancrage connu de la destination, sinon zéro, sans remettre à zéro la phase.
La phase lumineuse est suspendue sur les maps désactivées et conservée pour
le retour. La phase des nuages continue selon les règles V1.

La lumière est **un seul Plane au z=1 dans le viewport de map**. Les tuiles de
sol natives sont au z=0 ; les tuiles de priorité supérieure et les personnages
visibles sont au-dessus, ainsi que les viewports d'interface. La faible opacité
n'est donc pas le mécanisme de protection des personnages. Le Fog natif conserve
son z=3000. Le ton TJN s'applique ensuite normalement au viewport, lumière comprise.

Ce choix éclaire principalement le sol : les cimes et tuiles placées au-dessus
ne reçoivent pas cette couche. Les reflets sous le sol ou sprites personnalisés
placés à z≤1 peuvent la recevoir. Modifier `z` change cette garantie ; conserver 1.

Le spriteset possède et libère son Plane ; `RPG::Cache` possède la texture
partagée. Ni texture, ni Plane, ni Color ne sont créés à chaque frame. Les
ressources sont libérées à la destruction du spriteset, à l'extinction météo
ou sur une destination désactivée. La session et les forçages sont réinitialisés
par le callback PSDK de nouvelle partie / chargement. Aucun champ n'est ajouté
aux sauvegardes.

`atmospherics` reste une réserve sans moteur de rendu actif. Le registre peut
accueillir un futur adaptateur ; il n'instancie rien à lui seul. Aucun adaptateur
de combat n'est installé.

## Fichiers livrés

Fichiers de l'extension, avec les évolutions depuis V1 :

| Fichier                                                                           | État / rôle                                                                   |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `00000 AmbiancesConfig.rb`                                                        | Nouveau : réglages utilisateur, défauts, groupes, maps, profils et météo      |
| `00001 Configuration.rb`                                                          | Modifié : priorités et profil lumineux cible                                  |
| `00002 SessionState.rb`                                                           | Modifié : phase et tick numériques de lumière ajoutés à la session V1         |
| `00003 Manager.rb`                                                                | Modifié : contexte mémorisé, cache, forçages et masquage optionnel des nuages |
| `00004 MapAdapter.rb`                                                             | Modifié : avancement lumineux sur l'update logique existant                   |
| `00005 DiffuseLight.rb`                                                           | Nouveau : Plane, interpolation et cycle de vie                                |
| `00006 SunRays.rb`                                                                | Nouveau V3 : sprites localisés, interpolation, visibilité et cycle de vie     |
| `tools/build_diffuse_texture.py`                                                  | Nouveau : génération déterministe de la ressource, hors jeu                   |
| `tests/support.rb`, `tests/run.rb`                                                | Adaptés à la configuration V2, méthodes natives et données réelles            |
| `tests/v2.rb`                                                                     | Nouveau : tests V2, inclut toute la suite V1                                  |
| `tests/native_visual.rb`                                                          | Adapté : comparer les nuages avec la lumière désactivée                       |
| `tests/native_v2.rb`, `tests/check_captures.py`                                   | Nouveaux : captures, mesures et comparaisons de pixels                        |
| `tests/native_results.json`, `tests/captures/`                                    | Résultats V1 régénérés, 11 captures                                           |
| `tests/native_v2_results.json`, `tests/capture_checks.json`, `tests/captures_v2/` | Nouveaux résultats V2, 13 captures                                            |
| `README.md`                                                                       | Documentation centrale V1/V2/V3, réglages et validation                       |

**Historique de l'implémentation V3** — modifiés : `00000 AmbiancesConfig.rb`, `00001 Configuration.rb`,
`00002 SessionState.rb`, `00003 Manager.rb`, `tests/support.rb`,
`tests/native_visual.rb`, `tests/native_v2.rb` et ce README. Les deux bancs natifs
précédents désactivent explicitement les rayons pour comparer leurs références.
`00004 MapAdapter.rb` et `00005 DiffuseLight.rb` restent inchangés pour cette V3.

**Créés pour cette V3** : `00006 SunRays.rb`, `tools/build_ray_texture.py`,
`tests/v3.rb`, `tests/native_v3.rb`, `tests/check_rays_captures.py`,
`tests/native_v3_results.json`, `tests/ray_capture_checks.json` et les captures
de `tests/captures_v3/`. Les mesures des bancs natifs V1/V2 ont été régénérées.

**Nouvelle ressource V3** hors extension :
`graphics/animations/bombance_ambiance/forest_sunlight.png`, 80×144 RGBA.
Ce masque contient un faisceau irrégulier et une tache au sol, avec bords
entièrement transparents, alpha maximal 214, et échantillonnage de deux pixels.
La géométrie est construite mathématiquement, sans flou appliqué à une image
source. Les RGB transparents sont blancs pour éviter les franges sombres.
Le point d'ancrage du masque est (40,124). Le générateur est déterministe et
reste hors exécution du jeu ; le masque est chargé par le cache graphique PSDK.

La ressource V2, conservée sans changement, est
`graphics/animations/bombance_ambiance/diffuse.png` : 320×240 RGBA, masque
irrégulier périodique échantillonné sur une grille de deux pixels. Construite
mathématiquement, sans ressource tierce. Alpha de 0 à 255, moyenne 39,37,
raccords périodiques sur les deux axes. Le générateur Python nécessite Pillow ;
Python n'est pas requis en jeu.

PSDK installé, FogFix, Weather/Fog Bombance, Fog de combat, malus de précision,
Marsh, Kit, BBBB, TJN, rencontres, maps, tilesets et événements n'ont pas été
modifiés par cette V3. Aucun paramètre de brouillard existant n'a été modifié.
Le dépôt contient déjà d'autres modifications sans rapport avec cette extension.

**Amélioration de densité horaire** : `00000 AmbiancesConfig.rb`,
`00001 Configuration.rb`, `00003 Manager.rb` et `00006 SunRays.rb` changent côté jeu.
Le générateur et la texture de rayon sont ajustés, sans nouvelle texture.
Tests, captures et documentation sont mis à jour ; aucune modification des maps,
événements, scripts PSDK, FogFix, Weather Bombance ou battlebacks. Aucun commit.

## Tests et captures

### Résultats V3 — densité horaire

**57 tests, 1 384 assertions, aucun échec**, sur Ruby Studio 3.0.6 et Ruby 3.1.
Les suites V1/V2 sont conservées. Les anciens tests V3 d'extinction nocturne et de
destruction sous Fog sont adaptés au nouveau contrat : lune optionnelle et pool
caché/réutilisé, toujours sans lumière sous Fog.

Couverture : pics 11/15/18 h, matin/soir/nuit, passage de minuit, bornes hivernales,
couleurs, retargetage pendant un fondu, capacité par map, lune désactivée, Fog
prioritaire, budget de cinq lectures par rayon tous les quatre ticks, aucun
échantillonnage des sprites éteints, aucune recréation lors des changements d'heure
ou météo. Les tests de raccords MapLinker, transitions vers maps désactivées,
retours, chargement, nuages et cycles de vie restent exécutés.

Bancs natifs : **18 vérifications V1 + 13 V2 + 37 V3**. Les raccords V1 restent
identiques pixel par pixel ; les résultats de pixels V2 sont inchangés.
Le démarrage réel par `Game.rb`, avec le Ruby fourni par Studio, charge les sept
fichiers dans l'ordre et atteint `Scene_Title` pendant 360 updates sans exception
de l'extension. Le lecteur natif TJN est disponible.

Les comparaisons natives vérifient aussi :

- 76 800 pixels de projection nuageuse, coordonnées négatives et zoom FogFix compris ;
- cycle transmission 1 → 0,583 → 0 → 1, disparition et retour sans toucher aux nuages ;
- Fog : aucun pixel de rayon ; pluie très atténuée (écart maximal de canal 6) ;
- nuit : teinte dominante bleu argenté, trois rayons au pic de 1 h ;
- joueur traversant : 0, puis 278, puis 77 pixels opaques éclairés ;
- 5 120 pixels d'interface et 5 120 pixels du témoin de viewport de dialogue inchangés.

### Captures comparatives

Les captures horaires isolent les rayons en masquant les nuages **uniquement dans
le banc**, avec V2 active. Le même cadrage et les tons du profil TJN natif par
défaut permettent de comparer la densité. Les captures de nuages ci-dessous
emploient au contraire la vraie Plane native en mouvement.

| Heure | Rayons visibles après fondu | Avec rayons                                        | Témoin sans rayons                                   |
| ----- | --------------------------- | -------------------------------------------------- | ---------------------------------------------------- |
| 11 h  | 5                           | [Capture](tests/captures_v3/hour_11_with_rays.png) | [Témoin](tests/captures_v3/hour_11_without_rays.png) |
| 15 h  | 10                          | [Capture](tests/captures_v3/hour_15_with_rays.png) | [Témoin](tests/captures_v3/hour_15_without_rays.png) |
| 18 h  | 6, dont le sixième à 78 %   | [Capture](tests/captures_v3/hour_18_with_rays.png) | [Témoin](tests/captures_v3/hour_18_without_rays.png) |
| 1 h   | 3 lunaires                  | [Capture](tests/captures_v3/hour_01_with_rays.png) | [Témoin](tests/captures_v3/hour_01_without_rays.png) |

Autres périodes : [matin 9 h](tests/captures_v3/morning_with_rays.png),
[soir 20 h 30](tests/captures_v3/sunset_with_rays.png).
Nuages : [clair](tests/captures_v3/cloud_clear_with_rays.png),
[partiel](tests/captures_v3/cloud_partial_with_rays.png),
[masqué](tests/captures_v3/cloud_shadow_with_rays.png),
[réapparu](tests/captures_v3/cloud_reappeared_with_rays.png).
Joueur : [avant](tests/captures_v3/player_crossing_0_with_rays.png),
[dans le rayon](tests/captures_v3/player_crossing_1_with_rays.png),
[sortie](tests/captures_v3/player_crossing_2_with_rays.png).

Ce sont des captures **LiteRGSS natif**, avec les données et graphismes de Route 1,
pas une partie complète. Les sprites de personnages sont déplacés par le banc ;
les témoins UI/dialogue utilisent les priorités natives mais pas les scripts des
menus et dialogues interactifs. Les transitions personnalisées et les interactions
complètes restent à vérifier en partie.

### Performances avec dix rayons

Mise à jour CPU moyenne : **0,0934 ms** sur 20 000 ticks, incluant les
échantillonnages nuageux tous les quatre ticks. Au pic, 50 pixels sont lus par lot ;
au pic lunaire, seulement 15. Aucun pixel n'est lu sous Fog après le fondu.

Rendu natif, médianes de sept lots de 200 images : **0,5631 ms avec** et
**0,5476 ms sans** rayons, soit environ +0,0154 ms dans ce banc. Ces mesures ne
constituent pas une garantie globale de FPS. Une texture partagée, dix sprites
conservés et une copie CPU des nuages ; aucun nouveau sprite lors des variations
de densité. Données brutes : `tests/native_v3_results.json` et
`tests/ray_capture_checks.json`.

### Référence V1/V2

**34 tests, 1 071 assertions, zéro échec, erreur ou test ignoré**, avec Ruby 3.1
et le Ruby 3.0.6 fourni par Studio. Les 22 tests V1 sont inclus. Couverture V2 :
quatre périodes, interpolation, météo rapide, Fog, pluie, météo inconnue, repli
TJN, transferts, intérieur, téléportation, redessins de menu, réinitialisation
de chargement, priorités de configuration, forçages, cache et destruction.

Les tests vérifient Route 1 → Bourg-Guignon → Route 1, les maps 36 et 80, et la
continuité vers une seconde map temporairement activée dans le banc. Une
activation ou un forçage ne se propage pas à une autre map. Les méthodes de
transfert, map et Fog proviennent du SDK installé ; les événements et l'interface
complète du jeu sont simulés dans le banc fonctionnel.

Le banc LiteRGSS V1 passe **18 vérifications** : égalité exacte des PNG natifs
et corrigés sur la même map et aux raccords, opacité, zoom et texture natifs.
Le banc LiteRGSS V2 passe **13 vérifications** de réutilisation/destruction,
météo et transferts. La comparaison de pixels confirme :

- 506 pixels opaques du joueur et du Pokémon témoin inchangés avec/sans lumière ;
- 5 120 pixels d'interface témoin inchangés ;
- une contribution faible pour les quatre périodes : écart maximal de canal de
  15/18/17/9 niveaux pour matin/jour/soir/nuit ;
- aucun saut anormal d'alpha au bord du masque répétable.

Captures LiteRGSS 320×240, même extrait de Route 1 (x=32, y=15, 20×15 tuiles) :

| Matin                                        | Journée                              | Crépuscule                                 | Nuit                                     |
| -------------------------------------------- | ------------------------------------ | ------------------------------------------ | ---------------------------------------- |
| [morning.png](tests/captures_v2/morning.png) | [day.png](tests/captures_v2/day.png) | [sunset.png](tests/captures_v2/sunset.png) | [night.png](tests/captures_v2/night.png) |

Chaque capture possède une version `_without_light` au même instant pour
comparer uniquement la contribution lumineuse. Série de déplacement :
[départ](tests/captures_v2/motion_00.png), [+10 s](tests/captures_v2/motion_10s.png),
[+30 s](tests/captures_v2/motion_30s.png), à 60 updates/s. Les nuages natifs
continuent eux aussi à se déplacer dans cette série.

**Ce sont des captures d'un banc natif, pas d'une partie complète.** Elles
utilisent les vraies tuiles de Route 1 et ressources de personnages, une frame
fixe d'autotile et les tons du profil TJN natif par défaut. Les personnages
sont des témoins statiques ; les événements de map ne s'exécutent pas. Un profil
TJN particulier ou une transition personnalisée doit être vérifié en partie.

### Mesures de référence V2, avant V3

Sur cette machine, avec 7 échantillons alternés de 200 rendus du banc :

| Mesure                                           | Résultat                                      |
| ------------------------------------------------ | --------------------------------------------- |
| Update CPU de lumière, moyenne sur 20 000 appels | 0,00367 ms/appel                              |
| Rendu de fenêtre sans lumière, médiane           | 0,5555 ms/image                               |
| Rendu de fenêtre avec lumière, médiane           | 0,5750 ms/image                               |
| Différence des médianes                          | **+0,0195 ms/image**                          |
| Ressources lumineuses                            | 1 Plane, 1 texture partagée, Color réutilisée |
| Surcoût de l'adaptateur des nuages, banc V1      | 0,00237 ms/appel                              |

Les temps de fenêtre incluent la soumission du rendu, sans constituer une
mesure GPU isolée ou une garantie pour tout le jeu. Les conversions numériques
Ruby/LiteRGSS produisent encore des allocations Ruby (environ 34 par update
lumineux dans ce banc), mais aucune allocation graphique par frame. Les
données brutes et les échantillons figurent dans les JSON de tests.

## Reproduction et validation en partie

Depuis la racine du projet :

```powershell
ruby 'scripts/00026 Configuration Ambiance Bombance/tests/v2.rb'
ruby 'scripts/00026 Configuration Ambiance Bombance/tests/v3.rb'
$studioRuby = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries/ruby.exe'
$minitestLib = 'C:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib'
& $studioRuby -I $minitestLib 'scripts/00026 Configuration Ambiance Bombance/tests/v2.rb'
& $studioRuby -I $minitestLib 'scripts/00026 Configuration Ambiance Bombance/tests/v3.rb'
& $studioRuby 'scripts/00026 Configuration Ambiance Bombance/tests/native_visual.rb'
& $studioRuby 'scripts/00026 Configuration Ambiance Bombance/tests/native_v2.rb'
& $studioRuby 'scripts/00026 Configuration Ambiance Bombance/tests/native_v3.rb'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_captures.py'
python 'scripts/00026 Configuration Ambiance Bombance/tests/check_rays_captures.py'
```

Les bancs natifs ouvrent brièvement une fenêtre et écrivent leurs résultats
uniquement dans cette extension. Ils ne démarrent pas la partie et ne lisent
ni n'écrivent de sauvegarde Pokémon. Les tests ne sont pas chargés en jeu.

Checklist restant à exécuter dans une partie réelle :

- [ ] V3 : Route 1 près des dix coordonnées configurées, densité 5/10/6/3 à 11/15/18/1 h.
- [ ] V3 : passage Morning → Day → Sunset → Night, couleurs progressives, lune bleue et désactivation par map respectée.
- [ ] V3 : caméra en mouvement et à l'arrêt, ouverture/fermeture de menu, animation presque fixe sans clignotement.
- [ ] V3 : pluie très atténuée, forte pluie/Fog/tempête sans rayons après fondu, météo événementielle respectée.
- [ ] V3 : raccord entre deux maps de même profil avec placements explicites ; pas de rayon dupliqué ou décalé.
- [ ] V3 : bâtiments, maps 36/80 et maps non configurées sans rayon ; retour cohérent sur Route 1.
- [ ] V3 : joueur, suiveur et PNJ légèrement éclairés dans le faisceau ; vrais dialogues et interfaces inchangés.
- [ ] V3 : ombre nuageuse au pied du rayon, extinction puis réapparition progressive, sans clignotement.
- [ ] Route 1 aux quatre périodes, avec le profil TJN réellement utilisé ; nuit toujours sombre.
- [ ] Changement de période sans flash, dialogue ouvert puis fermé.
- [ ] Route 1 ↔ Bourg-Guignon et Route 1 ↔ Cocovin ; nuages V1 toujours continus.
- [ ] Menu, bâtiment, sortie, retour et téléportation ; aucune lumière sur la map désactivée.
- [ ] Deux maps raccordées activées temporairement par configuration ; continuité spatiale.
- [ ] Pluie, Fog et changements météo rapides imposés par les événements existants.
- [ ] Forêt Hantée 36 et 80 : brouillard habituel, aucune nouvelle lumière.
- [ ] Joueur, suiveur, dialogues et interfaces lisibles ; transitions personnalisées intactes.
- [ ] Sauvegarde/rechargement et nouvelle partie : reprise douce, aucun état d'une autre session.
- [ ] Combat Fog simple/double/triple, sortie de combat : rendu, malus et battlebacks inchangés.
- [ ] Session prolongée avec transferts : pas de sprites résiduels ni ralentissement perceptible.

La V1 était validée en jeu et la V2 fonctionnait avant cette intervention. La
validation interactive complète de cette V3, notamment des combats et transitions spécifiques au projet,
reste distincte des tests automatisés décrits ci-dessus.
