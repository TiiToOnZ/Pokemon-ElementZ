# ============================================================
# UI::CraftSystemUI::RecipeGrid
# ------------------------------------------------------------
# Module handling the recipe grid display of the Craft System UI.
# Manages slot creation, grid refresh logic, cursor positioning
# and scroll knob updates.
# ============================================================

module UI
  module CraftSystemUI
    module RecipeGrid

      # Create the recipe grid and cursor.
      # Initializes slot coordinates and cursor sprite.
      # @return [void]
      def create_recipe_grid
        @cursor&.dispose
        @recipe_slots = []

        start_x, start_y = 11, 72

        Constants::GRID_SIZE.times do |i|
          col = i % Constants::GRID_COLS
          row = i / Constants::GRID_COLS

          @recipe_slots << {
            x: start_x + col * 32,
            y: start_y + row * 32,
            sprite: nil
          }
        end
        
        @cursor = UI::CraftSystemUI::Cursor.new(@viewport).set_z(3)
        @cursor.set_position(@recipe_slots.first[:x], @recipe_slots.first[:y])
        @cursor.visible = false
      end

      # Refresh the recipe grid using the provided recipe list.
      # Updates slot sprites, cursor visibility and scroll knob.
      # @param recipes [Array<Object>] recipes to display
      # @return [void]
      def refresh_recipe_grid(recipes)
        if recipes.empty?
          @recipe_slots.each do |slot|
            slot[:sprite]&.dispose
            slot[:sprite] = nil
          end
          @cursor.visible = false
          update_knob_position
          return
        end

        base_index = @scroll_row * Constants::GRID_COLS

        @recipe_slots.each_with_index do |slot, i|
          recipe = recipes[base_index + i]

          if recipe
            slot[:sprite] ||= add_sprite(
              slot[:x], slot[:y],
              :NO_INITIAL_IMAGE,
              type: ItemSprite
            ).set_z(2)

            slot[:sprite].visible = true
            slot[:sprite].data = recipe_data(recipe)[:result]
          else
            slot[:sprite]&.dispose
            slot[:sprite] = nil
          end
        end

        current_slot = @recipe_index - base_index
        if current_slot.between?(0, @recipe_slots.size - 1)
          slot = @recipe_slots[current_slot]
          @cursor.set_position(slot[:x] - 2, slot[:y] - 2)
          @cursor.visible = true
        else
          @cursor.visible = false
        end

        update_knob_position
      end

      # Update the scroll knob position based on current selection.
      # @return [void]
      def update_knob_position
        total_rows = (@recipes.size.to_f / Constants::GRID_COLS).ceil
        return @ui[:knob].y = Constants::KNOB_BASE_Y if total_rows <= 1

        max_travel = Constants::SCROLL_BAR_HEIGHT - Constants::KNOB_HEIGHT
        current_row = @recipe_index / Constants::GRID_COLS
        ratio = current_row.to_f / (total_rows - 1)

        @ui[:knob].y = Constants::KNOB_BASE_Y + (ratio * max_travel).round
      end
    end
  end
end
