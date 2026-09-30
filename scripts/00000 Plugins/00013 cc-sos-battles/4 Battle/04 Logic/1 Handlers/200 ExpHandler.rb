module Battle
  class Logic
    class ExpHandler
      # EV doubled for the rest of the battle once an SOS call was answered.
      module SOSDoubledEV
        # Distribute the ev to evables depending on the enemy that was taken down
        # @param evable [Array<PFM::PokemonBattler>]
        # @param enemy [PFM::PokemonBattler]
        def distribute_ev_to(evable, enemy)
          super
          return unless @logic.sos_state.ev_doubled?

          # Only the base yield is doubled, the power item bonuses are granted once, as in the games.
          evable.each { |receiver| receiver.original.add_bonus(enemy.battle_list) }
        end
      end
      prepend SOSDoubledEV
    end
  end
end
