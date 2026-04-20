# ============================================================
# UI::CraftSystemUI::Navigation
# ------------------------------------------------------------
# Module handling navigation logic of the Craft System UI.
# Manages recipe selection movement, category switching
# and scroll adjustments within the recipe grid.
# ============================================================

module UI
  module CraftSystemUI
    module Navigation

      # Move the current recipe selection.
      # @param delta [Integer] offset applied to selection index
      # @return [void]
      def move(delta)
        return if @recipes.empty?

        @recipe_index = (@recipe_index + delta).clamp(0, @recipes.size - 1)
        adjust_scroll
        refresh
      end

      # Move selection one slot to the left.
      # @return [void]
      def move_left
        move(-1)
      end

      # Move selection one slot to the right.
      # @return [void]
      def move_right
        move(1)
      end
      
      # Move selection one row up.
      # @return [void]
      def move_up
        move(-Constants::GRID_COLS)
      end
      
      # Move selection one row down.
      # @return [void]
      def move_down
        move(Constants::GRID_COLS)
      end
 
      # Switch to the previous category.
      # @return [void]
      def previous_category
        @category_index = (@category_index - 1) % @categories.size
        refresh_category
      end

      # Switch to the next category.
      # @return [void]
      def next_category
        @category_index = (@category_index + 1) % @categories.size
        refresh_category
      end

      # Refresh the UI after a category change.
      # Resets selection, scroll and rebuilds the grid.
      # @return [void]
      def refresh_category
        clear_ingredients
        update_category_text

        @recipes = recipes_for(current_category)

        @recipe_index = 0
        @scroll_row   = 0

        @recipe_slots.each do |slot|
          slot[:sprite]&.dispose
          slot[:sprite] = nil
        end

        create_recipe_grid
        refresh
      end

      # Adjust scroll position to keep selected recipe visible.
      # @return [void]
      def adjust_scroll
        total_rows = (@recipes.size.to_f / Constants::GRID_COLS).ceil
        max_scroll = [total_rows - Constants::GRID_ROWS, 0].max
        row = @recipe_index / Constants::GRID_COLS

        if row < @scroll_row
          @scroll_row = row
        elsif row >= @scroll_row + Constants::GRID_ROWS
          @scroll_row = row - Constants::GRID_ROWS + 1
        end

        @scroll_row = [[@scroll_row, 0].max, max_scroll].min
      end
    end
  end
end
