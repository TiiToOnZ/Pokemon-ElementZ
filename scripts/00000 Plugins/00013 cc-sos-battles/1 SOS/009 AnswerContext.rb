module SOSBattles
  # Battle facts feeding the multipliers of an answer roll.
  module AnswerContext
    class << self
      # Build the context hash CallOdds.answer_rate expects.
      # @param sos_state [SOSBattles::BattleState] state of the SOS mechanic for this battle
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param lead [PFM::PokemonBattler, nil] leading creature of the player bank
      # @return [Hash]
      def build(sos_state, caller_battler, lead)
        return {
          answered_last_turn: sos_state.answered_last_turn?,
          previous_call_unanswered: sos_state.previous_call_unanswered?,
          hit_super_effective: hit_super_effective_this_turn?(caller_battler),
          pressuring_lead: pressuring_lead?(lead)
        }
      end

      private

      # Whether the caller took a super effective hit during the current turn.
      # @note Reads the effectiveness the move resolved with, so moves that override it are accounted for.
      # @param battler [PFM::PokemonBattler] creature that called
      # @return [Boolean]
      def hit_super_effective_this_turn?(battler)
        return battler.damage_history.any? do |history|
          next false unless history.current_turn?

          next history.move&.super_effective?
        end
      end

      # Whether the leading creature of the player pressures the wild side.
      # @param lead [PFM::PokemonBattler, nil] leading creature of the player bank
      # @return [Boolean]
      def pressuring_lead?(lead)
        return false unless lead

        return %i[intimidate unnerve pressure].any? { |ability| lead.has_ability?(ability) }
      end
    end
  end
end
