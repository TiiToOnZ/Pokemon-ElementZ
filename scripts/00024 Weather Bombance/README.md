# Météo Bombance — extension du brouillard PSDK

> Mise à jour visuelle du 13 octobre 2026 : voir [VISUAL_REPORT.md](VISUAL_REPORT.md)
> pour les deux nappes animées, les captures Marsh et les nouveaux tests.
> Le rapport initial ci-dessous décrit la version d'origine ; l'opacité du voile
> a depuis été réglée à 150 dans le projet et ce réglage a été conservé.

Implémentation locale du 7 octobre 2026, sur le SDK installé et audité pour
Bombance/PSDK 26.60. PSDK reste l'unique source de vérité météo.
Le numéro 00024 était libre après 00023 Achievements Bombance.

## Fichiers et périmètre

| Création | Rôle |
| --- | --- |
| `00001 WeatherIntegration.rb` | Configuration, précision Fog, entrée en combat, présentation initiale, correction Anti-Brume |
| `00002 FogVisual.rb` | Voile persistant et animation finie enregistrée dans WeatherSprite |
| `tests/support.rb` | Banc isolé chargeant les méthodes/classes réelles du SDK et deux extensions existantes |
| `tests/weather_test.rb` | Tests gameplay, annonces, synchronisation et cycle de vie |
| `tests/native_visual.rb` | Composition graphique LiteRGSS avec les textures du projet |
| `tests/audit_events.rb` | Lecture des maps/événements pour les interrupteurs 39 et 138 |
| `tests/native_{1,2,3}v{1,2,3}_{clear,fog}.png` | Six captures comparatives du banc graphique |
| `README.md` | Ce rapport et les commandes de reproduction |

Aucun fichier préexistant modifié par cette intervention. Aucun changement dans
le SDK, `00000 Plugins`, SOS, Boss, BBBB, InfoBars, ZVBattleMessages, Battle Bases,
Triple Battle Position, les battlebacks, maps, événements ou textes.
Les modifications de données et sauvegardes déjà présentes dans le répertoire
de travail sont étrangères à cette extension. Aucun commit ni staging effectué.

Le chargeur PSDK ne charge que les scripts dont le nom commence par 3 à 5 chiffres
suivis d'un espace ou underscore : les tests ne s'exécutent pas en jeu.

## Architecture et hooks

| Cible | Extension locale | Comportement |
| --- | --- | --- |
| `PFM::Environment` | `prepend EnvironmentEntry` | Méthode de préparation unique du prochain combat |
| `Battle::Scene` | `prepend SceneEntry` | Préparation avant `initialize`, présentation avant `show_enter_event` natif |
| `Battle::Effects::Weather::Fog` | `prepend FogAccuracy` | Multiplicateur de précision via le pipeline natif |
| `Battle::Move::Defog` | `prepend DefogMessage` | Suppression native du brouillard avant le traitement restant d'Anti-Brume |
| `Battle::Visual` | `prepend VisualAmbience` | Création/suppression du voile, défilement, nettoyage |
| `UI::WeatherSprite` | `register(:fog, FogAppearance)` | Animation finie de 0,6 seconde |

Le chemin reste `Environment → current_weather_db_symbol → raw_weather_effect
→ Weather::Fog`. Les seuls objets supplémentaires sont graphiques. Le booléen
de présentation initiale et la porte d'entrée du cycle de vie visuel ne décrivent
pas la météo : l'existence du voile dépend toujours de `raw_weather_effect.fog?`.
Aucun objet graphique n'est ajouté à Environment ou aux sauvegardes.

## Précision

`FOG_ACCURACY_MULTIPLIER = 0.8` est regroupé avec les réglages visuels au début
de `00001 WeatherIntegration.rb`. Il suffit de changer cette valeur, par exemple
en `0.75`, pour modifier le malus.

`Fog#chance_of_hit_multiplier` appelle `super`, puis multiplie son résultat par
0,8. `Move#chance_of_hit` et `Logic#each_effects` restent inchangés. Les autres
effets, objets, talents et niveaux de précision/esquive continuent à se combiner.

| Précision de base, sans autre modificateur | Résultat avant RNG sous Fog |
| --- | --- |
| 100 | 80 |
| 90 | 72 |
| 80 | 64 |
| 70 | 56 |

Si `logic.weather_effects_disabled?` est vrai, le hook retourne seulement `super`.
L'API native couvre Air Lock et Cloud Nine ; aucun nom de talent n'est codé dans
l'extension. La météo brute et son voile restent présents, comme les autres
météos neutralisées du SDK. Le malus revient quand la neutralisation cesse.

