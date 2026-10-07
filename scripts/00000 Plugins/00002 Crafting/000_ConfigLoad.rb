# ============================================================
# Configs::Project::Recipes
# ------------------------------------------------------------
# Crafting configuration container.
# Stores categories and raw recipe data loaded from JSON.
# ============================================================

module Configs
  KEY_TRANSLATIONS[:categories] = :categories
  KEY_TRANSLATIONS[:data] = :data
  
  module Project
    class Recipes
      
      # List of crafting categories.
      # @return [Array<Hash>]
      attr_accessor :categories
      
      # Raw crafting recipes data.
      # @return [Hash{Symbol => Hash}]
      attr_accessor :data
    end
  end
  
  # Register crafting configuration file.
  register(:recipes, 'crafting_config', :json, false, Project::Recipes)
end
