module Battle
  class Logic
    # SOS calls performed by wild creatures at the end of a turn.
    module WildSOS
      # ID of the plugin text file holding the SOS messages
      SOS_TEXT_FILE = 110_010

      # Index of the call message in the plugin text file
      CALL_MESSAGE_INDEX = 0

      # Index of the unanswered call message in the plugin text file
      NO_ANSWER_MESSAGE_INDEX = 1

      # Index of the message closing a scripted battle whose list of allies is spent
      NO_ALLY_LEFT_MESSAGE_INDEX = 3

      # State of the SOS mechanic for this battle
      # @return [SOSBattles::BattleState]
      attr_reader :sos_state

      # One-shot configuration this battle was started with
      # @return [SOSBattles::Request, nil]
      attr_reader :sos_request

      # Create a new Logic instance
      # @param scene [Scene] scene that hold the logic object
      def initialize(scene)
        super
        @sos_state = SOSBattles::BattleState.new
        @sos_request = $game_temp.sos_request
        $game_temp.sos_request = nil
      end

      # Function that distribute the exp to all Pokemon and switch dead pokemon
      def battle_phase_end
        super
        collapse_wild_field
        attempt_sos_call
        @sos_state.end_turn
      end

      # Whether this battle may ever see an extra battler join.
      # @note Only a trainer battle grows past a one-on-one.
      # @return [Boolean]
      def field_growth_possible?
        return super && (@battle_info.trainer_battle? || @base_vs_type == 1)
      end

      # Whether the Adrenaline Orb may be used right now.
      # @note Nobody calls in a trainer battle nor with the mechanic off, and nervousness does not stack.
      # @return [Boolean]
      def adrenaline_orb_usable?
        return false unless sos_allowed?

        return !@sos_state.adrenaline_orb_used?
      end

      # Make the wild side nervous for the rest of the battle.
      def use_adrenaline_orb
        @sos_state.record_adrenaline_orb
      end

      private

      # Ratio of the remaining HP over the max HP of the side of a battler.
      # @param battler [PFM::PokemonBattler] battler whose side is measured
      # @return [Float]
      def side_hp_ratio(battler)
        return SOSBattles::SideHealth.ratio(retrieve_party_from_battler(battler))
      end

      # Send the field back to its base format as soon as a single wild creature is left standing.
      # @note The survivor may be the ally, which must then take a fallen place or the format loses it.
      def collapse_wild_field
        return if @battle_info.trainer_battle?
        return if @battle_info.vs_type == @base_vs_type

        survivors = alive_battlers(1)
        return unless survivors.size == 1

        survivor = survivors.first
        seat_survivor_at_base_place(survivor)
        # Releasing the place it still holds would hide the survivor itself.
        return log_error("SOS left the survivor on the extra place: #{survivor}") if survivor.position == extra_position

        release_extra_slot(@battlers[1][extra_position], true)
        # Shown once the format is back down: an info bar slides towards the place it reads at build time.
        @scene.visual.reseat_battler(survivor)
      end

      # Trade the survivor with a fallen creature so it stands on a place the base format holds.
      # @note Only what each place shows is re-pointed, or the survivor would cross the field for nothing.
      # @param survivor [PFM::PokemonBattler] the last wild creature standing
      def seat_survivor_at_base_place(survivor)
        return unless survivor.position == extra_position

        fallen = (0...extra_position).map { |index| @battlers[1][index] }.compact.find(&:dead?)
        return unless fallen

        switch_battlers(fallen, survivor)
      end

      # Answer a call that nobody can answer any more, and end the calls of this battle.
      # @note Spoken right after the call itself, so the two lines read as one beat.
      def announce_no_ally_left
        @sos_request.exhaustion_told
        @scene.display_message_and_wait(parse_text(SOS_TEXT_FILE, NO_ALLY_LEFT_MESSAGE_INDEX))
      end

      # Creature the battle opened with, the only one an imposed list ever answers to.
      # @note Read on the first turn, not at init, when the engine may not have loaded its battlers yet.
      # @return [PFM::PokemonBattler, nil]
      def sos_summoner
        return @sos_summoner ||= battler(1, 0)
      end

      # Whether a creature is allowed to call given how this battle was set up.
      # @note A scripted list belongs to its summoner, so focusing it down is an offer to cut the wave.
      # @param battler [PFM::PokemonBattler] creature that would call
      # @return [Boolean]
      def allowed_to_call?(battler)
        return true unless @sos_request&.species_imposed?

        return battler == sos_summoner
      end

      # Let the lone wild creature try to call for help.
      def attempt_sos_call
        sos_summoner
        return if @sos_request&.calls_over?

        caller_battler = sos_caller
        return unless caller_battler

        rate = SOSBattles::CallOdds.call_rate(side_hp_ratio(caller_battler), @sos_state.adrenaline_orb_used?)
        return unless rand(100) < rate

        message = parse_text(SOS_TEXT_FILE, CALL_MESSAGE_INDEX, PFM::Text::PKNICK[0] => caller_battler.given_name)
        @scene.display_message_and_wait(message)
        return announce_no_ally_left if @sos_request&.species_exhausted?

        answer_sos_call(caller_battler)
      end

      # Roll the answer of an SOS call and bring the ally in when it succeeds.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      def answer_sos_call(caller_battler)
        context = SOSBattles::AnswerContext.build(@sos_state, caller_battler, alive_battlers(0).first)
        unless rand(100) < SOSBattles::CallOdds.answer_rate(context)
          @sos_state.record_unanswered
          return @scene.display_message_and_wait(parse_text(SOS_TEXT_FILE, NO_ANSWER_MESSAGE_INDEX))
        end

        creature = draw_reinforcement_with_chain_shiny(caller_battler)
        return @sos_state.record_unanswered unless creature

        @sos_state.record_answer
        SOSBattles::ChainRewards.apply(creature, @sos_state.chain)
        enlist_creature(1, caller_battler.party_id, creature)
        grow_field(1, creature, caller_battler.party_id)
      end

      # Draw the answering creature with the shiny rolls the chain grants.
      # @note code_initialize consumes the rolls, so they are posted before the creature exists.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @return [PFM::Pokemon, nil]
      def draw_reinforcement_with_chain_shiny(caller_battler)
        $game_temp.sos_chain_shiny_rolls = SOSBattles::ChainRewards.shiny_rolls(@sos_state.chain)
        return SOSBattles::ReinforcementFactory.draw(caller_battler, @sos_request)
      ensure
        $game_temp.sos_chain_shiny_rolls = 0
      end

      # Lone wild creature allowed to call for help, if any.
      # @return [PFM::PokemonBattler, nil]
      def sos_caller
        return unless sos_allowed?
        return unless field_can_grow?(1)
        return if $game_temp.battle_turn <= SOSBattles::Settings.grace_turns

        battlers = alive_battlers(1)
        return unless battlers.size == 1

        battler = battlers.first
        return unless allowed_to_call?(battler)
        return unless battler.status.zero?
        return if battler.effects.has?(&:out_of_reach?)

        return battler
      end

      # Whether the SOS mechanic is enabled for this battle.
      # @return [Boolean]
      def sos_allowed?
        return false if @battle_info.trainer_battle?
        # Nobody can knock anything out in a Safari battle, so a second creature would never leave.
        return false if @scene.safari?
        # A call turns a one-on-one into a two-on-one, and nothing else.
        return false unless @base_vs_type == 1
        return @sos_request.enabled if @sos_request

        return $game_switches[Yuki::Sw::SOS_ENABLED]
      end
    end
    prepend WildSOS
  end
end
