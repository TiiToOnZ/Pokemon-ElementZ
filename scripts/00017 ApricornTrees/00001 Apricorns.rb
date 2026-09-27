# frozen_string_literal: true

module PFM
  class Apricorns
    attr_accessor :game_state

    def initialize(game_state)
      @game_state = game_state
      @quantities = ApricornTrees::COLORS.to_h { |color| [color, 0] }
    end

    def quantity(color)
      validate_color!(color)
      @quantities.fetch(color, 0)
    end
    alias [] quantity

    def quantities
      @quantities.dup.freeze
    end

    def add(color, amount = 1, source: :event, notify: true)
      validate!(color, amount)
      return true if amount.zero?
      @quantities[color] = quantity(color) + amount
      notify_acquisition(color, amount, source) if notify
      true
    end

    def remove(color, amount = 1)
      validate!(color, amount)
      return false if quantity(color) < amount
      @quantities[color] -= amount
      true
    end

    def notify_acquisition(color, amount, source)
      item = ApricornTrees::TYPES.fetch(color)[:item]
      ApricornTrees.safely_notify { game_state.quests.add_item(item, amount) }
      ApricornTrees::ACQUISITION_HOOKS.each_value do |hook|
        ApricornTrees.safely_notify { hook.call(self, color, amount, source) }
      end
    end

    private

    def validate_color!(color)
      raise ArgumentError, "Unknown Apricorn color: #{color.inspect}" unless ApricornTrees::TYPES.key?(color)
    end

    def validate!(color, amount)
      validate_color!(color)
      raise ArgumentError, 'Quantity must be a non-negative Integer' unless amount.is_a?(Integer) && amount >= 0
    end
  end

  class GameState
    def apricorns
      @apricorns ||= Apricorns.new(self)
      @apricorns.game_state = self
      @apricorns
    end

    on_player_initialize(:apricorns) { @apricorns = Apricorns.new(self) }
    on_expand_global_variables(:apricorns) do
      $apricorns = apricorns
      # Native :bag expansion has already converted pre-.26 inventories.
      @bag.apricorn_import_legacy! if @bag
      ApricornTrees.cancel_session if ApricornTrees.respond_to?(:cancel_session)
      @game_player.leave_apricorn_state if @game_player&.apricorn_state?
    end
  end
end

module ApricornTrees
  # Compatibility for old map rewards and the existing crafting UI. There is
  # only ONE inventory: no Apricorn is inserted into @items or a bag pocket.
  module BagCompatibility
    def item_quantity(item)
      color = ApricornTrees.color_for(item)
      return super unless color && game_state.bag.equal?(self)
      locked ? 0 : game_state.apricorns[color]
    end

    def add_item(item, amount = 1)
      color = ApricornTrees.color_for(item)
      return super unless color && game_state.bag.equal?(self)
      return false if locked
      return remove_item(item, -amount) if amount.is_a?(Integer) && amount.negative?
      game_state.apricorns.add(color, amount, source: :legacy_bag)
    end

    def remove_item(item, amount = 999)
      color = ApricornTrees.color_for(item)
      return super unless color && game_state.bag.equal?(self)
      return false if locked
      return add_item(item, -amount) if amount.is_a?(Integer) && amount.negative?
      # Preserve Bag's remove-up-to semantics; Apricorns#remove itself is strict.
      raise ArgumentError, 'Invalid quantity' unless amount.is_a?(Integer) && amount >= 0
      game_state.apricorns.remove(color, [amount, game_state.apricorns[color]].min)
    end

    # Ruby aliases otherwise keep pointing at the original native methods.
    def store_item(item, amount = 1)
      add_item(item, amount)
    end

    def drop_item(item, amount = 999)
      remove_item(item, amount)
    end

    def apricorn_import_legacy!
      @items.keys.each do |item|
        color = ApricornTrees.color_for(item)
        next unless color
        amount = @items[item]
        game_state.apricorns.add(color, amount, notify: false) if amount.is_a?(Integer) && amount.positive?
        @items.delete(item)
      end
      # Remove stale inventory references, without changing any Studio pocket.
      @orders.each { |order| order&.reject! { |item| ApricornTrees.color_for(item) } }
      @shortcut&.map! { |item| ApricornTrees.color_for(item) ? :__undef__ : item }
    end
  end
end
PFM::Bag.prepend(ApricornTrees::BagCompatibility)
