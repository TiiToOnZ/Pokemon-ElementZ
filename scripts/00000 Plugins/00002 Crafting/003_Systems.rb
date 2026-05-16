# ============================================================
# CraftSystem
# ------------------------------------------------------------
# Core crafting system manager.
# Responsible for:
#   - Unlock logic
#   - Condition evaluation
#   - State synchronization
#   - Craft execution
#   - Inventory interaction
#   - UI data formatting
# ============================================================

module CraftSystem
  module_function

  # Return crafting state hash.
  # @return [Hash{Symbol => Boolean}]
  def state
    $crafting_data ||= {}
    sync_state!
    $crafting_data
  end


  # Retrieve recipe definition.
  # @param key [Symbol]
  # @return [Hash, nil]
  def recipe(key)
    Recipes[key]
  end

  # Return all recipe keys.
  # @return [Array<Symbol>]
  def all_recipes
    Recipes.keys
  end

  # Manually unlock a recipe.
  # @param key [Symbol]
  # @return [void]
  def unlock(key)
    key = key.to_sym
    sync_state!
    state[key] = true if Recipes[key]
    refresh_unlocks!
  end

  # Manually lock a recipe.
  # @param key [Symbol]
  # @return [void]
  def lock(key)
    key = key.to_sym
    sync_state!
    state[key] = false if Recipes[key]
    refresh_unlocks!
  end

  # Check if recipe is unlocked.
  # @param key [Symbol]
  # @return [Boolean]
  def unlocked?(key)
    key = key.to_sym
    recipe = Recipes[key]
    return false unless recipe

    cond = recipe[:unlock_condition]
    return true unless cond
    return state[key] == true if cond[:type] == :manual

    condition_met?(cond)
  end

  # Evaluate a condition structure.
  # @param condition [Hash, Array]
  # @return [Boolean]
  def condition_met?(condition)
    return true unless condition

    if condition.is_a?(Array)
      condition.all? { |c| condition_met?(c) }
    elsif condition.is_a?(Hash) && condition[:operator]
      evaluate_operator_conditions(condition)
    else
      evaluate_single_condition(condition)
    end
  end

  # Evaluate a single condition.
  # @param condition [Hash]
  # @return [Boolean]
  def evaluate_single_condition(condition)
    case condition[:type]
    when :switch
      $game_switches[condition[:id]]
    when :variable
      $game_variables[condition[:id]] >= condition.fetch(:value, 1)
    when :quest
      $quest && $quests.finished?(condition[:id])
    when :recipe
      key = condition[:key].to_sym
      state.key?(key) && unlocked?(key)
    when :item
      has_item_quantity?(condition[:item], condition.fetch(:quantity, 1))
    when :manual
      condition.fetch(:value, false)
    else
      false
    end
  end

  # Evaluate operator-based conditions (:and, :or, :not).
  # @param condition [Hash]
  # @return [Boolean]
  def evaluate_operator_conditions(condition)
    op = condition[:operator]
    conds = condition[:conditions] || []

    case op
    when :and, :all
      conds.all? { |c| condition_met?(c) }
    when :or, :any
      conds.any? { |c| condition_met?(c) }
    when :not, :none
      conds.none? { |c| condition_met?(c) }
    else
      false
    end
  end

  # Synchronize crafting state with current recipes.
  # @return [void]
  def sync_state!
    return if @syncing_state
    @syncing_state = true

    $crafting_data ||= {}
    current_keys = Recipes.keys.map(&:to_sym)

    $crafting_data.keys.each do |key|
      unless current_keys.include?(key)
        $crafting_data.delete(key)
        invalidate_dependent_recipes!(key)
      end
    end

    current_keys.each do |key|
      next if $crafting_data.key?(key)
      recipe = Recipes[key]
      cond   = recipe[:unlock_condition]

      if cond && cond[:type] == :manual
        $crafting_data[key] = cond.fetch(:value, false)
      else
        $crafting_data[key] = false
      end
    end

    refresh_unlocks!(skip_sync: true)
    @syncing_state = false
  end

  # Invalidate recipes depending on a deleted recipe.
  # @param deleted_key [Symbol]
  # @return [void]
  def invalidate_dependent_recipes!(deleted_key)
    Recipes.keys.each do |key|
      next unless state.key?(key)
      cond = Recipes[key][:unlock_condition] rescue nil
      next unless cond

      if depends_on_recipe?(cond, deleted_key)
        state[key] = false
        invalidate_dependent_recipes!(key)
      end
    end
  end

  # Check if condition depends on a recipe.
  # @param condition [Hash, Array]
  # @param target_key [Symbol]
  # @return [Boolean]
  def depends_on_recipe?(condition, target_key)
    return false unless condition
    if condition.is_a?(Array)
      condition.any? { |c| depends_on_recipe?(c, target_key) }
    elsif condition.is_a?(Hash) && condition[:operator]
      condition[:conditions].any? { |c| depends_on_recipe?(c, target_key) }
    else
      condition[:type] == :recipe && condition[:key].to_sym == target_key
    end
  end

  # Refresh unlock states recursively.
  # @param skip_sync [Boolean]
  # @return [void]
  def refresh_unlocks!(skip_sync: false)
    return if @refreshing
    @refreshing = true
    refresh_needed = !skip_sync

    while refresh_needed
      refresh_needed = false

      Recipes.keys.each do |key|
        recipe = Recipes[key]
        cond   = recipe[:unlock_condition]
        next unless cond
        next if cond[:type] == :manual

        met = condition_met?(cond)
        if state[key] != met
          state[key] = met
          refresh_needed = true
        end
      end
    end

    @refreshing = false
  end

  # Return unlocked recipes.
  # @return [Array<Symbol>]
  def available_recipes
    Recipes.keys.select { |key| unlocked?(key) }
  end

  # Return locked recipes.
  # @return [Array<Symbol>]
  def locked_recipes
    Recipes.keys.reject { |key| unlocked?(key) }
  end

  # Return unlocked recipes for a category.
  # @param category [Symbol]
  # @return [Array<Symbol>]
  def recipes_by_category(category)
    Recipes.keys.select do |key|
      r = Recipes[key]
      r[:category] == category.to_sym && unlocked?(key)
    end
  end

  # Check if player has enough quantity of an item.
  # @param item [Symbol]
  # @param quantity [Integer]
  # @return [Boolean]
  def has_item_quantity?(item, quantity)
    return false if quantity <= 0
    $bag.item_quantity(item) >= quantity
  end

  # Return maximum craftable amount.
  # @param key [Symbol]
  # @return [Integer]
  def max_craft(key)
    recipe = Recipes[key]
    return 0 unless recipe && unlocked?(key)

    recipe[:ingredients].map do |item, qty|
      $bag.item_quantity(item) / qty
    end.min || 0
  end

  # Check if crafting is possible.
  # @param key [Symbol]
  # @param amount [Integer]
  # @return [Boolean]
  def can_craft?(key, amount = 1)
    max_craft(key) >= amount
  end

  # Craft a recipe.
  # @param key [Symbol]
  # @param amount [Integer]
  # @return [Boolean]
  def craft(key, amount = 1)
    return false unless can_craft?(key, amount)

    recipe = Recipes[key]

    recipe[:ingredients].each do |item, qty|
      $bag.remove_item(item, qty * amount)
    end

    $bag.add_item(recipe[:result], recipe[:quantity] * amount)
    true
  end

  # Craft maximum possible amount.
  # @param key [Symbol]
  # @return [Boolean]
  def craft_all(key)
    amount = max_craft(key)
    return false if amount <= 0
    craft(key, amount)
  end

  # Return formatted recipe data for UI usage.
  # @param key [Symbol]
  # @return [Hash, nil]
  def data_craft(key)
    recipe = Recipes[key]
    return nil unless recipe

    {
      ingredients: recipe[:ingredients],
      result: recipe[:result],
      quantity: recipe[:quantity],
      unlocked: unlocked?(key),
      max_craft: max_craft(key),
      category: recipe[:category]
    }
  end
end
