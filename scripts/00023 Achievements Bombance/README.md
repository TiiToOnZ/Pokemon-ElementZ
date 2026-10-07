# Succès Bombance — V1 finalisée

PSDK installé **6716**, Ruby Studio **3.0.6**, interface **320×240**.
Le contenu ordinaire se configure dans **00001 Definitions.rb**.
Les récompenses sont temporaires et s'ajoutent aux récompenses existantes des
quêtes du professeur. Aucun équilibrage définitif n'est appliqué.

## Organisation

| Fichier | Rôle |
|---|---|
| 00001 Definitions.rb | Catégories, descriptions, déblocages métier, succès, seuils, récompenses, sources |
| 00002 ProgressSources.rb | Adaptateurs PSDK/Zone, propriété des Pokémon et preuves d'acquisition |
| 00002 StateAndEngine.rb | État persistant, API, reçus, synchronisation et attribution |
| 00003 Notifications.rb | File temporaire et composants graphiques |
| 00004 Scene.rb | Catégories, succès, détails ; navigation et défilement |
| 00005 Integration.rb | Hooks locaux et bouton du menu |
| tests/ | Régressions conservées, contenu final, audit de données et rendu natif |
| TEST_REPORT.md | Résultats, reproduction, limites et checklist |
| FINAL_REPORT.md | Audit de configuration et rapport de livraison |

Le dossier tests non numéroté n'est pas chargé par ScriptLoader. Aucun autre
système ni aucune donnée Studio/RMXP n'a été modifié.

## Contenu livré

| Catégorie / succès | Seuils | Source exacte | Rétroactif |
|---|---|---|---|
| Général / Combattant | 5, 15, 30, 50, 100, 200 | compteur trainer_battles_won | Non |
| Général / Bienfaiteur | 3, 10, 20, 40, 75, 100 | clés de game.quests.finished_quests dont data_quest(id).is_primary == false | Oui |
| Général / Éleveur | 1, 5, 15, 30, 60, 100 | compteur eggs_hatched | Non |
| Général / Quelle chance ! | 1, 3, 5, 10, 20, 30 | compteur shinies_caught : acquisitions réelles de chromatiques | Non |
| Général / Meilleurs amis | unique, amitié 255 | maximum de Pokemon#loyalty dans équipe/PC, hors Œufs | Oui |
| Général / Jusqu'au bout | unique, niveau 100 | maximum de Pokemon#level dans équipe/PC, hors Œufs | Oui |
| Chercheur / Collectionneur | 5, 15, 30, 60, 100, 175, 275, 400, 550, 700 | game.pokedex.creature_caught | Oui |
| Chercheur / Formes & curiosités | 1, 3, 5, 10, 20, 30 | paires espèce/forme alternatives valides, creature_seen? | Oui |
| Chercheur / Expert local | 1, 3, 5, 10, 20, toutes (27 actuellement) | collection du Pokédex de zone, entrées toutes connues | Oui |

Général est ouvert dès le début. Chercheur se débloque via la quête 49 ou les
quêtes suivantes 14, 15, 16, 17, 18, 67, 68, 69, actives ou terminées,
ou via unlock_category(:researcher). Les métiers classés secondaires dans
Studio comptent comme secondaires ; ce n'est pas un filtrage par le titre
affiché dans le Journal. La base contient actuellement 72 quêtes secondaires :
les seuils demandés 75/100 anticipent l'ajout de contenu.

« Destin exceptionnel » reste un concept futur : aucun succès fictif correspondant
n'est installé. L'exemple secret ci-dessous permet d'en créer lorsqu'un événement
réel sera défini.

## AJOUTER UN SUCCÈS

Les exemples sont des **entrées à insérer dans les Hash existants**, en conservant
les virgules entre entrées. Ne pas remplacer le fichier entier par un exemple.
Les identifiants Symbol sont internes et stables ; les titres restent modifiables.

### 1. Créer une catégorie

Dans CATEGORIES :

```ruby
artisan: {
  title: 'Artisan',
  description: 'Fabrique des objets utiles.',
  unlocked: false,
  hidden_until_unlocked: false,
  invisible_until_unlocked: false
},
```

