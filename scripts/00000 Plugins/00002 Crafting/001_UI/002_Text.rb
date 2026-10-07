# ============================================================
# UI::CraftSystemUI::Texts
# ------------------------------------------------------------
# Module handling text elements of the Craft System UI.
# Responsible for creating and updating displayed texts
# such as the ingredient header and current category name.
# ============================================================

module UI
  module CraftSystemUI
    module Texts

      # Create the text elements of the crafting interface.
      # Initializes the ingredient header and current category label.
      # @return [void]
      def create_texts
        @text_ingredient = add_text(159, 37, 154, 24, 'INGREDIENTS', 1, color: 10)
        @text_category   = add_text(7, 37, 134, 24, category_name, 1, color: 10)
      end
      
      # Update the displayed category name.
      # Called when the current category changes.
      # @return [void]
      def update_category_text
        @text_category.text = category_name
      end
    end 
  end
end
