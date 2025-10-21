# Save Load Tweaks - Written by FrivolousAqua
# Altered save menu with the intent of giving more visual feedback to the player.
# Changes made include:
# - Corruption notification: explains that a save is corrupted, how to find a backup, and if they'd like to start a new game
# - Ask the player if they'd like to overwrite a previous save, and confirm when data has been saved
# - Visually refresh the save data screen so that it shows the save in live time

module GamePlay
  class Load
    private

    # When you select an option on the load screen
    def action_a
      Graphics.sort_z
      Save.save_index = Configs.save_config.single_save? ? 0 : @index + 1
      # This is a valid save file
      if @index < @all_saves.size && @all_saves[@index]
        play_decision_se
        Graphics.update
        load_game
      # This is either a new game or something corrupted
      elsif @index < @all_saves.size
        # Corruption notification
        # This should only come up if you're not on the new game button, meaning that the file is corrupted
        play_buzzer_se # ouch
        display_message(ext_text(311_110, 4))
        display_message(ext_text(311_110, 5))
        corruptWarning = display_message(ext_text(311_110, 6), 2, ext_text(311_110, 1), ext_text(311_110, 2))
        create_new_game if corruptWarning == 0
        # Okay, you're actually making a new game
      else
        play_decision_se
        create_new_game
      end
    end
  end

  class Save
    private

    # When you select an option on the save screen
    def action_a
      Graphics.sort_z
      play_decision_se # Play an additional sound in the beginning to give the player feedback

      # If the player is selecting a file that exists already, ask if they want to overwrite it
      saveWarning = display_message(ext_text(311_110, 0), 2, ext_text(311_110, 1), ext_text(311_110, 2)) if @index < @all_saves.size

      # Begin the save process; only continues if the save warning value is 0 or it's a new game
      if @index == @all_saves.size or saveWarning == 0
        Save.save_index = Configs.save_config.single_save? ? 0 : @index + 1
        save_game # Save the game here
        @saved = true
        @running = false
        # Vanity
        # This will refresh the save sign; this is the UI
        @all_saves[@index] = PFM.game_state
        load_sign_data
        # Let the player know that it's done
        play_save_se
        display_message(ext_text(311_110, 3))
      end
    end
  end
end