- unlocked: true : disponible immédiatement.
- false/absent : verrouillée jusqu'au déblocage.
- hidden_until_unlocked: true : nom « ??? » et description masquée.
- invisible_until_unlocked: true : catégorie absente jusqu'au déblocage.

Pour un métier lié à des quêtes, ajouter dans CATEGORY_UNLOCKS ses vrais IDs :

```ruby
artisan: {quest_ids: [123]}, # remplacer 123 par l'ID réellement créé dans Studio
```

Un événement peut aussi appeler directement :

```ruby
BombanceAchievements.unlock_category(:artisan)
```

### 2. Créer un succès à paliers / compteur custom

Dans DEFINITIONS :

```ruby
artisan_fabrication: {
  category: :artisan,
  title: 'Premiers outils',
  description: 'Fabrique des objets.',
  source: :crafted_items,
  unit: 'objets',
  milestone: '%{value} objets fabriqués',
  tiers: [
    {id: :crafted_5, value: 5, reward: {type: :money, amount: 100}},
    {id: :crafted_20, value: 20, reward: {type: :item, id: :poke_ball, quantity: 1}},
    {id: :crafted_50, value: 50, reward: {type: :item, id: :great_ball, quantity: 3}}
  ]
},
```

Une source absente de SOURCES est automatiquement un compteur sauvegardé.
Après une fabrication **réussie**, dans une commande Script RPG Maker
ou dans le système de fabrication :

```ruby
BombanceAchievements.increment(:crafted_items)
# Ou un lot de trois objets :
BombanceAchievements.increment(:crafted_items, 3)
```

La vérification des succès concernés est automatique. Ne pas appeler les deux
lignes pour la même fabrication. Les compteurs métier natifs livrés sont déjà
branchés : ne pas incrémenter manuellement trainer_battles_won, eggs_hatched ou
shinies_caught pour les opérations couvertes par les hooks.

### 3. Créer un succès unique avec une source calculée

Dans SOURCES, déclarer une lecture existante, sans compteur parallèle :

```ruby
owned_level: ->(game) { ProgressSources.owned_max(game, :level) },
```

Dans DEFINITIONS :

```ruby
artisan_niveau: {
  category: :artisan,
  title: 'Un compagnon expérimenté',
  description: 'Possède un Pokémon de niveau 50.',
  kind: :unique,
  source: :owned_level,
  tiers: [
    {id: :completed, value: 50, reward: {type: :money, amount: 500}}
  ]
},
```

Un unique utilise exactement un reçu. Son interface affiche « Obtenu / Non obtenu »,
sans chaîne artificielle ni 1/1. Une source personnalisée est relue à la
synchronisation ; pour une réaction immédiate, son système propriétaire peut appeler :

```ruby
BombanceAchievements.source_changed(:owned_level)
```

Les sources livrées ont déjà leurs hooks. Aucun nouveau polling n'est nécessaire.

### 4. Créer un succès secret individuel, débloqué par un événement

Dans DEFINITIONS (exemple de structure ; remplacer par un vrai événement) :

```ruby
secret_a_definir: {
  category: :general,
  title: 'Nom à définir',
  description: 'Description à définir.',
  kind: :unique,
  source: :manual,
  secret: true,                    # titre ??? avant obtention
  hidden_description: true,        # description ???
  hidden_reward: true,             # récompense ???
  invisible_until_obtained: true,  # retirer cette option pour afficher une ligne ???
  exclude_until_obtained: true,    # exclure du pourcentage tant qu'inconnu
  tiers: [
    {id: :completed, value: 1, reward: {type: :money, amount: 100}}
  ]
},
```

Dans le véritable événement déclencheur :

```ruby
BombanceAchievements.unlock_achievement(:secret_a_definir)
```

Cette API accepte seulement source: :manual. Un second appel ne redonne rien.
Si la catégorie est verrouillée, la preuve est conservée et la récompense attend
son ouverture. Chaque option de masquage est indépendante ; secret masque le
titre et les indications de progression, hidden_description masque la description.
Un secret entièrement absent doit aussi utiliser exclude_until_obtained pour
ne pas révéler son existence par le total.

