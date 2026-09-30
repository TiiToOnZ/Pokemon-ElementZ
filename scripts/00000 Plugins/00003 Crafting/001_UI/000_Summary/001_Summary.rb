# ============================================================
# UI::CraftSystemUI::Summary
# ------------------------------------------------------------
# Module handling the information panel of the Craft System UI.
# Manages creation, display and visibility of the crafted item
# summary (background, icon, name and description).
# ============================================================

module UI
  module CraftSystemUI
    module Summary 

      # Create the summary UI elements.
      # Initializes all graphical components if they are not already created.
      # @return [void]
      def create_summary
        @summary ||= {}
 
        @summary[:box] = add_sprite(0, 0, 'crafting/shadow').set_z(5)
        @summary[:item_desc_box] = add_sprite(0, 115, 'crafting/item_desc').set_z(6)

        @summary[:result_icon] = add_sprite(
          9, 121,
          :NO_INITIAL_IMAGE,
          type: ItemSprite
        ).set_z(7)

        @summary[:result_name] = add_text(44, 134, 108, 16, '', 1, color: 0)

        @summary[:result_description] = with_font(20) do
          add_text(15, 158, 300, 16, '', 0, color: 0)
        end

        hide_summary
      end

      # Display the summary for the given recipe.
      # Updates the icon, name and description according to recipe data.
      # @param recipe [Symbol] identifier of the recipe to display
      # @return [void]
      def show_summary(recipe)
        create_summary

        data = recipe_data(recipe)
        return unless data

        @summary[:result_icon].data = data[:result]
        @summary[:result_name].text = data_item(data[:result]).exact_name
        @summary[:result_description].multiline_text =
          data_item(data[:result]).description

        @summary.each_value { |element| element.visible = true }
      end

      # Hide all summary UI elements.
      # @return [void]
      def hide_summary
        return unless @summary
        @summary.each_value { |element| element.visible = false }
      end
    end
  end
end
