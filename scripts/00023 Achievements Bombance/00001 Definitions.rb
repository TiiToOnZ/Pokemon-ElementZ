# frozen_string_literal: true

# CONTENU : noms, seuils et récompenses se modifient ici. Garder les IDs déjà publiés.
module BombanceAchievements
  CATEGORIES = {
    general: {title: 'Général', description: 'Tes aventures à travers Bombance.', unlocked: true},
    researcher: {title: 'Chercheur', description: 'Découvre les Pokémon et leurs habitats.',
                 hidden_until_unlocked: false, invisible_until_unlocked: false}
  }.freeze
  CATEGORY_UNLOCKS = {researcher: {quest_ids: [49, 14, 15, 16, 17, 18, 67, 68, 69].freeze}}.freeze

  # Les Joyaux restent des objets standards du sac, dans la poche Objets (socket 1).
  # Les récompenses symboliques sont résolues avant la création de leur reçu.
  GEM_ITEMS = {
    normal: :normal_gem,
    fire: :fire_gem,
    water: :water_gem,
    electric: :electric_gem,
    grass: :grass_gem,
    ice: :ice_gem,
    fighting: :fighting_gem,
    poison: :poison_gem,
    ground: :ground_gem,
    flying: :flying_gem,
    psychic: :psychic_gem,
    bug: :bug_gem,
    rock: :rock_gem,
    ghost: :ghost_gem,
    dragon: :dragon_gem,
    dark: :dark_gem,
    steel: :steel_gem,
    fairy: :fairy_gem
  }.freeze
  RANDOM_GEM_ITEMS = GEM_ITEMS.values.freeze
  PRIMORDIAL_GEM = :joyau_primordial
  GREAT_BALLS = {type: :item, id: :great_ball, quantity: 3}.freeze

  DEFINITIONS = {
    trainer_wins: {
      category: :general,
      title: 'Combattant',
      description: 'Remporte des combats contre des Dresseurs.',
      source: :trainer_battles_won,
      unit: 'victoires',
      milestone: '%{value} victoires',
      tiers: [
        {id: :wins_5, value: 5, reward: :random_gem},
        {id: :wins_15, value: 15, reward: :random_gem},
        {id: :wins_30, value: 30, reward: :random_gem},
        {id: :wins_50, value: 50, reward: :random_gem},
        {id: :wins_100, value: 100, reward: {resolver: :random_gem, quantity: 2}},
        {id: :wins_200, value: 200, reward: {resolver: :random_gem, quantity: 2}},
        {id: :wins_350, value: 350, reward: {resolver: :random_gem, quantity: 3}},
        {id: :wins_500, value: 500, reward: {resolver: :random_gem, quantity: 3}},
        {id: :wins_750, value: 750, reward: {resolver: :random_gem, quantity: 4}}
      ]
    },
    secondary_quests: {
      category: :general,
      title: 'Bienfaiteur',
      description: 'Termine des quêtes secondaires.',
      source: :secondary_quests_completed,
      unit: 'quêtes',
      milestone: '%{value} quêtes terminées',
      tiers: [
        {id: :quests_3, value: 3, reward: :primordial_gem},
        {id: :quests_10, value: 10, reward: :primordial_gem},
        {id: :quests_20, value: 20, reward: :primordial_gem},
        {id: :quests_40, value: 40, reward: {resolver: :primordial_gem, quantity: 2}},
        {id: :quests_75, value: 75, reward: {resolver: :primordial_gem, quantity: 2}},
        {id: :quests_100, value: 100, reward: {resolver: :primordial_gem, quantity: 3}}
      ]
    },
    eggs: {
      category: :general,
      title: 'Éleveur',
      description: 'Fais éclore des Œufs Pokémon.',
      source: :eggs_hatched,
      unit: 'éclosions',
      milestone: '%{value} éclosions',
      tiers: [
        {id: :eggs_1, value: 1, reward: :random_gem},
        {id: :eggs_5, value: 5, reward: :random_gem},
        {id: :eggs_15, value: 15, reward: :random_gem},
        {id: :eggs_30, value: 30, reward: {resolver: :random_gem, quantity: 2}},
        {id: :eggs_60, value: 60, reward: {resolver: :random_gem, quantity: 2}},
        {id: :eggs_100, value: 100, reward: {resolver: :random_gem, quantity: 3}},
        {id: :eggs_200, value: 200, reward: {resolver: :random_gem, quantity: 4}}
      ]
    },
    shinies: {
      category: :researcher,
      title: 'Quelle chance !',
      description: 'Obtiens des Pokémon chromatiques.',
      source: :shinies_caught,
      unit: 'chromatiques',
      milestone: '%{value} chromatiques obtenus',
      tiers: [
        {id: :shinies_1, value: 1, reward: :random_gem},
        {id: :shinies_3, value: 3, reward: :random_gem},
        {id: :shinies_5, value: 5, reward: {resolver: :random_gem, quantity: 2}},
        {id: :shinies_10, value: 10, reward: {resolver: :random_gem, quantity: 2}},
        {id: :shinies_20, value: 20, reward: {resolver: :random_gem, quantity: 3}},
        {id: :shinies_30, value: 30, reward: {resolver: :random_gem, quantity: 3}}
      ]
    },
    best_friends: {
      category: :general,
      title: 'Meilleurs amis',
      description: "Atteins le maximum d'amitié avec un Pokémon.",
      kind: :unique,
      source: :maximum_loyalty,
      tiers: [
        {id: :completed, value: 255, reward: :pokemon_gem_bundle}
      ]
    },
    level_100: {
      category: :general,
      title: "Jusqu'au bout",
      description: 'Amène un Pokémon au niveau 100.',
      kind: :unique,
      source: :maximum_level,
      tiers: [
        {id: :completed, value: 100, reward: :pokemon_gem_bundle}
      ]
    },
    researcher_collection: {
      category: :researcher, title: 'Attrapez-les tous !',
      description: 'Attraper différentes espèces de Pokémon afin de les enregistrer dans le Pokédex.',
      source: :pokedex_species, unit: 'espèces', milestone: '%{value} espèces enregistrées',
      tiers: [
        {id: :species_5, value: 5, reward: [{type: :item, id: :poke_ball, quantity: 5},{type: :item, id: :potion, quantity: 2}]},
        {id: :species_15, value: 15, reward: {type: :item, id: :exp_share, quantity: 1}},
        {id: :species_30, value: 30, reward: [{type: :item, id: :great_ball, quantity: 5},{type: :item, id: :super_potion, quantity: 2}]},
        # IDs describe objectives, never their screen index. Old receipts for 50/75
        # survive their return. Removed 60/100/175/400/550/700 remain archived.
        {id: :species_50, value: 50, reward: {type: :item, id: :tm27, quantity: 1}},
        {id: :species_75, value: 75, reward: {type: :money, amount: 300, hidden: true}},
        {id: :species_105, value: 105, reward: {type: :item, id: :king_s_rock, quantity: 1}},
        {id: :species_140, value: 140, reward: {type: :money, amount: 300, hidden: true}},
        {id: :species_180, value: 180, reward: [{type: :item, id: :ultra_ball, quantity: 5},{type: :item, id: :hyper_potion, quantity: 2}]},
        {id: :species_225, value: 225, reward: {type: :money, amount: 100}},
        {id: :species_275, value: 275, reward: GREAT_BALLS},
        {id: :species_330, value: 330, reward: {type: :money, amount: 100}},
        {id: :species_390, value: 390, reward: {type: :money, amount: 100}},
        {id: :species_455, value: 455, reward: {type: :money, amount: 100}},
        {id: :species_525, value: 525, reward: {type: :money, amount: 100}},
        {id: :species_600, value: 600, reward: {type: :money, amount: 100}},
        {id: :species_680, value: 680, reward: {type: :money, amount: 100}},
        {id: :species_765, value: 765, reward: {type: :money, amount: 100}},
        {id: :species_855, value: 855, reward: {type: :money, amount: 100, hidden: true}}
      ]
    },
    researcher_forms: {
      category: :researcher,
      title: 'Formes & curiosités',
      description: 'Découvre différentes formes de Pokémon.',
      source: :pokedex_forms,
      unit: 'formes',
      milestone: '%{value} formes découvertes',
      tiers: [
        {id: :forms_3, value: 3, reward: :random_gem},
        {id: :forms_5, value: 5, reward: :random_gem},
        {id: :forms_10, value: 10, reward: {resolver: :random_gem, quantity: 2}},
        {id: :forms_20, value: 20, reward: {resolver: :random_gem, quantity: 2}},
        {id: :forms_30, value: 30, reward: {resolver: :random_gem, quantity: 3}},
        {id: :forms_50, value: 50, reward: {resolver: :random_gem, quantity: 3}}
      ]
    },
    researcher_zones: {
      category: :researcher,
      title: 'Expert local',
      description: 'Complète les Pokémon connus de différentes zones de Bombance.',
      source: :completed_zones,
      unit: 'zones',
      milestone: '%{value} zones complètes',
      tiers: [
        {
          id: :zones_1,
          value: 1,
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 1, zone_quantity: 1}
        },
        {
          id: :zones_3,
          value: 3,
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 1, zone_quantity: 1}
        },
        {
          id: :zones_5,
          value: 5,
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 2, zone_quantity: 1}
        },
        {
          id: :zones_10,
          value: 10,
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 2, zone_quantity: 2}
        },
        {
          id: :zones_20,
          value: 20,
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 3, zone_quantity: 2}
        },
        {
          id: :all_zones,
          value: ->(game) { ProgressSources.zone_total(game) },
          label: 'Toutes les zones',
          reward: {resolver: :zone_gem_bundle, primordial_quantity: 5, zone_quantity: 3}
        }
      ]
    }
  }.freeze

  # Une source absente de cette table est un compteur custom (increment / set / value).
  SOURCES = {
    pokedex_species: ->(game) { game.pokedex.creature_caught },
    secondary_quests_completed: ->(game) { ProgressSources.secondary_quests(game) },
    maximum_loyalty: ->(game) { ProgressSources.owned_max(game, :loyalty) },
    maximum_level: ->(game) { ProgressSources.owned_max(game, :level) },
    pokedex_forms: ->(game) { ProgressSources.forms_seen(game) },
    completed_zones: ->(game) { ProgressSources.completed_zones(game) }
  }.freeze
  NOTIFICATION_SE = 'audio/se/select.wav'
end
