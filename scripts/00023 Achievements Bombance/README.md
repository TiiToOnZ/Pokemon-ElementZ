# Succès Bombance — V2

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
| 00003 Notifications.rb | File temporaire, pagination et animation des bandeaux |
| 00003 Panel.rb | Cadres Message 12, textes, icônes, barres et composants partagés |
| 00004 Scene.rb | Catégories, succès, détails ; navigation et défilement |
| 00005 Integration.rb | Hooks locaux et bouton du menu |
| tests/ | Régressions conservées, scénarios V2 et rendu natif |
| TEST_REPORT.md | Résultats, reproduction, limites et checklist |
| FINAL_REPORT.md | Livraison V2, captures, limites et état Git |

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
| Chercheur / Collectionneur | 5, 15, 30, 50, 75, 105, 140, 180, 225, 275, 330, 390, 455, 525, 600, 680, 765, 855 | game.pokedex.creature_caught | Oui |
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
- Plusieurs récompenses : un Array de Hash, sans changer les clés existantes :

```ruby
{id: :crafted_100, value: 100, reward: [
  {type: :item, id: :poke_ball, quantity: 5},
  {type: :item, id: :potion, quantity: 2},
  {type: :money, amount: 100}
]},
```

Chaque ligne a son propre reçu. Un objet indisponible ne bloque pas l'argent
ou les autres objets. Le détail affiche deux composantes par page ; ←/→
parcourt les pages. Le bandeau les fait défiler automatiquement.
Les récompenses de ce fichier restent centralisées et modifiables.
- Récompense cachée : ajouter hidden: true **dans reward**.
- Récompense cachée pour tout le succès : hidden_reward: true sur le succès.

Les objets doivent exister dans Studio. poke_ball et great_ball ont été vérifiés.
Les matériaux/noigrumes ont leur propre inventaire : ils sont refusés par le
handler ordinaire. Les Pokémon, recettes ou récompenses externes demanderaient
un nouveau handler, hors configuration ordinaire V2.

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

## Sauvegarde, migration et attribution V2 → V3

Le getter lazy de PFM::GameState appelle migrate_state. Aucun changement de
SaveLoadTweaks, aucun fichier de sauvegarde parallèle.

```ruby
{
  version: 3,
  categories: {researcher: true},
  counters: {trainer_battles_won: 5},
  manual: {},
  acquisition_baseline: true,
  identity: 'identité de la partie, créée à la demande',
  tiers: {
    researcher_collection: {
      species_5: {
        status: :pending,
        rewards: [
          {status: :rewarded, reward: {type: :item, id: :poke_ball, quantity: 5}},
          {status: :pending, reward: {type: :item, id: :potion, quantity: 2}}
        ]
      }
    }
  }
}
```

Migration déterministe sans distribution : les schémas absents/1/2 deviennent 3.
Les clés categories/counters/tiers/manual manquantes deviennent {}. Catégories,
compteurs, preuves manuelles, identité et reçus sur les Pokémon sont conservés.
Une version supérieure n'est pas abaissée. Réexécuter la migration ne change
pas le résultat.

Un ancien reward Hash devient une composante ; un ancien Array devient plusieurs
composantes. Le reward historique est aussi conservé pour l'audit. Un lot ancien
rewarded rend toutes ses composantes rewarded, sans complément provenant de la
nouvelle configuration. Un pending garde exactement la promesse enregistrée.
Les composantes déjà normalisées et partiellement payées sont conservées.
Une promesse absente reste en attente sans invention de récompense.

L'état obtenu correspond à la présence d'un reçu ; le paiement complet correspond
à status: :rewarded. Un pending compte donc dans la progression, mais le bandeau
« SUCCÈS DÉBLOQUÉ ! » attend le paiement intégral. Il n'existe pas de second
bandeau annonçant un paiement partiel. L'interface distingue Obtenu / En attente /
À obtenir pour chaque composante.

### Attribution et sac plein

Chaque composante est préparée puis commitée avant de préparer la suivante.
Le reçu individuel est marqué juste après le commit, avant tout callback de
quête. Un callback réentrant ne redonne pas l'objet. Un callback en erreur
ne remet pas en attente un gain déjà distribué.

Le handler d'objet vérifie le verrou du sac et maxBagItemCount (99 actuellement),
clone les collections internes, appelle Bag#add_item sur ce candidat et contrôle
le delta exact. Le sac PSDK installé ne réalise pas d'insertion partielle :
il ajoute la quantité entière. Si une extension n'insère qu'une partie dans le
candidat, le delta échoue : aucune quantité n'est commitée au sac réel, toute
la composante reste due. Il n'existe donc pas de reliquat partiellement inséré
pour une même composante ; un lot peut en revanche être partiellement payé.
Les collections commitées sont items, orders et shortcut.

Exemple : 5 Balls réussies, 2 Potions bloquées → sauvegarde → chargement →
libération de place → seulement les 2 Potions sont données. L'argent et les
composantes non bloquées peuvent être reçus pendant que le reste attend.

Les promesses sont copiées profondément à l'obtention. Éditer reward ensuite
ne modifie jamais un reçu existant. Les réessais ont lieu à la synchronisation
(carte chargée, ouverture du menu Succès, changement de source, sync_all).
Aucun bouton Réclamer, aucun autosave, aucune vérification de progression par frame.

