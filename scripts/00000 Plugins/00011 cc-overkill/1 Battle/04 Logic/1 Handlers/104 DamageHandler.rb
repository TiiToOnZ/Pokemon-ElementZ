module Battle
  class Logic
    class DamageHandler < ChangeHandlerBase
      # Measures the damage that goes beyond what the target can take, and marks the pulverised.
      module OverkillCollector
        # Function that test if the damage can be dealt and deal the damage if so
        # @param hp [Integer] number of hp (damage) dealt
        # @param target [PFM::PokemonBattler]
        # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
        # @param skill [Battle::Move, nil] Potential move used
        # @param messages [Proc] messages shown right before the post processing
        def damage_change_with_process(hp, target, launcher = nil, skill = nil, &messages)
          return super unless overkill_applies_to?(target)

          return measure_overkill(hp, target, launcher, skill) { super }
        end

        # Function that test if the drain can be applied and apply it if so
        # @param hp_factor [Integer] the division factor of HP to drain
        # @param target [PFM::PokemonBattler]
        # @param launcher [PFM::PokemonBattler] the pokemon that launched the move
        # @param skill [Battle::Move, nil] Potential move used
        # @param hp_overwrite [Integer, nil] set the hp drained
        # @param drain_factor [Integer] the division factor of HP heal
        # @param messages [Proc] messages shown right before the post processing
        def drain_with_process(hp_factor, target, launcher, skill = nil, hp_overwrite: nil, drain_factor: 1, &messages)
          return super unless overkill_applies_to?(target)

          hp = hp_overwrite || (target.max_hp / hp_factor).clamp(0, Float::INFINITY)
          return measure_overkill(hp, target, launcher, skill) { super }
        end

        private

        # Let a hit land, and mark its target when it went down with damage to spare
        # @param hp [Integer] number of hp (damage) dealt
        # @param target [PFM::PokemonBattler]
        # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
        # @param skill [Battle::Move, nil] Potential move used
        # @note Marking here and not at the end of the attack is what catches the hits dealt outside
        #   one, Future Sight landing from the end of turn chain being the one that matters.
        def measure_overkill(hp, target, launcher, skill)
          target.overkill_pending_excess = overkill_excess_of(hp, target, launcher, skill)
          result = yield
          target.overkilled = true if target.overkill_landing?
          target.overkill_pending_excess = 0
          return result
        end

        # Tell if the overkill mechanic has anything to do with a hit landing on a target
        # @param target [PFM::PokemonBattler]
        # @return [Boolean]
        def overkill_applies_to?(target)
          return Overkill::Settings.applies_to_player_side if target.from_player_party?

          return true
        end

        # Get the damage a hit carries beyond what its target can take
        # @param hp [Integer] number of hp (damage) dealt
        # @param target [PFM::PokemonBattler]
        # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
        # @param skill [Battle::Move, nil] Potential move used
        # @return [Integer]
        def overkill_excess_of(hp, target, launcher, skill)
          excess = (skill&.uncapped_damage || hp) - target.overkill_absorbable_hp
          # A lethal blow ends some moves early, and the gauge reads the excess during super.
          excess += skill.overkill_pending_damage(launcher, target) if excess >= 0 && skill && launcher

          return [excess, 0].max
        end
      end

      prepend OverkillCollector

      # Makes an overkill cost the trust of a creature of the player, instead of the usual knockout malus.
      module OverkillLoyalty
        # Row of the trust loss message in the plugin text file
        LOYALTY_LOSS_MESSAGE_ID = 4

        private

        # Function handling the loyalty update after death
        # @param hp [Integer] number of hp (damage) dealt
        # @param target [PFM::PokemonBattler]
        # @param launcher [PFM::PokemonBattler, nil] Potential launcher of a move
        # @param skill [Battle::Move, nil] Potential move used
        def handle_post_damage_death_loyalty_update(hp, target, launcher, skill)
          return super unless overkill_loyalty_applies_to?(target)

          kept = (target.loyalty / Overkill::Settings.loyalty_divisor).floor
          return if kept == target.loyalty

          target.loyalty = kept
          scene.display_message_and_wait(
            parse_text_with_pokemon(Overkill::Settings.text_file_id, LOYALTY_LOSS_MESSAGE_ID, target)
          )
        end

        # Tell if an overkill takes the place of the knockout loyalty malus on a target
        # @param target [PFM::PokemonBattler]
        # @return [Boolean]
        # @note The party of the player alone: the loyalty of anyone else is dropped with its battler.
        def overkill_loyalty_applies_to?(target)
          return false if Overkill::Settings.loyalty_divisor <= 1
          return false unless target.from_player_party?

          return target.overkill_landing?
        end
      end

      prepend OverkillLoyalty
    end
  end
end
