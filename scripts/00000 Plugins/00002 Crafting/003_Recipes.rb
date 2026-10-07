# ============================================================
# CraftSystem::Recipes
# ------------------------------------------------------------
# Handles recipe configuration access and normalization.
# Responsible for:
#   - Loading recipe data
#   - Symbol normalization
#   - Unlock condition normalization
#   - Category helpers
# ============================================================

module CraftSystem
  module Recipes
    module_function
    
    # Return normalized recipe data.
    # @return [Hash{Symbol => Hash}]
    def data
      @data ||= normalize(Configs.recipes.data)
    end
    
    # Retrieve a recipe by key.
    # @param key [Symbol, String]
    # @return [Hash, nil]
    def [](key)
      return false if key.nil?
      data[key.to_sym]
    end
    
    # Return all recipe keys.
    # @return [Array<Symbol>]
    def keys
      data.keys
    end
    
    # Return all available categories.
    # @return [Array<Symbol>]
    def categories
      @categories ||= Configs.recipes.categories.map { |h| h.keys.first.to_sym }
    end
    
    # Return localized category name.
    # @param cat [Symbol]
    # @return [String]
    def category_name(cat)
      cat_data = Configs.recipes.categories.find { |h| h.keys.first.to_sym == cat.to_sym }
      return cat.to_s.upcase unless cat_data
      
      text_id = cat_data.values.first
      ext_text(140000, text_id)
    end
    
    # Normalize raw recipe hash.
    # @param raw [Hash]
    # @return [Hash{Symbol => Hash}]
    def normalize(raw)
      raw.transform_keys(&:to_sym).transform_values do |recipe|
        normalize_recipe(recipe)
      end
    end
    private :normalize
    
    # Normalize a single recipe entry.
    # @param recipe [Hash]
    # @return [Hash]
    def normalize_recipe(recipe)
      recipe[:ingredients]&.transform_keys!(&:to_sym)
      
      if (cond = recipe[:unlock_condition])
        recipe[:unlock_condition] = normalize_condition(cond)
      end
      
      recipe[:result]   = recipe[:result].to_sym
      recipe[:category] = recipe[:category].to_sym
      
      recipe
    end
    private :normalize_recipe
    
    # Normalize unlock condition structure.
    # Supports nested operator conditions.
    # @param condition [Hash]
    # @return [Hash]
    def normalize_condition(condition)
      if condition[:operator] || condition['operator']
        {
        operator: (condition[:operator] || condition['operator']).to_sym,
        conditions: (condition[:conditions] || condition['conditions']).map do |cond|
          normalize_condition(cond)
        end
      }
    else
      normalized = {
      type: (condition[:type] || condition['type']).to_sym
    }
    
    normalized[:id]       = condition[:id] || condition['id'] if condition[:id] || condition['id']
    normalized[:value]    = condition[:value] || condition['value'] if condition[:value] || condition['value']
    normalized[:key]      = (condition[:key] || condition['key']).to_sym if condition[:key] || condition['key']
    normalized[:item]     = (condition[:item] || condition['item']).to_sym if condition[:item] || condition['item']
    normalized[:quantity] = condition[:quantity] || condition['quantity'] if condition[:quantity] || condition['quantity']
    normalized[:count]    = condition[:count] || condition['count'] if condition[:count] || condition['count']
    
    normalized
  end
end
private :normalize_condition
end
end