### 5. Modifier un seuil ou une récompense

Dans le palier voulu, modifier value ou reward. Exemple demandé :

```ruby
{id: :species_30, value: 30, reward: {type: :money, amount: 2000}},
# devient :
{id: :species_30, value: 30, reward: {type: :item, id: :great_ball, quantity: 3}},
```

- Argent : {type: :money, amount: 2000}.
- Un objet : {type: :item, id: :poke_ball, quantity: 1}.
- Plusieurs exemplaires : quantity: 3.
- Récompense cachée : ajouter hidden: true **dans reward**.
- Récompense cachée pour tout le succès : hidden_reward: true sur le succès.

Les objets doivent exister dans Studio. poke_ball et great_ball ont été vérifiés.
Les matériaux/noigrumes ont leur propre inventaire : ils sont refusés par le
handler ordinaire. Les Pokémon, recettes ou récompenses externes demanderaient
un nouveau handler, hors configuration ordinaire V1.

**Conserver les IDs publiés.** Changer un titre ou une récompense ne réattribue pas
un palier déjà reçu. Une récompense pending conserve sa copie promise, même si
la configuration change. Changer value sous le même ID conserve les anciens
reçus ; créer un nouvel ID représente au contraire une nouvelle récompense.
Ordonner les paliers par valeur croissante et garder les IDs uniques dans le succès.

Un seuil dynamique peut être une lambda de lecture :

```ruby
{id: :all_zones, value: ->(game) { ProgressSources.zone_total(game) },
 label: 'Toutes les zones', reward: {type: :item, id: :great_ball, quantity: 3}},
```

Un seuil dynamique à zéro ne se valide pas. « Toutes les zones » se calcule
depuis les données chargées, sans nombre magique. Si la base s'agrandit, les
nouveaux joueurs devront compléter le nouveau total ; un reçu déjà obtenu
reste acquis et n'est jamais redonné.

## API publique

```ruby
BombanceAchievements.unlock_category(:researcher)
BombanceAchievements.category_unlocked?(:researcher)
BombanceAchievements.increment(:crafted_items)       # +1
BombanceAchievements.increment(:crafted_items, 3)    # +3
BombanceAchievements.set(:crafted_items, 12)          # valeur absolue
BombanceAchievements.value(:crafted_items)            # compteur ou source calculée
BombanceAchievements.source_changed(:crafted_items)
BombanceAchievements.unlock_achievement(:secret_a_definir) # après déclaration
BombanceAchievements.check(:researcher_collection)
BombanceAchievements.sync_category(:researcher)
BombanceAchievements.sync_all
```

set/value/sync_all sont les équivalents existants de set_counter/counter/sync :
aucun alias redondant n'a été ajouté. Les compteurs acceptent des entiers >= 0 ;
les sources calculées sont en lecture seule. Un palier obtenu ne se perd pas
si une valeur baisse. Pour un système personnalisé qui ajoute directement un
Pokémon à l'équipe sans passer par GameState#add_pokemon ou Storage#store,
appeler pokemon_acquired(pokemon) après l'acquisition ; la propriété réelle et
les doublons sont vérifiés. Le chargement initial établit d'abord le socle des
anciens chromatiques : ils ne sont pas attribués rétroactivement.

## Formes : définition et audit

PSDK conserve des masques de bits par espèce dans @has_seen_and_forms et
@has_caught_and_forms. Chaque bit est un ID de forme. La source utilise l'API
publique creature_seen?(db_symbol, form), sans copier ces statistiques.

Une découverte est une **paire espèce/forme alternative valide 1..29**, vue au
moins une fois. La forme 0 reste couverte par Collectionneur ; les changements
de sexe, l'état chromatique et les formes spéciales >= 30 ne sont pas des
découvertes supplémentaires pour ce succès. La limite 29 suit
UI::Dex::Presenter::MAX_SELECTABLE_FORM dans le Pokédex installé.

