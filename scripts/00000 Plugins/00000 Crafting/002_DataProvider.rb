# ============================================================
# UI::CraftSystemUI::DataProvider
# ------------------------------------------------------------
# Provides crafting data access for the UI layer.
# Acts as a bridge between UI and CraftSystem logic.
# ============================================================

module UI
  module CraftSystemUI
    module DataProvider
      
      # Return all crafting categories.
      # @return [Array<Symbol>]
      def categories
        CraftSystem::Recipes.categories.map(&:to_sym)
      end
      
      # Return available recipes for a category.
      # @param category [Symbol]
      # @return [Array<Symbol>]
      def recipes_for(category)
        return CraftSystem.available_recipes if category == :all
        
        CraftSystem.available_recipes.select do |key|
          CraftSystem.recipe(key)[:category] == category
        end
      end
      
      # Retrieve formatted recipe data for UI usage.
      # @param recipe [Symbol]
      # @return [Hash, nil]
      def recipe_data(recipe)
        CraftSystem.data_craft(recipe)
      end
      
      # Check if player has enough quantity of an ingredient.
      # @param item [Symbol]
      # @param qty [Integer]
      # @return [Boolean]
      def ingredient_valid?(item, qty)
        CraftSystem.has_item_quantity?(item, qty)
      end
    end
  end
end
