# Class that manage Music playing, save and menu access, timer and interpreter
class Game_System
  # Returns the name of the name window skin
  # If no specific name is set, returns the default window skin name
  # @return [String] The name of the name window skin
  def name_window_skin
    return @name_window_skin || windowskin_name
  end

  # Sets the name of the name window skin
  # @param name_window_skin [String] The name of the name window skin
  def name_window_skin=(name_window_skin)
    @name_window_skin = name_window_skin
  end
end

module UI
  # Module responsive of holding the whole message ui aspect
  module Message
  # Module defining the Message layout
    module Layout
      # Retrieve the current windowskin of the name window
            # @return [String]
            def current_name_windowskin
              nameskin_overwrite || current_layout.name_window_skin || $game_system.windowskin_name || NAME_SKIN
            end
    end
  end
end