Audit du 7 octobre 2026 : 828 espèces en base, 1 074 couples espèce/forme au total,
dont 197 alternatives 1..29 et 49 formes >= 30. Les catalogues des 27 zones
contiennent 39 alternatives distinctes. Ce dernier nombre motive les paliers
1/3/5/10/20/30 ; 197 est le plafond des données enregistrables, pas une promesse
d'accessibilité actuelle en jeu. Les 39 entrées sont configurées : leur accès
peut dépendre des événements. Pas de compteur custom, et revoir une forme ne
progresse pas. mark_captured seul ne remplace pas mark_seen pour ce succès.

## Zones : une seule source de vérité

ProgressSources::ZoneCatalog hérite localement de ElementZ::Habitat::Catalog ;
seule la sélection de la zone change. Le résultat passe dans la vraie méthode
UI::Dex::ZoneEncounterEnvironments.build, celle utilisée par la page Zone.
ZoneEncounterHome ne fait que réordonner cette même collection.

- Identifiant : zone.db_symbol ; seules les zones ayant au moins une map et une
  collection valide non vide sont éligibles.
- Collection : toutes les entrées affichées, y compris groupes inactifs/masqués
  temporairement, terrains, outils et périodes matin/jour/crépuscule/nuit.
- Connu : creature_seen?(espèce, forme) **ou** creature_caught?(espèce, forme),
  exactement Entry#revealed? ; la forme demandée doit correspondre.
- Doublons dédupliqués par le catalogue de la page ; aucun tirage de Pokémon/RNG.
- Formes automatiques : résolution du catalogue existant et de FORM_RESOLVERS,
  sans recréer une règle. Les entrées invalides/non résolues suivent les mêmes
  exclusions et avertissements que la page.
- Zones vides ignorées. Audit actuel : 27 zones, aucune anomalie de catalogue.

Seuls les couples constituant une zone sont mis en cache pour la session.
Leur état vu/capturé est toujours relu. Le cache disparaît au chargement ;
après une modification des données à chaud dans une session de développement,
appeler ProgressSources.reset puis sync_all. Les conditions temporelles ne
retirent aucune entrée, donc un changement d'heure ne change pas la complétion.

## Hooks et limites de rétroactivité

Tous les prepend sont dans Integration.rb et préservent les retours natifs.

| Hook | Effet |
|---|---|
| Pokedex#mark_seen | nouvelles formes vues, zones |
| Pokedex#mark_captured | nouvelles espèces capturées, zones |
| Quests#start | déblocage métier via CATEGORY_UNLOCKS |
| Quests#check_up_signal | vérification après transfert effectif aux quêtes terminées |
| Battle::Logic::BattleEndHandler#process | après super, résultat 0 + trainer_battle? ; une preuve par BattleInfo |
| GameState#add_pokemon | acquisitions réelles équipe/PC |
| Storage#store | acquisitions directes au PC ; contrôle de présence après store |
| GamePlay.make_egg_hatch | après retour natif réussi ; exclut retour false de remplacement de scène |
| Pokemon#loyalty=, #level=, #level_up_stat_refresh | seuil atteint sur un Pokémon réellement possédé |
| PokemonBattler#copy_properties_back_to_original | vérification après copie des résultats au Pokémon original |

Aucun historique global fiable n'a été trouvé pour victoires Dresseur,
éclosions ou chromatiques obtenus. Ces compteurs démarrent avec l'installation.
Les chromatiques déjà possédés sont marqués comme anciens sans incrément ;
les œufs ne le sont pas et peuvent compter après éclosion.

Les captures natives (dont SOS/CaptureChain), dons via add_pokemon, dépôts via
store et œufs éclos sont couverts. Les mouvements d'un même Pokémon ne
redistribuent rien. Les échanges/systèmes qui passent par ces API sont couverts.
Un échange PNJ remplaçant directement $actors[index], ou un script écrivant
directement dans une boîte, requiert l'appel d'adaptation ci-dessus pour compter
immédiatement un nouveau chromatique ; le Pokédex continue de fonctionner
normalement. Les Pokémon de la pension/équipe d'un ami ne sont pas scannés :
la rétroactivité amitié/niveau porte sur l'équipe et les boîtes du joueur.

Aucune probabilité, capture, chaîne, quête ou mise en scène de combat n'est
modifiée. Les tests isolés ne remplacent pas une validation d'un parcours réel.