Les sorties natives avant calcul restent prioritaires : précision ≤ 0, Annule
Garde, Verrouillage, ainsi que les autres bypass du SDK. Elles ne passent pas par
le produit des multiplicateurs Fog.

## Entrée et annonces

Ordre conservé : transition et envois natifs → message météo initial → animation
finie/ambiance → talents d'entrée natifs → événement `battle_begin` → choix joueur.
Le hook est placé avant le corps natif de `Scene#show_enter_event`, lui-même appelé
après `Visual#show_transition`. Il n'appelle aucun faux `weather_change`.

Le message est lu dans `WeatherChangeHandler::WEATHER_SYM_TO_MSG`, puis dans les
textes natifs. Une instance de combat ne le présente qu'une fois. `:none` est
silencieux ; les textes vides et placeholders `[~ n]` sont ignorés, notamment
le texte initial `:snow` de l'installation actuelle. Les textes ne sont pas copiés
dans le code ni modifiés dans les données.

Sous Fog puis Crachin : texte 18,91 → apparition Fog → Crachin natif → Rain native
et texte 18,88. Le voile Fog disparaît avant la présentation de la nouvelle météo.
La présentation initiale ne déclenche aucun callback de changement météo et ne
remet pas à zéro une météo créée ensuite par un talent.

## Visuel

Une seule `Plane` réutilise `graphics/animations/fog.png`, sans nouvel asset.
Réglages : opacité **48/255**, défilement horizontal **4 pixels/seconde**, z **60**,
apparition **0,6 seconde**. Le défilement dépend du temps écoulé et non du nombre
d'images par seconde. La texture est répétée par le shader natif de Plane.

Le z retenu après inspection des captures est dans le viewport principal : au-dessus
du fond/terrain et sous les bases (100/500) et Pokémon (101+/501+).
L'interface demeure dans le viewport supérieur. Ce voile léger rend le décor
brumeux tout en conservant les couleurs des Pokémon et la lisibilité des commandes.
Aucune position ni texture de battleback/base/Pokémon/interface n'est modifiée.

`FogAppearance` utilise un `Yuki::Animation.scalar` fini dans le Handler natif.
La Plane persistante n'entre pas dans `@animatable` : `wait_for_animation` termine
normalement. Le voile demeure quand `show_animation = false`, mais le fondu
d'apparition respecte cette option via `Visual#show_weather_animation` natif.

À chaque présentation météo native, puis lors de l'update visuel, le hook consulte
l'effet météo brut. Ce petit contrôle permet aussi de suivre un `apply_weather`
direct par script. Aucun parcours supplémentaire des combattants n'est nécessaire
pour le visuel. Fog → Rain/Sunny/Sandstorm/None détruit immédiatement la Plane ;
un retour à Fog en recrée une. La disparition du malus suit automatiquement le
changement de classe d'effet météo effectué par PSDK.

`Visual#dispose` détruit le voile avant le nettoyage natif ; victoire, fuite,
défaite et sortie de scène partagent ce chemin normal. Une animation en cours peut
terminer après suppression du voile : le setter d'opacité ignore une Plane détruite.
La référence locale au voile est effacée. Le bitmap partagé du cache n'est jamais
détruit par l'extension. Pas de traitement particulier d'une fermeture brutale
du processus ou d'une exception empêchant tout cleanup natif.

## Anti-Brume

Anomalie reproduite en exécutant le vrai `Defog#deal_effect` avant le prepend :
le handler affiche 18,96, puis Defog affiche 18,98, texte concernant le sable.
Le correctif retire Fog via le même handler natif, puis appelle `super` : le corps
natif constate qu'il n'y a plus Fog, évite la seconde annonce et conserve ses
traitements des pièges et protections. Le test vérifie notamment les effets
affectés par Tour Rapide, Protection adverse et la conservation de Protection alliée.
Le message de disparition reste exclusivement le texte natif 18,96, une fois.

## Synchronisation et données de map

Avant le corps de `Scene#initialize`, donc avant `in_battle = true`, `create_logic`
et les effets météo, la méthode locale d'Environment copie **une fois** l'état
extérieur `@weather` dans le champ PSDK existant `@battle_weather`. Elle rétablit
la durée infinie de la météo héritée : la durée partagée peut encore contenir le
compte à rebours du combat précédent. Elle actualise les interrupteurs météo via
la méthode native. Le SDK présent n'offre pas de setter public pour cette seule
copie ; l'accès à ses champs est isolé dans cette méthode locale.

