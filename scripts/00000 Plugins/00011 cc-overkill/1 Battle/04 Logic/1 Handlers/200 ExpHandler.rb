module Battle
  class Logic
    class ExpHandler
      # Grants a better yield when the enemy was taken down by an overkill.
      module OverkillRewards
        # Distribute the experience for a single pokemon
        # @param enemy [PFM::PokemonBattler]
        # @return [Hash{ PFM::PokemonBattler => Integer }]
        def distribute_exp_for(enemy)
          # super sets the flag, and the mark lasts the whole battle, so a second call would pay twice.
          already_paid = enemy.exp_distributed
          exp_data = super
          return exp_data if already_paid || !overkilled_foe?(enemy)

          return exp_data.transform_values { |amount| (amount * Overkill::Settings.exp_multiplier).to_i }
        end

        # Distribute the ev to evables depending on the enemy that was taken down
        # @param evable [Array<PFM::PokemonBattler>]
        # @param enemy [PFM::PokemonBattler]
        def distribute_ev_to(evable, enemy)
          super
          return unless overkilled_foe?(enemy)

          # Only the base yield is granted again, the power item bonuses stay granted once.
          (Overkill::Settings.ev_multiplier - 1).times do
            evable.each { |receiver| receiver.original.add_bonus(enemy.battle_list) }
          end
        end

        private

        # Tell if the enemy was taken down by an overkill and belongs to the foe side
        # @param enemy [PFM::PokemonBattler]
        # @return [Boolean]
        def overkilled_foe?(enemy)
          return false if enemy.bank == 0

          return enemy.overkilled?
        end
      end

      prepend OverkillRewards
    end
  end
end
