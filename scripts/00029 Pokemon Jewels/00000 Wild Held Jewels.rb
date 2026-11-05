# Assigns ElementZ Jewels only to wild Pokemon, after native held-item rolls.
module ElementZ
  module WildHeldJewels
    TYPE_TO_ITEM = {
      bug: :bug_gem,
      dark: :dark_gem,
      dragon: :dragon_gem,
      electric: :electric_gem,
      fairy: :fairy_gem,
      fighting: :fighting_gem,
      fire: :fire_gem,
      flying: :flying_gem,
      ghost: :ghost_gem,
      grass: :grass_gem,
      ground: :ground_gem,
      ice: :ice_gem,
      normal: :normal_gem,
      poison: :poison_gem,
      psychic: :psychic_gem,
      rock: :rock_gem,
      steel: :steel_gem,
      water: :water_gem
    }.freeze
    PRIMORDIAL_ITEM = :joyau_primordial
    JEWEL_ITEMS = (TYPE_TO_ITEM.values + [PRIMORDIAL_ITEM]).freeze
    ELEMENTAL_CHANCE = 45
    PRIMORDIAL_CHANCE = 5
    BONUS_ABILITIES = %i[compound_eyes super_luck].freeze
    CHECKED_IVAR = :@elementz_wild_jewel_roll_checked
    PASSIVE_EFFECT_IVAR = :@elementz_passive_jewel_effect
    CAPTURE_ANNOUNCED_IVAR = :@elementz_captured_item_announcement_done

    module_function

    # Apply one Jewel decision to a wild Pokemon that has no item.
    # @param pokemon [PFM::Pokemon]
    # @return [PFM::Pokemon]
    def assign_if_empty(pokemon)
      return pokemon unless pokemon
      return pokemon if pokemon.instance_variable_defined?(CHECKED_IVAR)

      pokemon.instance_variable_set(CHECKED_IVAR, true)
      return pokemon unless pokemon.item_holding.nil? || pokemon.item_holding == 0

      type_items = jewel_items_for(pokemon)
      elemental_chance, primordial_chance = jewel_chances
      # Match the native held-item table: one cumulative roll, with each entry
      # occupying a slice of the same 0...100 range.
      rng = rand(100)
      if !type_items.empty? && rng < elemental_chance
        pokemon.item_holding = data_item(type_items[rand(type_items.size)]).id
      else
        rng -= elemental_chance unless type_items.empty?
        pokemon.item_holding = data_item(PRIMORDIAL_ITEM).id if rng < primordial_chance
      end
      return pokemon
    end

    # Apply the PSDK wild-item multipliers once to the Jewel distribution.
    # Native common/rare items are rolled earlier and remain untouched.
    # @return [Array<Numeric>] elemental and primordial percentage slices
    def jewel_chances
      ability = PFM.game_state.actors[0]&.ability_db_symbol
      return [ELEMENTAL_CHANCE * 1.2, PRIMORDIAL_CHANCE * 4] if BONUS_ABILITIES.include?(ability)

      return [ELEMENTAL_CHANCE, PRIMORDIAL_CHANCE]
    end

    # Tell whether the Pokemon physically holds an item.
    # @param pokemon [PFM::Pokemon, PFM::PokemonBattler]
    # @return [Boolean]
    def holding_item?(pokemon)
      symbol = data_item(pokemon.item_holding || 0).db_symbol
      return false if symbol.nil? || %i[none __undef__].include?(symbol)

      return true
    end

    # Test whether an item belongs to ElementZ's passive Jewel set.
    # @param db_symbol [Symbol]
    # @return [Boolean]
    def jewel_item?(db_symbol)
      return JEWEL_ITEMS.include?(db_symbol)
    end

    # Find the exact Pokemon instance stored by the native capture procedure.
    # @param pokemon [PFM::Pokemon]
    # @return [PFM::Pokemon, nil]
    def stored_pokemon(pokemon)
      stored = PFM.game_state.actors.find { |candidate| candidate.equal?(pokemon) }
      return stored if stored

      $storage.each_pokemon do |candidate|
        if candidate.equal?(pokemon)
          stored = candidate
          break
        end
      end
      return stored
    end

    # Read the displayed name from the stored Pokemon's physical item field.
    # @param pokemon [PFM::Pokemon]
    # @return [String]
    def held_item_name(pokemon)
      return data_item(pokemon.item_holding || 0).name
    end

    # Build a unique list using the current form's actual types.
    # @param pokemon [PFM::Pokemon]
    # @return [Array<Symbol>]
    def jewel_items_for(pokemon)
      types = [pokemon.data.type1, pokemon.data.type2].compact.map do |type|
        type.respond_to?(:to_sym) ? type.to_sym : type
      end
      types.reject! { |type| type == :none || type == :__undef__ }
      types.select! { |type| TYPE_TO_ITEM.key?(type) }
      return types.map { |type| TYPE_TO_ITEM[type] }.uniq
    end

    # Wild_Battle#configure_battle is private and also overridden by the Boss plugin.
    # Prepending and calling super keeps that battle setup intact.
    module WildBattlePatch
      def configure_battle(enemy_arr, battle_id)
        enemy_arr.each { |pokemon| ElementZ::WildHeldJewels.assign_if_empty(pokemon) } if enemy_arr.is_a?(Array)
        return super
      end

      private :configure_battle
    end

    # SOS reinforcements are drawn after initial battle configuration.
    # Wrap only the factory draw so each reinforcement gets the same one-time decision.
    module SOSFactoryPatch
      def draw(caller_battler, sos_request)
        pokemon = super
        ElementZ::WildHeldJewels.assign_if_empty(pokemon)
        return pokemon
      end
    end

    # PSDK registers the 18 elemental Jewels as active battle Gems. Returning
    # the base no-op item effect keeps them held without boosting/consuming them.
    module PassiveJewelEffectPatch
      def item_effect
        return super unless ElementZ::WildHeldJewels.jewel_item?(battle_item_db_symbol)

        return instance_variable_get(PASSIVE_EFFECT_IVAR) if instance_variable_defined?(PASSIVE_EFFECT_IVAR)

        return instance_variable_set(PASSIVE_EFFECT_IVAR, Battle::Effects::Item.new(@scene.logic, self, :__undef__))
      end
    end

    # Do not play the native item bar/sound or let ZVBattleLog record a Jewel.
    module JewelVisualPatch
      def show_item(target, *args, **kwargs)
        return if ElementZ::WildHeldJewels.jewel_item?(target.item_db_symbol)

        return super
      end
    end

    # Frisk normally identifies the first foe's held item by name. Hide only
    # ElementZ Jewels while retaining its native reveal for ordinary items.
    module FriskJewelPatch
      def on_switch_event(handler, who, with)
        return if with != @target

        foe_item = handler.logic.foes_of(with).find do |foe|
          foe.alive? && foe.item_db_symbol != :__undef__ &&
            !ElementZ::WildHeldJewels.jewel_item?(foe.item_db_symbol)
        end
        return unless foe_item

        handler.scene.visual.show_ability(with)
        handler.scene.display_message_and_wait(parse_text_with_pokemon(19, 439, with, PFM::Text::PKNICK[1] => foe_item.given_name, PFM::Text::ITEM2[2] => foe_item.item_name))
      end
    end

    # After the native procedure copies battler properties to the captured
    # Pokemon and stores it, disclose the exact held item's name if present.
    module CaptureAnnouncementPatch
      def give_pokemon_procedure(battler, ball)
        captured_pokemon = battler.original

        result = super
        puts "[JOYAUX] Objet : #{captured_pokemon.item_holding.inspect}"

        return result if @battle_info.trainer_battle?
        return result unless captured_pokemon
        return result unless ElementZ::WildHeldJewels.holding_item?(captured_pokemon)

        unless captured_pokemon.instance_variable_defined?(
          ElementZ::WildHeldJewels::CAPTURE_ANNOUNCED_IVAR
        )
          captured_pokemon.instance_variable_set(
            ElementZ::WildHeldJewels::CAPTURE_ANNOUNCED_IVAR, true
          )

          item_name = ElementZ::WildHeldJewels.held_item_name(captured_pokemon)

          display_message_and_wait(
            "#{captured_pokemon.given_name} porte un #{item_name} !"
          )
        end

        return result
      end
    end
  end
end

PFM::Wild_Battle.prepend(ElementZ::WildHeldJewels::WildBattlePatch)
SOSBattles::ReinforcementFactory.singleton_class.prepend(ElementZ::WildHeldJewels::SOSFactoryPatch)
PFM::PokemonBattler.prepend(ElementZ::WildHeldJewels::PassiveJewelEffectPatch)
Battle::Visual.prepend(ElementZ::WildHeldJewels::JewelVisualPatch)
Battle::Effects::Ability::Frisk.prepend(ElementZ::WildHeldJewels::FriskJewelPatch)
Battle::Scene.prepend(ElementZ::WildHeldJewels::CaptureAnnouncementPatch)
