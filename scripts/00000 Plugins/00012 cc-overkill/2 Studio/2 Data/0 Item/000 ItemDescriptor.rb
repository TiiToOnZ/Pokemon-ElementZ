module PFM
  module ItemDescriptor
    class Wrapper
      # Refuses any item aimed at a creature an overkill pulverised, for the rest of the battle.
      module OverkillRejection
        # Row of the revival refusal in the plugin text file
        OVERKILL_NO_RETURN_TEXT_ID = 3

        # Build the user-facing message when on_creature_choice returns false for this creature
        # @param creature [PFM::Pokemon]
        # @return [String]
        def rejection_message(creature)
          return super unless battle_rejection_reason(creature) == :overkilled

          return parse_text_with_pokemon(Overkill::Settings.text_file_id, OVERKILL_NO_RETURN_TEXT_ID, creature)
        end

        private

        # Return the symbol describing why this creature can't receive the item in battle, or nil
        # @param creature [PFM::Pokemon]
        # @return [Symbol, nil]
        # @note Asked before the usability block of any item class, so every route is covered here.
        def battle_rejection_reason(creature)
          reason = super
          return reason if reason
          return :overkilled if $game_temp.in_battle && creature.dead? && creature.overkilled?

          return nil
        end
      end

      prepend OverkillRejection
    end
  end
end
