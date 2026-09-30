# ============================================================
# UI::CraftSystemUI::RecipeDetail
# ------------------------------------------------------------
# Module handling the ingredient detail section of the
# Craft System UI. Manages creation, update, visibility and
# disposal of ingredient rows.
# ============================================================

module UI
  module CraftSystemUI 
    module RecipeDetail
      
      # ==========================================================
      # UI::CraftSystemUI::RecipeDetail::IngredientRow
      # ----------------------------------------------------------
      # Represents a single ingredient row in the detail panel.
      # Handles its graphical components and validity state.
      # ==========================================================
      class IngredientRow
        # @return [Sprite]
        attr_accessor :box
        # @return [ItemSprite]
        attr_accessor :icon
        # @return [Text]
        attr_accessor :name
        # @return [Text]
        attr_accessor :qty
        # @return [Boolean]
        attr_accessor :valid
        
        # Create a new ingredient row.
        # @param parent [Object] parent UI object
        # @param item [Object] ingredient item
        # @param qty [Integer] required quantity
        # @param y [Integer] vertical position
        # @return [void]
        def initialize(parent, item, qty, y)
          @parent = parent
          @valid = parent.ingredient_valid?(item, qty)
          
          @box  = parent.add_sprite(163, y, 'crafting/ing_details')
          @icon = parent.add_sprite(162, y - 1, :NO_INITIAL_IMAGE, type: ItemSprite)
          @name = parent.with_font(20) { parent.add_text(195, y + 3, 77, 24, '', 0, color: 10) }
          @qty  = parent.build_qty_text(268, y + 3, "#{$bag.item_quantity(item)}/#{qty}", @valid)
        end
        
        # Dispose all graphical elements of the row.
        # @return [void]
        def dispose
          [@box, @icon, @name, @qty].each { |e| e&.dispose }
        end
        
        # Hide all row elements.
        # @return [void]
        def hide
          [@box, @icon, @name, @qty].each { |e| e&.visible = false if e }
        end
        
        # Show all row elements.
        # @return [void]
        def show
          [@box, @icon, @name, @qty].each { |e| e&.visible = true if e }
        end
        
        # Update the quantity text and validity state.
        # Rebuilds the text object if validity changed.
        # @param text [String] displayed quantity text
        # @param new_valid [Boolean] new validity state
        # @return [void]
        def update_qty(text, new_valid)
          if @valid != new_valid
            @qty&.dispose
            @qty = @parent.build_qty_text(268, @name.y + 3, text, new_valid)
            @valid = new_valid
          else
            @qty.text = text
          end
        end
      end
      
      # ----------------------------------------------------------
      # Build a quantity text element.
      # @param x [Integer] horizontal position
      # @param y [Integer] vertical position
      # @param text [String] displayed text
      # @param valid [Boolean] validity state
      # @return [Text]
      # ----------------------------------------------------------
      def build_qty_text(x, y, text, valid)
        with_font(20) { add_text(x, y, 38, 24, text, 1, color: valid ? 10 : 12) }
      end
      
      # Clear and dispose all ingredient rows.
      # @return [void]
      def clear_ingredients
        return unless @ingredient_rows
        @ingredient_rows.each(&:dispose)
        @ingredient_rows.clear
      end
      
      # Rebuild ingredient rows from given data.
      # @param ingredients [Array<[Object, Integer]>]
      # @return [void]
      def rebuild_ingredients(ingredients)
        @ingredient_rows&.each(&:dispose)
        
        @ingredient_rows = ingredients.map.with_index do |(item, qty), i|
          y = 73 + i * 33
          IngredientRow.new(self, item, qty, y)
        end
      end
      
      # Refresh ingredient rows using provided recipe data.
      # @param data [Hash] recipe data containing :ingredients
      # @return [void]
      def refresh_ingredients(data)
        ingredients = data[:ingredients].to_a
        rebuild_ingredients(ingredients) if @ingredient_rows.size != ingredients.size
        
        @ingredient_rows.each_with_index do |row, i|
          item, qty = ingredients[i]
          valid = ingredient_valid?(item, qty)
          text  = "#{$bag.item_quantity(item)}/#{qty}"
          
          row.icon.data = item
          row.name.text = data_item(item).exact_name
          
          row.update_qty(text, valid)
        end
      end
    end
  end
end
