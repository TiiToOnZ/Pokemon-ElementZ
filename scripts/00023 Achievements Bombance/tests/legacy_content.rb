# frozen_string_literal: true

module LegacyAchievementContent
  CATEGORIES = {
    general: {title: 'Général', unlocked: true},
    researcher: {title: 'Chercheur', hidden_until_unlocked: false, invisible_until_unlocked: false}
  }.freeze

  # All profession adapters live here. IDs also recognize existing saves at later levels.
  CATEGORY_UNLOCKS = {
    researcher: {quest_ids: [49, 14, 15, 16, 17, 18, 67, 68, 69].freeze}
  }.freeze

  # TEST ONLY: independent of Prof. Charme's existing rewards. Not final balancing.
  TEST_REWARDS = [
    {type: :money, amount: 100}, {type: :item, id: :poke_ball, quantity: 1},
    {type: :money, amount: 200}, {type: :item, id: :poke_ball, quantity: 2},
    {type: :money, amount: 300, hidden: true},
    {type: :item, id: :poke_ball, quantity: 3, hidden: true}
  ].map(&:freeze).freeze

  DEFINITIONS = {
    researcher_collection: {
      category: :researcher, title: 'Collectionneur',
      description: 'Attrape différentes espèces de Pokémon.',
      unit: 'espèces', milestone: '%{value} espèces capturées', source: :pokedex_species,
      tiers: [5, 15, 30, 50, 75, 100].map.with_index do |value, index|
        {id: "species_#{value}".to_sym, value: value, reward: TEST_REWARDS[index]}.freeze
      end.freeze
    }.freeze
  }.freeze

  # Computed sources are never copied into the save. Other source symbols use counters.
  SOURCES = {pokedex_species: ->(state) { state.pokedex.creature_caught }}
  NOTIFICATION_SE = 'audio/se/select.wav'
end
