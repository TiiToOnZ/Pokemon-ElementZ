# frozen_string_literal: true

module PFM
  class GameState
    def bombance_achievements
      data = (@bombance_achievements ||= {})
      %i[categories counters tiers manual].each { |key| data[key] ||= {} }
      data[:version] = 2
      data
    end
  end
end

module BombanceAchievements
  # Handlers prepare a transaction without changing live inventory. commit must not
  # yield, save, call events or callbacks. after runs only once the receipt is committed.
  REWARD_HANDLERS = {}
  REWARD_LABELS = {}

  class << self
    def state
      PFM.game_state.bombance_achievements
    end

    def safely
      yield
    rescue StandardError => error
      log_error("BombanceAchievements: #{error.class}: #{error.message}")
      nil
    end

    def reset_session
      @checking = {}
      @map_synced_state = nil
      ProgressSources.reset
      Notifications.reset if defined?(Notifications)
    end

    # Called on map creation, once per activated save (never during save previews).
    def on_map_ready
      return if @map_synced_state.equal?(PFM.game_state)
      sync_all
      @map_synced_state = PFM.game_state
    end

    def category_unlocked?(id)
      category = CATEGORIES.fetch(id)
      !!(category[:unlocked] || state[:categories][id])
    end

    def unlock_category(id, notify: true)
      CATEGORIES.fetch(id)
      return false if category_unlocked?(id)
      state[:categories][id] = true
      enqueue(type: :category, category: id) if notify
      sync_category(id)
      true
    end

    def category_title(id)
      category = CATEGORIES.fetch(id)
      return '???' if category[:hidden_until_unlocked] && !category_unlocked?(id)
      category[:title]
    end

    def visible_categories
      CATEGORIES.keys.reject do |id|
        CATEGORIES[id][:invisible_until_unlocked] && !category_unlocked?(id)
      end
    end

    def achievements_in(category, visible: false)
      DEFINITIONS.keys.select do |id|
        definition = DEFINITIONS[id]
        definition[:category] == category &&
          (!visible || !definition[:invisible_until_obtained] || revealed?(id))
      end
    end

    def unique?(id)
      DEFINITIONS.fetch(id)[:kind] == :unique
    end

    def revealed?(id)
      DEFINITIONS.fetch(id)[:tiers].any? { |tier| obtained?(id, tier) }
    end

    def achievement_title(id)
      definition = DEFINITIONS.fetch(id)
      definition[:secret] && !revealed?(id) ? '???' : definition[:title]
    end

    def achievement_description(id)
      definition = DEFINITIONS.fetch(id)
      definition[:hidden_description] && !revealed?(id) ? '???' : definition[:description]
    end

    def unique_status(id)
      revealed?(id) ? 'Obtenu' : 'Non obtenu'
    end

    def tier_value(tier)
      target = tier.fetch(:value)
      target.respond_to?(:call) ? target.call(PFM.game_state) : target
    end

    def tier_label(id, tier)
      return unique_status(id) if unique?(id)
      return '???' if DEFINITIONS[id][:secret] && !revealed?(id)
      tier[:label] || "#{tier_value(tier)} #{DEFINITIONS[id][:unit]}"
    end

    # Manual-only achievements use source: :manual and usually kind: :unique.
    # A locked category can retain this proof; its reward waits for category unlock.
    def unlock_achievement(id)
      definition = DEFINITIONS.fetch(id)
      raise ArgumentError, 'Manual unlock requires source: :manual' unless definition[:source] == :manual
      fresh = !state[:manual][id]
      state[:manual][id] = true
      check(id)
      fresh
    end

    def value(source)
      reader = SOURCES[source]
      reader ? reader.call(PFM.game_state) : state[:counters].fetch(source, 0)
    end

    def set(counter, amount)
      raise ArgumentError, 'Computed sources are read-only' if SOURCES.key?(counter)
      raise ArgumentError, 'Counter must be a Symbol' unless counter.is_a?(Symbol)
      raise ArgumentError, 'Counter must be a non-negative Integer' unless amount.is_a?(Integer) && amount >= 0
      state[:counters][counter] = amount
      source_changed(counter)
      amount
    end

    def increment(counter, amount = 1)
      raise ArgumentError, 'Increment must be a non-negative Integer' unless amount.is_a?(Integer) && amount >= 0
      set(counter, value(counter) + amount)
    end

    def source_changed(source)
      DEFINITIONS.each { |id, definition| check(id) if definition[:source] == source }
    end

    def tier_record(id, tier)
      state[:tiers].dig(id, tier[:id])
    end

    def obtained?(id, tier)
      !tier_record(id, tier).nil?
    end

    def rewarded?(id, tier)
      tier_record(id, tier)&.fetch(:status) == :rewarded
    end

    def progress(id)
      definition = DEFINITIONS.fetch(id)
      return 0 unless category_unlocked?(definition[:category])
      return state[:manual][id] ? 1 : 0 if definition[:source] == :manual
      value(definition[:source])
    end

    def next_tier(id)
      DEFINITIONS.fetch(id)[:tiers].find { |tier| !obtained?(id, tier) }
    end

    def totals(category = nil)
      ids = category ? [category] : CATEGORIES.keys.select { |id| category_unlocked?(id) }
      done = total = 0
      ids.each do |cat|
        next unless category_unlocked?(cat)
        achievements_in(cat).each do |id|
          next if DEFINITIONS[id][:exclude_until_obtained] && !revealed?(id)
          DEFINITIONS[id][:tiers].each { |tier| total += 1; done += 1 if obtained?(id, tier) }
        end
      end
      [done, total]
    end

    def percentage(category = nil)
      done, total = totals(category)
      total.zero? ? 0 : done * 100 / total
    end

    def check(id)
      definition = DEFINITIONS.fetch(id)
      return false unless category_unlocked?(definition[:category])
      @checking ||= {}
      return false if @checking[id]
      @checking[id] = true
      begin
        current = progress(id)
        definition[:tiers].each do |tier|
          next if rewarded?(id, tier)
          target = tier_value(tier)
          next unless obtained?(id, tier) || (target.positive? && current >= target)
          records = (state[:tiers][id] ||= {})
          # Pending is business state, not a request to show a banner. Snapshot the
          # promised reward so a later config edit cannot change an unpaid reward.
          records[tier[:id]] ||= {status: :pending, reward: tier[:reward].dup}
          safely { deliver(id, tier, records.fetch(tier[:id])) }
        end
      ensure
        @checking.delete(id)
      end
      true
    end

    def sync_category(category)
      CATEGORIES.fetch(category)
      return unless category_unlocked?(category)
      achievements_in(category).each { |id| check(id) }
    end

    def reconcile_categories(notify: true)
      quests = PFM.game_state.quests
      CATEGORY_UNLOCKS.each do |category, condition|
        next if category_unlocked?(category)
        known = condition.fetch(:quest_ids).any? do |id|
          quests.active_quests.key?(id) || quests.finished_quests.key?(id)
        end
        unlock_category(category, notify: notify) if known
      end
    end

    def quest_started(id)
      CATEGORY_UNLOCKS.each do |category, condition|
        unlock_category(category) if condition.fetch(:quest_ids).include?(id)
      end
    end

    def sync_all
      baseline_acquisitions
      reconcile_categories
      CATEGORIES.each_key { |category| sync_category(category) }
      retry_retired_rewards
    end

    # Keep V1 receipts for removed tiers (notably species_50/species_75).
    # They neither count in percentages nor issue stale notifications.
    def retry_retired_rewards
      return if @retrying_retired
      @retrying_retired = true
      begin
        state[:tiers].each do |id, records|
          records.each do |tier_id, record|
            next if record[:status] == :rewarded
            next if DEFINITIONS[id]&.fetch(:tiers)&.any? { |tier| tier[:id] == tier_id }
            safely { deliver(id, nil, record) }
          end
        end
      ensure
        @retrying_retired = false
      end
    end

    def register_reward(type, label:, &prepare)
      REWARD_HANDLERS[type] = prepare
      REWARD_LABELS[type] = label
    end

    def reward_text(id, tier)
      reward = tier_record(id, tier)&.fetch(:reward) || tier[:reward]
      hidden = reward[:hidden] || DEFINITIONS[id][:hidden_reward]
      return '???' if hidden && !obtained?(id, tier)
      REWARD_LABELS.fetch(reward[:type]).call(reward)
    end

    def enqueue(event)
      Notifications.enqueue(event) if defined?(Notifications)
    end

    private

    def deliver(id, tier, record)
      transaction = REWARD_HANDLERS.fetch(record[:reward][:type]).call(PFM.game_state, record[:reward])
      return unless transaction # e.g. locked or full bag: retry on the next sync
      transaction.fetch(:commit).call
      record[:status] = :rewarded
      # No UI, event callback, yield or save between inventory commit and receipt.
      safely { transaction[:after]&.call }
      enqueue(type: :tier, achievement: id, tier: tier[:id]) if tier
    end
  end

  register_reward(:money, label: ->(reward) { "#{reward.fetch(:amount)} $" }) do |game, reward|
    amount = reward.fetch(:amount)
    raise ArgumentError, 'Invalid money reward' unless amount.is_a?(Integer) && amount.positive?
    {commit: -> { game.add_money(amount) }}
  end

  register_reward(:item, label: ->(reward) { "#{reward.fetch(:quantity, 1)} × #{data_item(reward.fetch(:id)).name}" }) do |game, reward|
    item, count = reward.fetch(:id), reward.fetch(:quantity, 1)
    raise ArgumentError, 'Invalid item reward' if data_item(item).db_symbol == :__undef__
    raise ArgumentError, 'Invalid quantity' unless count.is_a?(Integer) && count.positive?
    # Apricorns are a separate inventory. They require their own future handler.
    raise ArgumentError, 'Use a material handler for apricorns' if defined?(ApricornTrees) && ApricornTrees.color_for(item)
    bag = game.bag
    next if bag.locked
    max = Configs.settings.max_bag_item_count
    next if max.positive? && bag.item_quantity(item) + count > max
    candidate = bag.clone
    candidate.instance_variable_set(:@items, bag.instance_variable_get(:@items).dup)
    candidate.instance_variable_set(:@orders, bag.instance_variable_get(:@orders).map { |order| order&.dup })
    candidate.instance_variable_set(:@shortcut, bag.shortcuts.dup)
    before = candidate.item_quantity(item)
    candidate.add_item(item, count)
    raise 'Item insertion failed' unless candidate.item_quantity(item) == before + count
    {
      commit: lambda {
        %i[@items @orders @shortcut].each do |ivar|
          bag.instance_variable_set(ivar, candidate.instance_variable_get(ivar))
        end
      },
      after: -> { game.quests.add_item(item, count) }
    }
  end
end
