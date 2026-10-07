# ============================================================
# UI::CraftSystemUI::Cursor
# ------------------------------------------------------------
# Animated cursor used in the Craft System UI.
# Handles sprite loading and looping animation.
# ============================================================

module UI
  module CraftSystemUI
    class Cursor < SpriteSheet

      # Create the cursor sprite and initialize its animation.
      # @param viewport [Viewport]
      # @return [void]
      def initialize(viewport)
        super(viewport, 1, 2)
        @animation = nil
        @file = 'crafting/cursor'
        @axis = :sy=
        
        init_sprite
        init_animation
      end
      
      # Update the cursor animation.
      # @return [void]
      def update
        @animation.update if @animation
      end
      
      # Load the cursor sprite bitmap.
      # @return [void]
      def init_sprite
        set_bitmap(@file, :interface)
      end
      
      # Initialize the looping animation.
      # Alternates between frame 0 and 1.
      # @return [void]
      def init_animation
        ya = Yuki::Animation
        @animation = ya.timed_loop_animation(1, [
          ya.send_command_to(self, :sy=, 0),
          ya.wait(0.5),
          ya.send_command_to(self, :sy=, 1)
        ]).start
      end
    end
  end
end
