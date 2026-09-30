module SOSBattles
  # State of the SOS mechanic for the duration of one battle.
  class BattleState
    # Number of answered calls in the current chain
    # @return [Integer]
    attr_reader :chain

    def initialize
      @chain = 0
      @adrenaline_orb_used = false
      @ev_doubled = false
      @answered_this_turn = false
      @unanswered_this_turn = false
      @answered_last_turn = false
      @unanswered_last_turn = false
      @called_trainers = []
    end

    # Whether an Adrenaline Orb was used during this battle.
    # @return [Boolean]
    def adrenaline_orb_used?
      return @adrenaline_orb_used
    end

    # Remember an Adrenaline Orb was used, which raises the call rate for the rest of the battle.
    def record_adrenaline_orb
      @adrenaline_orb_used = true
    end

    # Whether the EV earned in this battle are doubled.
    # @return [Boolean]
    def ev_doubled?
      return @ev_doubled
    end

    # Whether an ally answered a call during the previous turn.
    # @return [Boolean]
    def answered_last_turn?
      return @answered_last_turn
    end

    # Whether the previous call went unanswered.
    # @return [Boolean]
    def previous_call_unanswered?
      return @unanswered_last_turn
    end

    # Record a call that was answered.
    def record_answer
      @chain += 1
      @ev_doubled = true
      @answered_this_turn = true
    end

    # Record a call that nobody answered.
    def record_unanswered
      @unanswered_this_turn = true
    end

    # Slide the current turn flags into the previous turn slots.
    def end_turn
      @answered_last_turn = @answered_this_turn
      @unanswered_last_turn = @unanswered_this_turn
      @answered_this_turn = false
      @unanswered_this_turn = false
    end

    # Record a trainer that joined the battle.
    # @param trainer_id [Integer] Studio ID of the trainer
    def record_called_trainer(trainer_id)
      @called_trainers << trainer_id
    end

    # Whether a trainer already joined this battle.
    # @param trainer_id [Integer] Studio ID of the trainer
    # @return [Boolean]
    def trainer_already_called?(trainer_id)
      return @called_trainers.include?(trainer_id)
    end
  end
end
