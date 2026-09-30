# Namespace of the SOS Battles plugin.
module SOSBattles
  # Tunable settings of the plugin.
  module Settings
    class << self
      # Call rate of a wild creature before any multiplier, in percent
      # @return [Integer]
      attr_accessor :base_call_rate

      # Odds, in percent, that the answer comes from the caller's family instead of the encounter group
      # @return [Integer]
      attr_accessor :family_branch_rate

      # Whether the family branch may answer with an evolution of the caller
      # @return [Boolean]
      attr_accessor :family_branch_allows_evolution

      # Odds, in percent, that a call nobody else answered is taken by the encounter group rather than by the caller's own species
      # @return [Integer]
      attr_accessor :group_fallback_rate

      # Multiplier applied to the shiny rolls granted by the SOS chain
      # @return [Integer]
      attr_accessor :chain_shiny_multiplier

      # Number of turns during which no reinforcement may arrive
      # @return [Integer]
      attr_accessor :grace_turns

      # Percentage of team HP at or below which a trainer is considered in distress
      # @return [Integer]
      attr_accessor :trainer_distress_percent

      # Multiplier the call rate gains once an Adrenaline Orb was used
      # @return [Numeric]
      attr_accessor :adrenaline_orb_multiplier

      # Multiple of the base rate the answer roll starts from
      # @return [Numeric]
      attr_accessor :answer_rate_factor

      # Rewards of the chain, each row being [chain, perfect IVs, hidden ability percent, shiny rolls]
      # @return [Array<Array<Numeric>>]
      attr_reader :chain_thresholds

      # Call rate multipliers of a weakened side, each row being [ratio below which it applies, multiplier]
      # @return [Array<Array<Numeric>>]
      attr_reader :hp_multipliers

      # Answer roll multipliers, keyed by the flags AnswerContext builds
      # @return [Hash{Symbol => Numeric}]
      attr_reader :answer_multipliers

      # @param thresholds [Array<Array<Numeric>>] rows of [chain, perfect IVs, hidden ability percent, shiny rolls]
      def chain_thresholds=(thresholds)
        @chain_thresholds = validated_rows(thresholds, 4, 'chain_thresholds', '[chain, perfect IVs, hidden ability percent, shiny rolls]')
      end

      # @param multipliers [Array<Array<Numeric>>] rows of [ratio below which it applies, multiplier]
      def hp_multipliers=(multipliers)
        @hp_multipliers = validated_rows(multipliers, 2, 'hp_multipliers', '[ratio below which it applies, multiplier]')
      end

      # @param multipliers [Hash{Symbol => Numeric}] multiplier of each answer roll flag
      def answer_multipliers=(multipliers)
        valid = multipliers.is_a?(Hash) && multipliers.all? { |flag, value| flag.is_a?(Symbol) && value.is_a?(Numeric) }
        raise ArgumentError, 'SOSBattles::Settings.answer_multipliers expects a Hash of Symbol => number' unless valid

        @answer_multipliers = multipliers
      end

      private

      # Refuse a malformed table where the game creator wrote it, rather than deep inside a battle.
      # @param rows [Object] value the creator assigned
      # @param width [Integer] number of values every row must hold
      # @param setting [String] name of the setting, for the message
      # @param shape [String] shape of one row, for the message
      # @return [Array<Array<Numeric>>]
      def validated_rows(rows, width, setting, shape)
        valid = rows.is_a?(Array) && rows.all? { |row| row.is_a?(Array) && row.size == width && row.all?(Numeric) }
        raise ArgumentError, "SOSBattles::Settings.#{setting} expects an Array of rows shaped #{shape}" unless valid

        return rows
      end
    end

    self.base_call_rate = 10
    self.family_branch_rate = 15
    self.family_branch_allows_evolution = false
    self.group_fallback_rate = 0
    self.chain_shiny_multiplier = 1
    self.grace_turns = 1
    self.trainer_distress_percent = 50
    self.adrenaline_orb_multiplier = 2
    self.answer_rate_factor = 4
    self.hp_multipliers = [[0.2, 5], [0.5, 3]]
    self.answer_multipliers = { answered_last_turn: 1.5, previous_call_unanswered: 3, hit_super_effective: 2, pressuring_lead: 1.2 }
    self.chain_thresholds = [
      [5, 1, 0, 1],
      [10, 2, 5, 1],
      [11, 2, 5, 5],
      [20, 3, 10, 5],
      [21, 3, 10, 9],
      [30, 4, 15, 9],
      [31, 4, 15, 13]
    ]
  end
end
