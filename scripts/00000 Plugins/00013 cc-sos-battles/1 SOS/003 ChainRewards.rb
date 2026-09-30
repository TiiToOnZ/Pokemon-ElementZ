module SOSBattles
  # Rewards granted to a creature summoned during an SOS chain, read from the settings.
  module ChainRewards
    class << self
      # Apply the SOS chain rewards to a freshly generated creature.
      # @param creature [PFM::Pokemon] creature answering the call
      # @param chain [Integer] number of answered calls
      def apply(creature, chain)
        perfect = perfect_ivs(chain)
        %i[iv_hp iv_atk iv_dfe iv_spd iv_ats iv_dfs].sample(perfect).each do |stat|
          creature.send(:"#{stat}=", 31)
        end
        return unless rand(100) < hidden_ability_rate(chain)
        return unless creature.data.abilities.size > 2

        creature.ability_index = 2
        creature.update_ability
      end

      # Number of stats forced to a perfect IV.
      # @param chain [Integer] number of answered calls
      # @return [Integer]
      def perfect_ivs(chain)
        return reward_at(chain, 1)
      end

      # Odds, in percent, that the summoned creature gets its hidden ability.
      # @param chain [Integer] number of answered calls
      # @return [Integer]
      def hidden_ability_rate(chain)
        return reward_at(chain, 2)
      end

      # Number of extra shiny rolls granted to the summoned creature.
      # @param chain [Integer] number of answered calls
      # @return [Integer]
      def shiny_rolls(chain)
        return reward_at(chain, 3) * Settings.chain_shiny_multiplier
      end

      private

      # Value of one reward column for a given chain.
      # @param chain [Integer] number of answered calls
      # @param column [Integer] index of the column in a chain_thresholds row
      # @return [Integer]
      def reward_at(chain, column)
        entry = Settings.chain_thresholds.reverse.find { |threshold| chain >= threshold.first }
        return 0 unless entry

        return entry[column]
      end
    end
  end
end
