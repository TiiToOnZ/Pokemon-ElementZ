module SOSBattles
  # Computation of the odds ruling an SOS call, read from the settings.
  module CallOdds
    class << self
      # Multiplier granted by the remaining HP of a whole side.
      # @note A band applies below its ratio, so a side above the last one keeps the base rate.
      # @param hp_ratio [Float] remaining HP over max HP of the side
      # @return [Numeric]
      def hp_multiplier(hp_ratio)
        band = Settings.hp_multipliers.find { |ratio, _multiplier| hp_ratio < ratio }
        return 1 unless band

        return band.last
      end

      # Odds, in percent, that a creature calls for help.
      # @param hp_ratio [Float] remaining HP over max HP of the caller side
      # @param adrenaline_orb_used [Boolean] whether an Adrenaline Orb was used this battle
      # @return [Float]
      def call_rate(hp_ratio, adrenaline_orb_used)
        rate = Settings.base_call_rate * hp_multiplier(hp_ratio).to_f
        rate *= Settings.adrenaline_orb_multiplier if adrenaline_orb_used

        return rate
      end

      # Odds, in percent, that an ally answers a call.
      # @param context [Hash] flags gathered by AnswerContext
      # @return [Float]
      def answer_rate(context)
        rate = Settings.base_call_rate * Settings.answer_rate_factor.to_f
        Settings.answer_multipliers.each { |flag, multiplier| rate *= multiplier if context[flag] }

        return rate
      end

      # Whether a side is weakened enough to be allowed to call for help.
      # @param hp_ratio [Float] remaining HP over max HP of the side
      # @return [Boolean]
      def distress?(hp_ratio)
        return hp_ratio <= Settings.trainer_distress_percent / 100.0
      end
    end
  end
end