`@weather` n'est pas modifié. La méthode refuse de resynchroniser un combat déjà
actif. Aucune synchronisation continue n'est ajoutée. Les attaques météo et leurs
durées de 5/8 tours restent natives.

Avec MixWeather OFF : map Fog → combat Fog → Rain en combat → retour map Fog.
Si `forcedWeather = null`, la remise à zéro native de fin de combat peut laisser
`@battle_weather = 0` ; l'entrée suivante réhérite correctement du Fog extérieur.
Les tests utilisent la véritable méthode native de reset de fin de combat.

| Zone inspectée | Map | forcedWeather |
| --- | --- | --- |
| 32, Forêt Hantée | 36 | 5, Fog |
| 38 | 80 | 5, Fog |
| 31 | 51 | 1, Rain |
| 39, Île Liberté | 52 | null, peut recevoir une météo événementielle |

## Interrupteurs et anomalies laissées intactes

**39 / MixWeather** : nommé « Battle Weather applies to Map ». Le SDK initialise
les interrupteurs à false. Aucune commande de contrôle, y compris les plages de
numéros, ne l'active dans les **85 maps** et événements communs inspectés. Aucune
écriture explicite trouvée dans les scripts locaux. L'extension ne le force jamais.
Si une sauvegarde ou une intervention manuelle le met ON, les règles natives de
mélange map/combat restent actives : l'indépendance recherchée suppose bien OFF.

**138 / Meteo** : aucune activation explicite trouvée non plus. L'événement commun
61 est parallèle et dépend de cet interrupteur. Il vérifie notamment l'extérieur
(switch 20), mais **pas** `forcedWeather`. Donc, si 138 est ON en Forêt Hantée,
ses commandes `Game_Screen#weather` peuvent remplacer Fog par None/Rain/Sunny.
Le conflit est possible dans ce chemin ; aucune activation actuelle par les
événements du projet n'a été démontrée. Les valeurs d'une partie en mémoire ou
d'une ancienne sauvegarde n'ont pas été lues. Vérification en console possible :
`[$game_switches[39], $game_switches[138]]`.

Correction recommandée pour une phase ultérieure : exclure les zones où
`data_zone($env.current_zone).forced_weather` est non nil avant toute application
aléatoire, y compris dans les chemins de l'événement 60. La valeur 0 est elle aussi
une contrainte de zone. Aucun événement ni interrupteur modifié ici.

**WT_Snow** : la table native contient deux fois ce même interrupteur, aux indices
Hail et Hardsun. La dernière écriture écrase la première ; l'index Snow 9 n'a pas
d'entrée. Cette anomalie n'est pas corrigée et n'empêche pas Fog de fonctionner.
Les sujets neige/grêle, Hardrain et météo aléatoire restent hors périmètre.

## Tests et interactions

Résultat gameplay avec le Ruby 3.0.6 de Studio : **24 tests, 157 assertions,
0 échec, 0 erreur, 0 ignoré**. Le banc charge les véritables classes Weather,
Environment, WeatherChangeHandler, Defog, WeatherMove, EffectBase, les méthodes
de calcul de précision, each_effects, le constructeur de Scene, show_enter_event,
le reset de fin de combat et le Handler d'animation. Les services périphériques
(combat complet, entrées clavier, chargement des équipes, etc.) sont simulés.

| Couverture demandée | Résultat |
| --- | --- |
| A–D : None, Fog et valeurs 100/90/80/70 | Validé |
| E : niveaux précision/esquive | Combinaison native validée |
| F : autre multiplicateur | Produit conservé, exemple 100 × 0,8 × 0,5 = 40 |
| G : Air Lock et Cloud Nine | Vraies classes/enregistrements natifs ; neutralisation puis retour du malus |
| H : précision ≤ 0, Annule Garde, Verrouillage | Bypass conservés |
| I–J : Danse Pluie/Zénith, plus Sable | Vrais effets WeatherMove ; état, durée, message et retrait du voile validés |
| K : Anti-Brume | Anomalie native reproduite, message unique corrigé, protections/pièges conservés |
| L : entrant SOS | Ajout simulé d'un combattant ; précision et météo globales conservées |
| M : Boss | Vrai `BossEffectDispatch` chargé ; effet de test combiné, ordre et court-circuit conservés |
| ZVBattleMessages | Vrai module chargé ; jet 85 rate sous Fog/80 et déclenche popup/log ; réussite sans Fog ; fallback natif testé |
| Annonce initiale | Fog/Rain/Sunny/Sandstorm/Hail/Hardsun/Hardrain/StrongWinds une fois ; None/Snow placeholder silencieux ; vide ignoré |
| Crachin | Vrai effet Drizzle ; ordre Fog → talent → Rain, sans doublon |
| Présentation seule | Aucun callback de faux changement météo |
| Durée Fog finie | Expiration native, retrait du voile, texte de fin unique |
| Map → battle → map | Fog forcé sans remplacement, puis avec Rain ; Fog événementiel retrouvé au second combat |
| Animation | Vrais Handler et wait natifs ; fin à environ 0,6 seconde, ambiance persistante |
| Options/cleanup | Ambiance sans animations, réactivation, défilement, suppression pendant un fondu, dispose |

