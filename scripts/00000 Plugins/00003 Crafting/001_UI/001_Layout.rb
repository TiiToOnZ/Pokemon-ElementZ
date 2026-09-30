# ============================================================
# UI::CraftSystemUI::Layout
# ------------------------------------------------------------
# Module handling the visual layout of the Craft System UI.
# Responsible for creating and positioning all graphical
# components such as frames, grids, ingredient boxes,
# navigation arrows and scroll elements.
# ============================================================

module UI
  module CraftSystemUI
    module Layout

      # Create all base sprites for the crafting interface.
      #
      # Initializes:
      # - Main frame (FR / EN support)
      # - Recipe grid
      # - Ingredient display box
      # - Scroll bar
      # - Navigation arrows (left / right)
      # - Scroll knob
      #
      # @return [Hash<Symbol, Sprite>]
      # Returns a hash containing all created sprites.
      def create_box
        {
          frame: add_sprite(
            0, 0,
            'crafting/frames'
          ).src_rect.set(0, $options.language == 'fr' ? 28 : 0, 320, 28),

          grid: add_sprite(4, 34, 'crafting/grid'),

          ing_box: add_sprite(156, 34, 'crafting/ing_box'),

          scroll_bar: add_sprite(147, 35, 'crafting/scroll'),

          left: add_sprite(20, 43, 'crafting/inputs')
                  .src_rect.set(0, 0, 12, 12),

          right: add_sprite(116, 43, 'crafting/inputs')
                   .src_rect.set(12, 0, 12, 12),

          knob: add_sprite(146, Constants::KNOB_BASE_Y, 'crafting/knob')
        }
      end
    end
  end
end
