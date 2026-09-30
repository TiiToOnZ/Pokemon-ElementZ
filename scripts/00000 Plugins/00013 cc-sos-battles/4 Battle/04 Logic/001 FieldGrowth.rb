module Battle
  class Logic
    # Insertion and removal of an extra battler on a bank, in the middle of a battle.
    module FieldGrowth
      # Format the battle started with, before any growth
      # @return [Integer]
      attr_reader :base_vs_type

      # Create a new Logic instance
      # @param scene [Scene] scene that hold the logic object
      def initialize(scene)
        super
        @base_vs_type = @battle_info.vs_type
        @extra_slot_open = {}
        @mirrored_holes = []
        prepare_extra_position_effects
      end

      # Position of the extra slot, one past the base format.
      # @return [Integer]
      def extra_position
        return @base_vs_type
      end

      # Whether this battle may ever see an extra battler join.
      # @return [Boolean]
      def field_growth_possible?
        return @base_vs_type < 3
      end

      # Whether a bank may receive a battler on its extra slot right now.
      # @note An explicit flag, because the battler array also holds the reserve at that very index.
      # @param bank [Integer] bank to grow
      # @return [Boolean]
      def field_can_grow?(bank)
        return false unless field_growth_possible?

        occupant = extra_slot_occupant(bank)
        return occupant.nil? || occupant.dead?
      end

      # Battler currently standing on the extra slot of a bank.
      # @note Read from the array, never cached: switch_battlers moves who stands there on its own.
      # @param bank [Integer] bank to read
      # @return [PFM::PokemonBattler, nil]
      def extra_slot_occupant(bank)
        return unless @extra_slot_open[bank]

        return @battlers[bank][extra_position]
      end

      # Bring a creature on the extra slot of a bank.
      # @note The creature must already belong to the party it is declared in.
      # @param bank [Integer] bank receiving the creature
      # @param creature [PFM::Pokemon] creature to bring in
      # @param party_id [Integer] index of the party the creature belongs to
      # @return [PFM::PokemonBattler, nil]
      def grow_field(bank, creature, party_id)
        return unless field_can_grow?(bank)

        battler = PFM::PokemonBattler.new(creature, @scene)
        battler.bank = bank
        battler.party_id = party_id
        battler.position = extra_position
        battler.place_in_party = party_of(bank, party_id).index(creature)
        battler.bag = @battle_info.bags[bank][party_id] || PFM::Bag.new
        battler.last_battle_turn = $game_temp.battle_turn
        occupy_extra_slot(bank, battler)
        open_mirrored_hole(bank)
        execute_pre_entry_events(battler)
        @scene.visual.show_incoming_battler(battler, from_ball: owned_party?(bank, party_id))
        execute_entry_events(battler)

        return battler
      end

      # Make room for an existing battler of a bank on its free extra slot, without revealing it yet.
      # @note Its trainer walks in before it does, so the reveal is left to send_out_from_trainer.
      # @param battler [PFM::PokemonBattler] battler joining the field
      # @return [PFM::PokemonBattler, nil]
      def move_to_extra_slot(battler)
        return unless field_can_grow?(battler.bank)

        @battlers[battler.bank].delete(battler)
        battler.position = extra_position
        battler.last_battle_turn = $game_temp.battle_turn
        occupy_extra_slot(battler.bank, battler)

        return battler
      end

      # Free the extra slot of a bank.
      # @param battler [PFM::PokemonBattler] battler leaving the field
      # @param restore_format [Boolean] whether the field goes back to its base format
      def release_extra_slot(battler, restore_format)
        bank = battler.bank
        @scene.visual.hide_outgoing_battler(battler)
        battler.position = -1
        @extra_slot_open[bank] = false
        return unless restore_format

        close_mirrored_hole(bank)
        release_mirrored_slot(bank)
        @battle_info.vs_type = @base_vs_type
        $game_temp.vs_type = @base_vs_type
        @scene.visual.refresh_field_positions
      end

      private

      # Set a creature up before its sprite is revealed, as the engine does ahead of a switch-in.
      # @note Illusion picks its disguise from the party as it stands right now, so it cannot wait for the reveal.
      # @param battler [PFM::PokemonBattler] creature about to be shown
      def execute_pre_entry_events(battler)
        switch_handler.execute_pre_switch_events(battler, battler)
      end

      # Run the switch-in events of creatures that just took a place, fastest first.
      # @note Each one is its own switch-in, the shape the engine uses when a battle opens.
      # @param battlers [Array<PFM::PokemonBattler, nil>] creatures that just entered the field
      def execute_entry_events(*battlers)
        battlers.compact.sort_by(&:spd).reverse.each do |battler|
          switch_handler.execute_switch_events(battler, battler)
        end
      end

      # Give the place the field may gain its own effect handler, on every bank.
      # @note init_effects sizes them on the starting format, so a reader indexing that place would find nil.
      def prepare_extra_position_effects
        return unless field_growth_possible?

        @position_effects.each { |bank_effects| bank_effects[extra_position] ||= Effects::EffectsHandler.new }
      end

      # Party the battle info holds at one place of a bank.
      # @note BattleInfo exposes bare nested arrays with no reader for a single party.
      # @param bank [Integer] bank holding the party
      # @param party_id [Integer] index of the party on that bank
      # @return [Array<PFM::Pokemon>]
      def party_of(bank, party_id)
        return @battle_info.parties[bank][party_id]
      end

      # Add a creature to a party in the middle of a battle, so the engine counts it as one of theirs.
      # @param bank [Integer] bank holding the party
      # @param party_id [Integer] index of the party on that bank
      # @param creature [PFM::Pokemon] creature joining the party
      def enlist_creature(bank, party_id, creature)
        party_of(bank, party_id) << creature
      end

      # Whether a party belongs to somebody who could throw a ball.
      # @note BattleInfo only names a party that has a trainer, so a nameless one is wild.
      # @param bank [Integer] bank holding the party
      # @param party_id [Integer] index of the party on that bank
      # @return [Boolean]
      def owned_party?(bank, party_id)
        return !@battle_info.names[bank][party_id].nil?
      end

      # The two banks of a battle always face each other.
      # @param bank [Integer] bank to mirror
      # @return [Integer]
      def mirrored_bank(bank)
        return bank.zero? ? 1 : 0
      end

      # Put a battler on the extra slot, pushing whoever sat there off the field.
      # @note Inserting keeps the reserve in order, the displaced battler lands just outside the field.
      # @param bank [Integer] bank receiving the battler
      # @param battler [PFM::PokemonBattler] battler taking the slot
      def occupy_extra_slot(bank, battler)
        @battlers[bank].insert(extra_position, battler)
        @extra_slot_open[bank] = true
        @battle_info.vs_type = extra_position + 1
        $game_temp.vs_type = @battle_info.vs_type
        @scene.visual.refresh_field_positions
      end

      # Leave the place the format just opened on the other bank empty.
      # @note An empty entry is the only way to free a place while the reserve stays reachable by the switch menu.
      # @param grown_bank [Integer] bank that just received a battler
      def open_mirrored_hole(grown_bank)
        bank = mirrored_bank(grown_bank)
        return if @battlers[bank][extra_position].nil?

        @battlers[bank].insert(extra_position, nil)
        @mirrored_holes << bank
      end

      # Fill the empty place back in once the field goes down to its base format.
      # @param released_bank [Integer] bank whose extra slot was just freed
      def close_mirrored_hole(released_bank)
        bank = mirrored_bank(released_bank)
        return unless @mirrored_holes.delete(bank)
        return unless @battlers[bank][extra_position].nil?

        @battlers[bank].delete_at(extra_position)
      end

      # Bring the other bank in line with the format it just gained.
      # @note The trainer case, where the other bank must fight the enlarged field. The wild case leaves it empty.
      # @param grown_bank [Integer] bank that just received a battler
      # @return [PFM::PokemonBattler, nil] battler that took the place, if any
      def settle_mirrored_slot(grown_bank)
        bank = mirrored_bank(grown_bank)
        battler = @battlers[bank][extra_position]
        return unless battler
        return if battler.position == extra_position

        battler.position = extra_position
        battler.last_battle_turn = $game_temp.battle_turn
        @extra_slot_open[bank] = true
        execute_pre_entry_events(battler)
        @scene.visual.show_incoming_battler(battler)

        return battler
      end

      # Take the mirrored battler back off the field when the format goes down again.
      # @note Its position goes back to -1, or can_fight? keeps claiming a place the format no longer holds.
      # @param released_bank [Integer] bank whose extra slot was just freed
      def release_mirrored_slot(released_bank)
        bank = mirrored_bank(released_bank)
        battler = extra_slot_occupant(bank)
        return unless battler

        @scene.visual.hide_outgoing_battler(battler)
        battler.position = -1
        @extra_slot_open[bank] = false
      end
    end
    prepend FieldGrowth
  end
end