Test graphique **LiteRGSS réel**, Ruby Studio : **1 test, 182 442 assertions,
0 échec, 0 erreur, code de sortie 0**. La grande majorité des assertions comparent
des pixels ; elles ne représentent pas autant de scénarios indépendants.

Compositions 1v1, 2v2 et 3v3 avec battleback, bases, Pokémon, textures de barres
et une commande de menu de test. Le vrai Plane/shader du SDK et l'animation Fog
sont utilisés. Les captures ont été inspectées. Le voile modifie bien le fond ;
les coordonnées restent identiques, le menu reste intact ; après Rain/Sunny/None,
le rendu revient à l'état initial, sans trace du voile. Destruction de la Plane
et du viewport vérifiée, bitmap du cache conservé.

Ces compositions ne lancent pas les contrôleurs complets BBBB/InfoBars ni le vrai
menu interactif. Le SOS est simulé : aucun appel aléatoire complet joué. Les effets
Boss sont injectés dans leur vrai dispatcher, sans scénario de Boss complet.
Les transitions, victoire/fuite/défaite et les zones réelles restent à valider
ensemble dans le jeu. Aucun fichier de sauvegarde n'a été chargé ou écrit.

## Reproduire

Depuis la racine du projet, avec `scripts/psdk_scripts` pointant sur le SDK installé :

```powershell
ruby 'scripts/00024 Weather Bombance/tests/weather_test.rb'
ruby 'scripts/00024 Weather Bombance/tests/audit_events.rb'

$studioRuby = 'C:/Users/thiba/AppData/Local/Programs/pokemon-studio/resources/psdk-binaries'
$minitestLib = 'C:/Ruby31-x64/lib/ruby/gems/3.1.0/gems/minitest-5.15.0/lib'
& "$studioRuby/ruby.exe" -I $minitestLib 'scripts/00024 Weather Bombance/tests/weather_test.rb'
& "$studioRuby/ruby.exe" -I $minitestLib -r "$studioRuby/lib/LiteRGSS.so" 'scripts/00024 Weather Bombance/tests/native_visual.rb'
```

Les chemins Ruby/Minitest sont ceux présents sur cette machine. Aucune dépendance
installée pour cette tâche. Le test natif ouvre brièvement une fenêtre et remplace
ses six captures locales, puis le processus la ferme. Il ne lance pas le jeu.

## Checklist très courte dans le jeu

1. Forêt Hantée : constater Fog sur la map, lancer un combat ; vérifier un seul
   message, le fondu puis le voile, et la lisibilité des barres/menu.
2. Essayer des attaques de précision connue ; tester aussi Annule Garde et
   Air Lock/Cloud Nine si disponibles. Un petit échantillon de jets ne mesure
   pas exactement le taux de réussite.
3. Utiliser Danse Pluie ou Zénith ; constater le retrait du voile. Dans un autre
   combat sous Fog, utiliser Anti-Brume : une seule annonce de dissipation.
4. Finir/fuir : vérifier Fog sur la map, puis dans un second combat. Refaire
   l'enchaînement sur une météo événementielle de l'Île Liberté si disponible.
5. Vérifier une zone pluvieuse, puis un combat double/triple ou SOS et un Boss ;
   refaire une entrée sous Fog avec les animations désactivées.

## Diff

Diff limité à ce dossier : **13 fichiers créés, 1 253 lignes ajoutées**, six PNG
inclus ; **180 lignes de production** dans les deux scripts numérotés.
Les fichiers restent non suivis tant qu'ils ne sont pas ajoutés à Git : un simple
`git diff --stat` ne les affiche donc pas. L'état global contient aussi des
modifications de données de l'utilisateur, qui n'appartiennent pas à ce travail.
