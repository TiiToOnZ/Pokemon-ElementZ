module SOSBattles
  # Fabrication of the creature answering an SOS call.
  class ReinforcementFactory
    class << self
      # Draw the creature answering the call.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param sos_request [SOSBattles::Request, nil] one-shot configuration the battle was started with
      # @return [PFM::Pokemon, nil]
      def draw(caller_battler, sos_request)
        return imposed_species(caller_battler, sos_request) if sos_request&.species_imposed?

        encounter = current_encounter
        creature = draw_pool_member(caller_battler, encounter)
        creature ||= draw_family_member(caller_battler, encounter)
        creature ||= draw_group_member(encounter)
        creature ||= draw_caller_kin(caller_battler, encounter)

        return creature
      end

      private

      # Next creature of the list a scripted battle was given.
      # @note The list is the whole cast: once spent nobody answers, so a scene never borrows the area.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param sos_request [SOSBattles::Request] configuration the battle was started with
      # @return [PFM::Pokemon, nil]
      def imposed_species(caller_battler, sos_request)
        db_symbol = sos_request.next_species
        return unless db_symbol

        return PFM::Pokemon.new(db_symbol, caller_battler.level)
      end

      # Encounter group serving as the default reinforcement pool.
      # @note Private in PFM::Wild_Battle, hence the send, and nil where no group is declared.
      # @return [Studio::Group, nil]
      def current_sos_group
        return $wild_battle&.send(:current_selected_group)
      rescue StandardError => e
        log_error("SOS could not resolve the encounter group: #{e.message}")
        return nil
      end

      # Encounter the area offers this call, drawn once and read by every branch for its level range.
      # @return [Studio::Group::Encounter, nil]
      def current_encounter
        group = current_sos_group
        return unless group

        return SOSBattles::ReinforcementPool.pick_encounter(group.encounters, rand)
      end

      # Draw a species the game creator declared the caller may call for.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param encounter [Studio::Group::Encounter, nil] encounter giving the level range
      # @return [PFM::Pokemon, nil]
      def draw_pool_member(caller_battler, encounter)
        member = SOSBattles::CallPools.species_for(caller_battler)
        return unless member

        db_symbol, form = member
        if data_creature(db_symbol).db_symbol == :__undef__
          log_error("SOS pool of #{caller_battler.db_symbol} names an unknown creature: #{db_symbol}")
          return
        end

        return PFM::Pokemon.new(db_symbol, answer_level(caller_battler, encounter), false, false, form)
      end

      # Draw a family member of the caller, on the rare branch only.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param encounter [Studio::Group::Encounter, nil] encounter giving the level range
      # @return [PFM::Pokemon, nil]
      def draw_family_member(caller_battler, encounter)
        return unless rand(100) < SOSBattles::Settings.family_branch_rate

        form = data_creature(caller_battler.db_symbol).forms.find { |creature_form| creature_form.form == caller_battler.form }
        return unless form

        allow_evolution = SOSBattles::Settings.family_branch_allows_evolution
        member = SOSBattles::ReinforcementPool.family_member(form, allow_evolution)
        return unless member

        db_symbol, member_form = member
        return if data_creature(db_symbol).db_symbol == :__undef__

        return PFM::Pokemon.new(db_symbol, answer_level(caller_battler, encounter), false, false, member_form || 0)
      end

      # Draw the local creature the area offers, on the share of the calls the game creator left to it.
      # @param encounter [Studio::Group::Encounter, nil] encounter drawn in the group of the tile
      # @return [PFM::Pokemon, nil]
      def draw_group_member(encounter)
        return unless encounter
        return unless rand(100) < SOSBattles::Settings.group_fallback_rate

        return encounter.to_creature
      end

      # Answer with one of the caller's own kind, the call nobody else took.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param encounter [Studio::Group::Encounter, nil] encounter giving the level range
      # @return [PFM::Pokemon]
      def draw_caller_kin(caller_battler, encounter)
        return PFM::Pokemon.new(caller_battler.db_symbol, answer_level(caller_battler, encounter), false, false, caller_battler.form)
      end

      # Level the creature answering the call turns up at.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @param encounter [Studio::Group::Encounter, nil] encounter giving the level range
      # @return [Integer]
      def answer_level(caller_battler, encounter)
        return caller_battler.level unless encounter

        return rand(encounter.level_setup.range)
      end
    end
  end
end
