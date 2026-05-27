module Battle
  module Effects
    class Boss < PokemonTiedEffectBase
      # Check if the user of this ability ignore the center of attention in the enemy bank
      # @return [Boolean]
      def ignore_target_redirection?
        return true
      end

      # Function called after a battler proceed its two turn move's first turn
      # @param user [PFM::PokemonBattler]
      # @param targets [Array<PFM::PokemonBattler>, nil]
      # @param skill [Battle::Move, nil]
      # @return [Boolean] weither or not the two turns move is executed in one turn
      def on_two_turn_shortcut(user, targets, skill)
        return true
      end

      # Function called when a stat_decrease_prevention is checked
      # @param handler [Battle::Logic::StatChangeHandler] handler use to test prevention
      # @param stat [Symbol] :atk, :dfe, :spd, :ats, :dfs, :acc, :eva
      # @param target [PFM::PokemonBattler]
      # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
      # @param skill [Battle::Move, nil] Potential move used
      # @return [:prevent, nil] :prevent if the stat decrease cannot apply
      def on_stat_decrease_prevention(handler, stat, target, launcher, skill)
        return if target != @pokemon || launcher == @pokemon

        return handler.prevent_change do
          handler.scene.display_message_and_wait(parse_text_with_pokemon(19, 198, target))
        end
      end

      # Function called when a status_prevention is checked
      # @param handler [Battle::Logic::StatusChangeHandler]
      # @param status [Symbol] :poison, :toxic, :confusion, :sleep, :freeze, :paralysis, :burn, :flinch, :cure
      # @param target [PFM::PokemonBattler]
      # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
      # @param skill [Battle::Move, nil] Potential move used
      # @return [:prevent, nil] :prevent if the status cannot be applied
      def on_status_prevention(handler, status, target, launcher, skill)
        return if target != @pokemon || launcher == @pokemon

        return handler.prevent_change do
          # TODO: Add the corresponding text
        end
      end

      # Function called after damages were applied (post_damage, when target is still alive)
      # @param handler [Battle::Logic::DamageHandler]
      # @param hp [Integer] number of hp (damage) dealt
      # @param target [PFM::PokemonBattler]
      # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
      # @param skill [Battle::Move, nil] Potential move used
      def on_post_damage_death(handler, hp, target, launcher, skill)
        return unless target.boss? && target.nb_bars_hp > 0

        # TODO: Add the corresponding effect when a bar is lost
      end

      # Function called before drain were applied (to potentially prevent healing)
      # @param handler [Battle::Logic::DamageHandler]
      # @param hp [Integer] number of hp (damage) dealt
      # @param hp_healed [Integer] number of hp healed
      # @param target [PFM::PokemonBattler]
      # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
      # @param skill [Battle::Move, nil] Potential move used
      # @return [:prevent, nil] :prevent if the drain cannot be applied
      def on_drain_prevention(handler, hp, hp_healed, target, launcher, skill)
        return if target != @pokemon

        return handler.prevent_change do
          # TODO: Add the corresponding text
        end
      end

      # Function called at the end of a turn
      # @param logic [Battle::Logic] logic of the battle
      # @param scene [Battle::Scene] battle scene
      # @param battlers [Array<PFM::PokemonBattler>] all alive battlers
      def on_end_turn_event(logic, scene, battlers)
        return unless battlers.include?(@pokemon)

        # TODO: Add the corresponding effect at the end of the turn
      end

      # Function called when we try to check if the Pokemon is immune to a move due to its effect
      # @param user [PFM::PokemonBattler]
      # @param target [PFM::PokemonBattler]
      # @param move [Battle::Move]
      # @return [Boolean] if the target is immune to the move
      def on_move_ability_immunity(user, target, move)
        return false if target != @pokemon
        return false unless move.mental?

        return true
      end

      # Function giving the name of the effect
      # @return [Symbol]
      def name
        return :boss
      end
    end
  end
end
