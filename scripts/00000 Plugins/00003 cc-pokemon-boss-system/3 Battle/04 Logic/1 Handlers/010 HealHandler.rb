module Battle
  class Logic
    class DamageHandler < ChangeHandlerBase
      # Function that proceeds to heal a Pokemon.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed.
      # @param hp [Integer] The number of HP to heal.
      # @param test_heal_block [Boolean] Whether to test if healing is blocked. Defaults to true.
      # @param bar_state [Symbol] The state of the HP bar during healing (:losing). Defaults to :normal.
      # @param animation_id [Symbol, Integer] The animation to use instead of the default one. Optional.
      # @return [Boolean] True if the heal was successful, false otherwise.
      def heal_boss(target, hp, test_heal_block: true, bar_state: :normal, animation_id: nil)
        return false unless can_heal_boss?(target, test_heal_block)

        heal_amount = hp.clamp(1, target.max_hp)
        process_boss_healing(target, heal_amount, bar_state, animation_id)

        return true
      end

      private

      # Check if the target can be healed.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed.
      # @param test_heal_block [Boolean] Whether to test if healing is blocked. Defaults to true.
      # @return [Boolean] True if the target can be healed, false otherwise.
      def can_heal_boss?(target, test_heal_block)
        if target.effects.has?(:heal_block) && test_heal_block
          @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 6, target))
          return false
        end

        return true if target.hp < target.max_hp
        return true if target.nb_bars_hp < 5

        @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 9, target))
        return false
      end

      # Process the healing logic for the target.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed.
      # @param heal_amount [Integer] The number of HP to heal.
      # @param bar_state [Symbol] The state of the HP bar during healing (:losing). Defaults to :normal.
      # @param animation_id [Symbol, Integer] The animation to use instead of the default one. Optional.
      def process_boss_healing(target, heal_amount, bar_state, animation_id)
        return add_bar(target, heal_amount, animation_id) if can_add_bar?(target, heal_amount, bar_state)
        return lose_bar(target, heal_amount, animation_id) if can_lose_bar?(target, heal_amount, bar_state)

        apply_boss_healing_effect(target, heal_amount, animation_id)
      end

      # Check if the Boss can regenerate a bar.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed.
      # @param heal_amount [Integer] The number of HP to heal.
      # @param bar_state [Symbol] The state of the HP bar during healing (:losing). Defaults to :normal.
      # @return [Boolean] True a bar can be added, false otherwise.
      def can_add_bar?(target, heal_amount, bar_state)
        return false if heal_amount + target.hp < target.max_hp + 1
        return false if target.nb_bars_hp == 5
        return false if bar_state == :losing

        return true
      end

      # Check if the Boss can lose a bar.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed
      # @param heal_amount [Integer] The number of HP to heal.
      # @param bar_state [Symbol] The state of the HP bar during healing (:losing). Defaults to :normal.
      # @return [Boolean] True if a bar can be lost, false otherwise.
      def can_lose_bar?(target, heal_amount, bar_state)
        return bar_state == :losing
      end

      # Add a bar for the Boss.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed.
      # @param heal_amount [Integer] The number of HP to heal.
      # @param animation_id [Symbol, Integer] The animation to use instead of the default one. Optional.
      def add_bar(target, heal_amount, animation_id)
        missing_hp = target.max_hp - target.hp
        heal_amount -= missing_hp

        show_hp_animations(-missing_hp, target)

        target.nb_bars_hp += 1
        @scene.visual.boss_battle_add_bar(target.bank, target.position, target.nb_bars_hp)

        target.hp = 1
        @scene.visual.refresh_info_bar(target)

        apply_boss_healing_effect(target, heal_amount, animation_id)
        @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 21, target))
      end

      # Lose a bar for the Boss.
      # @param target [PFM::PokemonBattler] The Pokemon that will be healed
      # @param heal_amount [Integer] The number of HP to heal.
      # @param animation_id [Symbol, Integer] The animation to use instead of the default one. Optional.
      def lose_bar(target, heal_amount, animation_id)
        target.nb_bars_hp -= 1
        @scene.visual.boss_battle_clear_bar(target.bank, target.position, target.nb_bars_hp)
        target.hp = target.max_hp
        @scene.visual.refresh_info_bar(target)
        @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 0, target))
      end

      # Apply the healing effect to the target.
      # @param target [PFM::PokemonBattler] The Pokemon that will receive the healing effect.
      # @param heal_amount [Integer] The actual amount of HP to apply.
      # @param animation_id [Symbol, Integer] The animation to use for the healing effect. Optional.
      # @yieldparam heal_amount [Integer] The actual amount of HP healed, passed to the block if provided.
      def apply_boss_healing_effect(target, heal_amount, animation_id)
        show_hp_animations(-heal_amount, target)

        @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 3, target))
      end
    end
  end
end
