module Battle
  class Move
    class RevivalBlessing < Move
      # Keeps a pulverised creature out of everything Revival Blessing can bring back.
      module OverkillCannotReturn
        # Function that tests if the user is able to use the move
        # @param user [PFM::PokemonBattler] user of the move
        # @param targets [Array<PFM::PokemonBattler>] expected targets
        # @note Thing that prevents the move from being used should be defined by :move_prevention_user Hook
        # @return [Boolean] if the procedure can continue
        def move_usable_by_user(user, targets)
          return false unless super
          return true if revivable_party_of(user).any?

          show_usage_failure(user)
          return false
        end

        # Function that deals the effect to the pokemon
        # @param user [PFM::PokemonBattler] user of the move
        # @param actual_targets [Array<PFM::PokemonBattler>] targets that will be affected by the move
        # @note Redoes the engine pick on the revivable allies only; the player side filters in the menu.
        def deal_effect(user, actual_targets)
          return super if user.from_player_party?

          target = revivable_party_of(user).max_by(&:level)
          target.hp = target.max_hp / 2
          @scene.display_message_and_wait(parse_text_with_pokemon(66, 1590, target))
          summon_revived_ally(target) if target.position != -1
        end

        private

        # Get the fallen allies an overkill did not put out of the battle for good
        # @param user [PFM::PokemonBattler] user of the move
        # @return [Array<PFM::PokemonBattler>]
        def revivable_party_of(user)
          return @logic.all_battlers.select do |battler|
            next false unless battler.bank == user.bank
            next false unless battler.party_id == user.party_id
            next false unless battler.dead?

            next !battler.overkilled?
          end
        end
      end

      prepend OverkillCannotReturn
    end
  end
end