Argent, sac et reçus sont sérialisés ensemble dans GameState. Les bandeaux,
viewports, sprites, callbacks et définitions ne sont pas sérialisés.
register_reward conserve son contrat avancé prepare → commit → after : commit
doit être synchrone, sans yield, sauvegarde, callback ou échec partiel.
Seuls :money et :item sont fournis ; aucun type rare n'est ajouté.

### Historique Collectionneur

Les IDs sont sémantiques, pas des indices de ligne :
species_5 signifie l'objectif publié sous cette identité. La V2 ne renomme
aucun ancien reçu et ne transpose jamais le quatrième ancien palier sur la
quatrième nouvelle ligne.

- IDs communs 5, 15, 30 et 275 : reçus conservés tels quels.
- 50 et 75 : IDs de l'ancienne première V1, à nouveau visibles. Leurs éventuels
  reçus archivés sont réutilisés ; aucune seconde récompense.
- 60, 100, 175, 400, 550 et 700 : historiques conservés, exclus du total V2.
  Leurs dettes restent distribuables par sync_all, sans bandeau de palier retiré.
- 105, 140, 180, 225, 330, 390, 455, 525, 600, 680, 765 et 855 :
  nouveaux objectifs distincts, avec récompense temporaire de 100 $ chacun.
  Ils peuvent être obtenus rétroactivement en plus des anciennes archives :
  c'est une nouvelle récompense, pas un renommage d'un ancien palier.

Les récompenses sans reçu de 5/15/30/275 conservent la configuration actuelle ;
50 retrouve les 2 Balls historiques, 75 les 300 $ cachés historiques.
Les promesses sauvegardées priment toujours sur ces valeurs.
La récompense du seuil final 855 est masquée avant obtention par le champ hidden ;
l'objectif reste visible.

**18 seuils uniquement** : 5, 15, 30, 50, 75, 105, 140, 180, 225, 275, 330,
390, 455, 525, 600, 680, 765, 855. Toujours creature_caught ; aucune multiplication
par les formes. La base actuelle comporte 828 espèces hors __undef__ : 855
anticipe du contenu futur, son comportement moteur est testé avec un Pokédex simulé.

Changer value sous un ID existant conserve sa récompense déjà payée, y compris
si le nouvel objectif est supérieur. Pour publier réellement un objectif
supplémentaire, ajouter un nouvel ID ; ne jamais recycler l'identité d'un palier.

## Interface V2 et navigation

Rendu 320×240, PokemonDS, fond bleu nuit, crème, sélection or ; fragments du
Message_12 existant, sans répéter ses ornements latéraux. La coupe est le seul
nouvel asset : graphics/interface/achievements/trophy.png, RGBA 22×22.
Seul le chargement d'icône du bouton Succès change ; Quêtes reste distinct.

- ↑/↓ : choix et défilement ; A : entrer ; B : revenir.
- Détail : ↑/↓ pour les paliers, ←/→ pour les récompenses quand plusieurs pages.
- Deux cartes de catégories, trois succès ou cinq paliers visibles.
- Viewports réellement découpés ; seules les lignes visibles sont instanciées.
- Scrollbar proportionnelle, minimum 8 px, butées, sélection x/N.
- Sélection et décalage mémorisés par catégorie/succès tant que l'écran reste
  ouvert ; la page de récompenses est mémorisée par palier.
- Textes répartis sur deux lignes puis tronqués avec … ; aucun ajout de contenu
  ne nécessite de modifier le code d'affichage.
- Uniques : Obtenu/Non obtenu, sans faux 1/1. Secrets et récompenses cachées
  respectent leurs paramètres, sans icône ni quantité révélée avant obtention.

Général : 26 unités ; Chercheur : 30 ; total déverrouillé : 56.
Les catégories verrouillées et les secrets exclus gardent la règle V1.

Bandeau : un seul à la fois, deux composantes par page, 2,4 secondes par page,
durée totale au moins 3,5 secondes, fondus de 0,18 seconde.
Le son n'est joué qu'à l'ouverture. Dialogues, combat, transition, panneaux de
quête et carte bloquent l'affichage et suspendent son temps. Un changement de
scène supprime le bandeau courant comme en V1, les événements encore en file
attendent la carte. Activer une sauvegarde vide cette file volatile.

Les actions virtuelles PSDK sont conservées : clavier, croix et stick manette
utilisent le même parcours. Les mappings natifs sont testés ; une manette
physique reste à valider dans le vrai jeu.

## Tests et livraison

Voir [TEST_REPORT.md](TEST_REPORT.md) pour les commandes exécutables, les
résultats mesurés et la checklist ; [FINAL_REPORT.md](FINAL_REPORT.md) pour
la liste des fichiers, les captures et les limites de livraison.

Les fixtures absentes source_support.rb et legacy_content.rb ne figurent dans
aucun historique Git accessible. La cause exacte de cette omission n'est pas
établie. Le premier est reconstruit à partir des classes natives et JSON actuels ;
le second reprend la configuration retrouvée dans la sauvegarde locale avant
finalisation. Les 27 scénarios historiques sont conservés, avec leurs attentes
adaptées au schéma 3 et aux capacités visibles V2. Aucun ancien résultat non
reproduit n'est présenté comme validation actuelle.
