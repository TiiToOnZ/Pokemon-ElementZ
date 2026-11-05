# frozen_string_literal: true
require 'securerandom'

module BombanceAchievements
  # Read-only adapters. Cached zone membership is session data, never save data.
  module ProgressSources
    class ZoneCatalog < ElementZ::Habitat::Catalog
      def initialize(zone)
        @achievement_zone = zone
      end

      private

      def current_zone
        @achievement_zone
      end
    end

    class << self
      def reset
        @zones = @forms = nil
      end

      def each_owned(game)
        return enum_for(__method__, game) unless block_given?
        Array(game.actors).each { |pokemon| yield pokemon if pokemon }
        game.storage&.each_pokemon { |pokemon| yield pokemon }
      end

      def owned?(game, pokemon)
        each_owned(game).any? { |owned| owned.equal?(pokemon) }
      end

      def owned_max(game, attribute)
        each_owned(game).reject(&:egg?).map { |pokemon| pokemon.public_send(attribute) }.max || 0
      end

      def secondary_quests(game)
        game.quests.finished_quests.keys.count do |id|
          quest = data_quest(id)
          quest && quest.db_symbol != :__undef__ && quest.is_primary == false
        end
      end

      def form_pairs
        @forms ||= each_data_creature.flat_map do |creature|
          next [] if creature.db_symbol == :__undef__
          creature.forms.filter_map do |form|
            [creature.db_symbol, form.form] if form.form.between?(1, 29)
          end
        end.uniq
      end

      def forms_seen(game)
        form_pairs.count { |symbol, form| game.pokedex.creature_seen?(symbol, form) }
      end

      def zone_pairs(game)
        raise 'Inactive save cannot build the zone catalogue' unless game.equal?(PFM.game_state)
        @zones ||= each_data_zone.each_with_object({}) do |zone, zones|
          next if zone.db_symbol == :__undef__ || zone.maps.empty?
          # Exactly the union shown on the Zone page, including inactive groups.
          view = UI::Dex::ZoneEncounterEnvironments.build(ZoneCatalog.new(zone).snapshot)
          pairs = view.entries.map(&:key)
          zones[zone.db_symbol] = pairs unless pairs.empty?
        end
      end

      def zone_total(game)
        zone_pairs(game).size
      end

      def completed_zone_symbols(game)
        zone_pairs(game).filter_map do |zone, pairs|
          zone if pairs.all? do |symbol, form|
            game.pokedex.creature_seen?(symbol, form) || game.pokedex.creature_caught?(symbol, form)
          end
        end
      end

      def completed_zones(game)
        completed_zone_symbols(game).size
      end

      def zone_type_counts(game, zone)
        pairs = zone_pairs(game).fetch(zone, [])
        pairs.each_with_object(Hash.new(0)) do |(symbol, form), counts|
          creature_form = data_creature(symbol).forms.find { |entry| entry.form == form }
          next unless creature_form

          [creature_form.type1, creature_form.type2].each do |type|
            type = type.db_symbol if type.respond_to?(:db_symbol)
            type = type.to_sym if type.respond_to?(:to_sym)
            counts[type] += 1 if GEM_ITEMS.key?(type)
          end
        end
      end
    end
  end

  class << self
    # Persist only tiny receipts on the actual Pokemon. Personality values are not
    # unique (and shiny= changes them); a per-save identity also permits GTS trades.
    def pokemon_receipts(pokemon)
      identity = (state[:identity] ||= SecureRandom.hex(16))
      receipts = pokemon.instance_variable_get(:@bombance_achievement_receipts) || {}
      pokemon.instance_variable_set(:@bombance_achievement_receipts, receipts)
      receipts[identity] ||= {}
    end

    def baseline_acquisitions
      return if state[:acquisition_baseline]
      ProgressSources.each_owned(PFM.game_state) do |pokemon|
        pokemon_receipts(pokemon)[:shiny] = true if !pokemon.egg? && pokemon.shiny?
      end
      state[:acquisition_baseline] = true
    end

    def pokemon_acquired(pokemon)
      return unless ProgressSources.owned?(PFM.game_state, pokemon)
      return if pokemon.egg?
      receipt = pokemon_receipts(pokemon)
      if pokemon.shiny? && !receipt[:shiny]
        receipt[:shiny] = true
        increment(:shinies_caught)
      end
      owned_pokemon_changed(pokemon)
    end

    def egg_hatched(pokemon)
      return if pokemon.egg? || !ProgressSources.owned?(PFM.game_state, pokemon)
      receipt = pokemon_receipts(pokemon)
      unless receipt[:hatch]
        receipt[:hatch] = true
        increment(:eggs_hatched)
      end
      pokemon_acquired(pokemon)
    end

    def owned_pokemon_changed(pokemon)
      return unless ProgressSources.owned?(PFM.game_state, pokemon)
      return if pokemon.egg? || (pokemon.loyalty < 255 && pokemon.level < 100)
      source_changed(:maximum_loyalty, pokemon: pokemon) if pokemon.loyalty >= 255
      source_changed(:maximum_level, pokemon: pokemon) if pokemon.level >= 100
    end

    def update_completed_zone_rewards(previously_completed)
      completed = ProgressSources.completed_zone_symbols(PFM.game_state)
      new_zones = completed - previously_completed
      new_zones.each_with_index do |zone, index|
        record_zone_completion(zone)
        source_changed(:completed_zones, progress: previously_completed.size + index + 1, zone: zone)
      end
    end
  end
end
