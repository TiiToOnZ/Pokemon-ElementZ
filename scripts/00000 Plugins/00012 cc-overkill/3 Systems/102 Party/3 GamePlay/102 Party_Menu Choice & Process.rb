module GamePlay
  class Party_Menu
    # Refuses a pulverised creature to Revival Blessing, and says why.
    module OverkillCannotReturn
      # Row of the revival refusal in the plugin text file
      OVERKILL_NO_RETURN_TEXT_ID = 3

      # Process the separation when the party is in mode :show_revival_menu_choice
      def show_revival_menu_choice
        creature = @party[@index]
        return super unless creature.dead? && creature.overkilled?

        display_message(parse_text_with_pokemon(Overkill::Settings.text_file_id, OVERKILL_NO_RETURN_TEXT_ID, creature))
      end
    end

    prepend OverkillCannotReturn
  end
end
