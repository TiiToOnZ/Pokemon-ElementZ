# frozen_string_literal: true

module ApricornTrees
  module Crafting
    def craft(key, amount = 1)
      recipe = ::CraftSystem::Recipes[key]
      return super unless recipe && recipe[:ingredients].keys.any? { |item| ApricornTrees.color_for(item) }
      craft_apricorn_recipe(key, recipe, amount)
    end

    private

    def craft_apricorn_recipe(key, recipe, amount)
      return false unless amount.is_a?(Integer) && amount.positive? && can_craft?(key, amount)
      bag = PFM.game_state.bag
      return false if bag.locked
      stock = PFM.game_state.apricorns
      output = recipe[:result]
      count = recipe[:quantity] * amount
      return false unless count.is_a?(Integer) && count.positive?
      return false if data_item(output).db_symbol == :__undef__
      max = Configs.settings.max_bag_item_count
      return false if max.positive? && bag.item_quantity(output) + count > max

      # Stage on an isolated inventory. Native Bag#add_item deliberately skips
      # quest hooks on a bag that isn't game_state.bag. Failed output insertion
      # (exception OR silent no-op) leaves the real inventory untouched.
      candidate = bag.clone
      candidate.instance_variable_set(:@items, bag.instance_variable_get(:@items).dup)
      candidate.instance_variable_set(:@orders, bag.instance_variable_get(:@orders).map { |order| order&.dup })
      candidate.instance_variable_set(:@shortcut, bag.shortcuts.dup)
      costs = {}
      recipe[:ingredients].each do |item, quantity|
        return false unless quantity.is_a?(Integer) && quantity.positive?
        quantity *= amount
        if (color = ApricornTrees.color_for(item))
          costs[color] = costs.fetch(color, 0) + quantity
        else
          before = candidate.item_quantity(item)
          return false if before < quantity
          candidate.remove_item(item, quantity)
          return false unless candidate.item_quantity(item) == before - quantity
        end
      end
      return false unless costs.all? { |color, quantity| stock[color] >= quantity }
      before = candidate.item_quantity(output)
      candidate.add_item(output, count)
      return false unless candidate.item_quantity(output) == before + count

      # Synchronous commit; no callback or yield until both inventories agree.
      costs.each { |color, quantity| stock.remove(color, quantity) }
      %i[@items @orders @shortcut].each do |ivar|
        bag.instance_variable_set(ivar, candidate.instance_variable_get(ivar))
      end
      ApricornTrees.safely_notify { PFM.game_state.quests.add_item(output, count) }
      true
    rescue StandardError => error
      log_error("Apricorn crafting failed: #{error.class}: #{error.message}")
      false
    end
  end
end

if defined?(CraftSystem::Recipes)
  CraftSystem.singleton_class.prepend(ApricornTrees::Crafting)
end