## Sauvegarde, migration et attribution

Le getter lazy PFM::GameState#bombance_achievements reste le point d'entrée :

```ruby
{
  version: 2,
  categories: {researcher: true},
  counters: {trainer_battles_won: 5, eggs_hatched: 1, shinies_caught: 1},
  manual: {secret_a_definir: true},
  acquisition_baseline: true,
  identity: 'identifiant aléatoire de 32 caractères hexadécimaux', # créé à la demande
  tiers: {
    researcher_collection: {
      species_5: {status: :rewarded, reward: {type: :money, amount: 100}},
      species_15: {status: :pending, reward: {type: :item, id: :poke_ball, quantity: 1}}
    }
  }
}
```

Les clés categories/counters/tiers/manual manquantes deviennent {}.
version passe de 1 à 2 sans effacer les reçus existants. Les données des sources
calculées ne sont pas dupliquées. L'activation vide les notifications/caches et
établit le socle des acquisitions anciennes, sans donner de récompense.
La carte synchronise une fois par partie activée ; le menu synchronise aussi.
Un aperçu de sauvegarde ne déclenche pas de gain. Aucune vérification permanente
des statistiques dans update_graphics.

Chaque Pokémon enregistré peut porter un petit Hash sérialisable :

```ruby
@bombance_achievement_receipts = {
  'identifiant de la partie' => {shiny: true, hatch: true}
}
```

Cela évite de confondre des Pokémon différents ayant le même code de personnalité
(ce code est aussi modifié par shiny=). Les clones techniques gardent le reçu ;
un Pokémon échangé dans une autre partie peut être acquis par cette autre partie.
Un outil de duplication créant volontairement une nouvelle créature en clonant
toutes les variables conserverait cette identité : il doit gérer ce cas.

Les anciens IDs species_5/15/30/100 restent valides. species_50 et species_75
restent archivés dans tiers, hors des pourcentages et de l'interface. Leur argent
ou objet n'est jamais repris. Une ancienne dette pending est honorée lors de
sync_all, sans bandeau correspondant à un palier disparu. species_60 et les
nouveaux IDs sont de nouveaux paliers, indépendants des archives ; ils peuvent
donc donner de nouveaux gains. Les anciennes récompenses promises, dont celles
de species_100, gardent leur valeur initiale.

Le reçu est créé pending avec une copie de la récompense. Préparation sans
mutation active ; commit inventaire/argent et reçu synchrones ; callbacks de
quête ensuite. Sac plein/verrouillé ou échec de préparation : réessai lors
d'une synchronisation. Le détail indique « en attente ». Aucun bouton Réclamer.

Argent, sac, compteurs et reçus sont sauvegardés ensemble par PSDK. Aucun autosave.
Un arrêt avant sauvegarde perd ensemble les nouveaux gains et leurs reçus.
Sprites, viewport, timers, file de notifications, Proc et définitions complètes
ne sont jamais sérialisés dans cet état. register_reward reste l'extension
avancée pour un nouveau type de récompense, avec un commit sans yield ni
callback ni échec partiel.

## Interface et progression

Menu natif, neuf boutons, entrée Succès après Quêtes. Seul le libellé du bouton
Journal devient Quêtes ; l'objet, sa condition et QuestUI restent inchangés.
Actions PSDK UP/DOWN/A/B : clavier et configuration native de manette.

Général compte 26 unités de progression ; Chercheur 22 ; total déverrouillé 48.
Chaque palier obtenu vaut une unité, chaque unique une unité. Un pending est
déjà obtenu. Catégories verrouillées et secrets configurés pour être exclus
ne faussent pas le total visible. Un unique affiche son statut ; aucune chaîne 1/1.

File de notifications temporaire, un seul bandeau, différée en combat/dialogue/
transition et pendant les panneaux incompatibles. Les gains persistent, pas les
bandeaux. La file est vidée au rechargement. Les titres utilisent le texte lisible
sans les emoji fournis : la police PokemonDS ne garantit pas ces glyphes.
L'apparence générale est conservée ; le redesign reste un chantier séparé.