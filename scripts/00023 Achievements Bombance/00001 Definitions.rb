# frozen_string_literal: true

# CONTENU : noms, seuils et récompenses se modifient ici. Garder les IDs déjà publiés.
module BombanceAchievements
  CATEGORIES = {
    general: {title: 'Général', description: 'Tes aventures à travers Bombance.', unlocked: true},
    researcher: {title: 'Chercheur', description: 'Découvre les Pokémon et leurs habitats.',
                 hidden_until_unlocked: false, invisible_until_unlocked: false}
  }.freeze
  CATEGORY_UNLOCKS = {researcher: {quest_ids: [49, 14, 15, 16, 17, 18, 67, 68, 69].freeze}}.freeze

  # Récompenses TEMPORAIRES. Chaque ligne de palier peut remplacer reward librement.
  MONEY = {type: :money, amount: 100}.freeze
  BALL = {type: :item, id: :poke_ball, quantity: 1}.freeze
  GREAT_BALLS = {type: :item, id: :great_ball, quantity: 3}.freeze

  DEFINITIONS = {
    trainer_wins: {
      category: :general, title: 'Combattant', description: 'Remporte des combats contre des Dresseurs.',
      source: :trainer_battles_won, unit: 'victoires', milestone: '%{value} victoires',
      tiers: [5, 15, 30, 50, 100, 200].map { |n| {id: "wins_#{n}".to_sym, value: n, reward: MONEY} }
    },
    secondary_quests: {
      category: :general, title: 'Bienfaiteur', description: 'Termine des quêtes secondaires.',
      source: :secondary_quests_completed, unit: 'quêtes', milestone: '%{value} quêtes terminées',
      tiers: [3, 10, 20, 40, 75, 100].map { |n| {id: "quests_#{n}".to_sym, value: n, reward: MONEY} }
    },
    eggs: {
      category: :general, title: 'Éleveur', description: 'Fais éclore des Œufs Pokémon.',
      source: :eggs_hatched, unit: 'éclosions', milestone: '%{value} éclosions',
      tiers: [1, 5, 15, 30, 60, 100].map { |n| {id: "eggs_#{n}".to_sym, value: n, reward: BALL} }
    },
    shinies: {
      category: :general, title: 'Quelle chance !', description: 'Obtiens des Pokémon chromatiques.',
      source: :shinies_caught, unit: 'chromatiques', milestone: '%{value} chromatiques obtenus',
      tiers: [1, 3, 5, 10, 20, 30].map { |n| {id: "shinies_#{n}".to_sym, value: n, reward: GREAT_BALLS} }
    },
    best_friends: {
      category: :general, title: 'Meilleurs amis', description: "Atteins le maximum d'amitié avec un Pokémon.",
      kind: :unique, source: :maximum_loyalty,
      tiers: [{id: :completed, value: 255, reward: MONEY}]
    },
    level_100: {
      category: :general, title: "Jusqu'au bout", description: 'Amène un Pokémon au niveau 100.',
      kind: :unique, source: :maximum_level,
      tiers: [{id: :completed, value: 100, reward: GREAT_BALLS}]
    },
    researcher_collection: {
      category: :researcher, title: 'Collectionneur',
      description: 'Enregistre différentes espèces de Pokémon dans le Pokédex.',
      source: :pokedex_species, unit: 'espèces', milestone: '%{value} espèces enregistrées',
      tiers: [
        {id: :species_5, value: 5, reward: MONEY},
        {id: :species_15, value: 15, reward: BALL},
        {id: :species_30, value: 30, reward: {type: :money, amount: 200}},
        {id: :species_60, value: 60, reward: {type: :item, id: :poke_ball, quantity: 2}},
        {id: :species_100, value: 100, reward: GREAT_BALLS},
        {id: :species_175, value: 175, reward: MONEY},
        {id: :species_275, value: 275, reward: GREAT_BALLS},
        {id: :species_400, value: 400, reward: MONEY},
        {id: :species_550, value: 550, reward: GREAT_BALLS},
        {id: :species_700, value: 700, reward: {type: :money, amount: 1000, hidden: true}}
      ]
    },
    researcher_forms: {
      category: :researcher, title: 'Formes & curiosités', description: 'Découvre différentes formes de Pokémon.',
      source: :pokedex_forms, unit: 'formes', milestone: '%{value} formes découvertes',
      # Formes alternatives valides 1..29, vues. Forme 0 et formes de combat exclues.
      # Audit : 197 alternatives en base, dont 39 dans les catalogues de zones.
      tiers: [1, 3, 5, 10, 20, 30].map { |n| {id: "forms_#{n}".to_sym, value: n, reward: BALL} }
    },
    researcher_zones: {
      category: :researcher, title: 'Expert local',
      description: 'Complète les Pokémon connus de différentes zones de Bombance.',
      source: :completed_zones, unit: 'zones', milestone: '%{value} zones complètes',
      tiers: [1, 3, 5, 10, 20].map { |n| {id: "zones_#{n}".to_sym, value: n, reward: MONEY} } +
        [{id: :all_zones, value: ->(game) { ProgressSources.zone_total(game) }, label: 'Toutes les zones', reward: GREAT_BALLS}]
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
