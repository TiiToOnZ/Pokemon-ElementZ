module Battle
  class Logic
    # Trainers joining an ongoing trainer battle when their side gets in distress.
    module TrainerReinforcement
      # Index of the reinforcement message in the plugin text file
      JOIN_MESSAGE_INDEX = 2

      # Create a new Logic instance
      # @param scene [Scene] scene that hold the logic object
      def initialize(scene)
        super
        @defeated_enemy_parties = []
      end

      # Function that distribute the exp to all Pokemon and switch dead pokemon
      def battle_phase_end
        super
        release_defeated_enemy_trainers
        attempt_trainer_reinforcement
      end

      private

      # Give their defeat scene to every enemy trainer beaten while the battle carries on.
      # @note Each is then taken out of the battle end sequence, so no defeat is ever played twice.
      def release_defeated_enemy_trainers
        return unless @battle_info.trainer_battle?
        return unless can_battle_continue?

        @battle_info.parties[1].each_index do |party_id|
          next if @defeated_enemy_parties.include?(party_id)
          next unless enemy_party_wiped?(party_id)

          play_trainer_defeat(party_id)
        end
      end

      # Whether every creature of an enemy party has fallen.
      # @param party_id [Integer] index of the party on bank 1
      # @return [Boolean]
      def enemy_party_wiped?(party_id)
        party = @battlers[1].compact.select { |battler| battler.party_id == party_id }
        return false if party.empty?

        return party.all?(&:dead?)
      end

      # Walk a beaten trainer back in, speak their defeat line, and retire them from the battle.
      # @param party_id [Integer] index of the party on bank 1
      def play_trainer_defeat(party_id)
        @defeated_enemy_parties << party_id
        fallen = extra_slot_occupant(1)
        # The field keeps its enlarged format on purpose: shrinking would force a recall on the player.
        release_extra_slot(fallen, false) if fallen&.dead? && fallen.party_id == party_id

        @scene.visual.show_beaten_trainer(1, party_id)
        defeat_text = @battle_info.defeat_texts[party_id]
        @scene.display_message_and_wait(defeat_text) if defeat_text && !defeat_text.empty?
        @scene.visual.forget_trainer_sprite(1, party_id)
        # Both lines are nil'd: the engine would say the defeat one twice, and let a beaten trainer gloat.
        @battle_info.defeat_texts[party_id] = nil
        @battle_info.victory_texts[party_id] = nil
      end

      # Let a trainer in distress call an ally trainer to the field.
      def attempt_trainer_reinforcement
        return unless @battle_info.trainer_battle?
        return unless @sos_request
        return unless field_can_grow?(1)
        return if $game_temp.battle_turn <= SOSBattles::Settings.grace_turns

        defender = alive_battlers(1).first
        return unless defender

        ratio = side_hp_ratio(defender)
        return unless SOSBattles::CallOdds.distress?(ratio)

        entry = pick_reinforcement_trainer(ratio)
        return unless entry

        summon_trainer(entry.first)
      end

      # Pick the trainer that answers, if the roll succeeds.
      # @param ratio [Float] team HP ratio of the calling side
      # @return [Array(Integer, Integer), nil]
      def pick_reinforcement_trainer(ratio)
        multiplier = SOSBattles::CallOdds.hp_multiplier(ratio)
        available = @sos_request.trainers.reject { |entry| @sos_state.trainer_already_called?(entry.first) }
        return available.find { |entry| rand(100) < entry.last * multiplier }
      end

      # Bring a whole trainer party on the enemy bank.
      # @param trainer_id [Integer] Studio ID of the trainer
      def summon_trainer(trainer_id)
        BattleInfo.add_trainer(@battle_info, 1, trainer_id)
        party_id = @battle_info.parties[1].size - 1
        # The whole party is built, not just the lead, so the AI has someone to send next.
        load_battlers_from_party(party_of(1, party_id), 1, party_id)
        register_reinforcement_ai(party_id)
        @sos_state.record_called_trainer(trainer_id)
        newcomer = @battlers[1].compact.find { |battler| battler.party_id == party_id }
        # Room first, so the creatures already out slide over before the trainer walks in.
        move_to_extra_slot(newcomer)
        @scene.visual.show_incoming_trainer(1, party_id, extra_position)
        announce_reinforcement(party_id)
        execute_pre_entry_events(newcomer)
        @scene.visual.send_out_from_trainer(1, party_id, newcomer)
        # The player's next creature comes out on its own, no choice screen.
        mirrored = settle_mirrored_slot(1)
        # Both banks entered at once, so their switch-in events are ordered against each other.
        execute_entry_events(newcomer, mirrored)
      end

      # Tell the player which trainer just joined.
      # @param party_id [Integer] index of the new party on bank 1
      def announce_reinforcement(party_id)
        name = @battle_info.names[1][party_id]
        return unless name

        message = parse_text(WildSOS::SOS_TEXT_FILE, JOIN_MESSAGE_INDEX, PFM::Text::TRNAME[0] => name)
        @scene.display_message_and_wait(message)
      end

      # Give the newcomer party its own AI, otherwise it never acts.
      # @param party_id [Integer] index of the new party on bank 1
      def register_reinforcement_ai(party_id)
        ai_level = @battle_info.ai_levels[1][party_id]
        return unless ai_level

        @scene.artificial_intelligences << AI::Base.registered(ai_level).new(@scene, 1, party_id, ai_level)
      end
    end
    prepend TrainerReinforcement
  end
end
