# frozen_string_literal: true
require_relative 'support'

class V2Tests < AchievementTest
  THRESHOLDS = [5, 15, 30, 50, 75, 105, 140, 180, 225, 275, 330, 390, 455, 525, 600, 680, 765, 855].freeze

  def first_tier
    BA::DEFINITIONS[ID][:tiers].first
  end

  def tier_record(achievement, tier_id)
    BA.state.dig(:tiers, achievement, tier_id)
  end

  def with_zone_pairs(zones)
    BA::ProgressSources.stub(:zone_pairs, ->(_game) { zones }) { yield }
  end

  def reload
    @game = Marshal.load(Marshal.dump(@game))
    activate(@game)
  end

  def receipt
    BA.tier_record(ID, first_tier)
  end

  def with_rewards(rewards)
    definition = BA::DEFINITIONS[ID].merge(tiers: [first_tier.merge(reward: rewards)])
    with_constant(:DEFINITIONS, BA::DEFINITIONS.merge(ID => definition)) { yield }
  end

  def test_exact_thresholds_and_bulk_progress
    assert_equal THRESHOLDS, BA::DEFINITIONS[ID][:tiers].map { |tier| tier[:value] }
    [0, 5, 15, 30, 855, 901].each do |count|
      setup
      native = @game.pokedex.method(:mark_captured).super_method
      count.times { |n| native.call("test_#{n}".to_sym) }
      BA.unlock_category(:researcher)
      expected = THRESHOLDS.select { |n| n <= count }
      assert_equal expected, received
      assert_equal count, BA.progress(ID)
      money, balls = @game.money, @game.bag.item_quantity(:poke_ball)
      3.times { BA.sync_all }
      assert_equal money, @game.money
      assert_equal balls, @game.bag.item_quantity(:poke_ball)
      reload
      BA.sync_all
      assert_equal expected, received
      assert_empty BA::Notifications.queue
    end
  end

  def test_two_items_paid_once_and_single_component_compatible
    capture(15)
    BA.unlock_category(:researcher)
    assert_equal [5, 15], received
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
    assert_equal 1, @game.bag.item_quantity(:exp_share)
    assert_equal 2, @game.bag.item_quantity(:potion)
    assert_equal [:rewarded, :rewarded], receipt[:rewards].map { |entry| entry[:status] }
    assert_equal 3, BA::Notifications.queue.size
    5.times { BA.check(ID) }
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
  end

  def test_partial_bag_full_save_reload_and_complete_banner
    Configs.settings.max_bag_item_count = 99
    @game.bag.add_item(:potion, 98)
    capture(5)
    BA.unlock_category(:researcher)
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
    assert_equal 98, @game.bag.item_quantity(:potion)
    assert_equal :pending, receipt[:status]
    assert_equal [:rewarded, :pending], receipt[:rewards].map { |entry| entry[:status] }
    assert BA.obtained?(ID, first_tier)
    assert_equal [:category], BA::Notifications.queue.map { |event| event[:type] }
    reload
    3.times { BA.sync_all }
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
    assert_empty BA::Notifications.queue
    @game.bag.remove_item(:potion, 1)
    BA.sync_all
    assert_equal 99, @game.bag.item_quantity(:potion)
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
    assert_equal :rewarded, receipt[:status]
    assert_equal [:tier], BA::Notifications.queue.map { |event| event[:type] }
    reload
    BA.sync_all
    assert_equal 99, @game.bag.item_quantity(:potion)
    assert_empty BA::Notifications.queue
  end

  def test_mixed_types_continue_after_blocked_component
    rewards = [{type: :item, id: :potion, quantity: 2}, {type: :money, amount: 37},
               {type: :item, id: :poke_ball, quantity: 5}]
    with_rewards(rewards) do
      @game.bag.locked = true
      capture(5)
      BA.unlock_category(:researcher)
      assert_equal 37, @game.money
      assert_equal [:pending, :rewarded, :pending], receipt[:rewards].map { |e| e[:status] }
      reload
      @game.bag.locked = false
      3.times { BA.sync_all }
      assert_equal 37, @game.money
      assert_equal 2, @game.bag.item_quantity(:potion)
      assert_equal 5, @game.bag.item_quantity(:poke_ball)
    end
  end

  def test_repeated_item_components_use_committed_inventory
    with_rewards([{type: :item, id: :potion, quantity: 2}, {type: :item, id: :potion, quantity: 3}]) do
      Configs.settings.max_bag_item_count = 4
      capture(5)
      BA.unlock_category(:researcher)
      assert_equal 2, @game.bag.item_quantity(:potion)
      assert_equal [:rewarded, :pending], receipt[:rewards].map { |e| e[:status] }
      @game.bag.remove_item(:potion, 1)
      BA.sync_all
      assert_equal 4, @game.bag.item_quantity(:potion)
      assert_equal :rewarded, receipt[:status]
    end
  end

  def test_partial_native_insertion_is_rejected_on_clone_without_live_credit
    bag = @game.bag
    original = bag.method(:clone)
    bag.define_singleton_method(:clone) do
      original.call.tap do |candidate|
        native = candidate.method(:add_item)
        candidate.define_singleton_method(:add_item) { |item, count| native.call(item, count - 1) }
      end
    end
    capture(5)
    BA.unlock_category(:researcher)
    assert_equal 0, bag.item_quantity(:poke_ball)
    assert_equal 0, bag.item_quantity(:potion)
    assert_equal [:pending, :pending], receipt[:rewards].map { |e| e[:status] }
    bag.singleton_class.send(:remove_method, :clone)
    BA.sync_all
    assert_equal 5, bag.item_quantity(:poke_ball)
    assert_equal 2, bag.item_quantity(:potion)
    assert_equal 2, $test_log.size
  end

  def test_invalid_component_does_not_block_other_components
    with_rewards([{type: :item, id: :missing_item, quantity: 1}, {type: :money, amount: 19}]) do
      capture(5)
      BA.unlock_category(:researcher)
      assert_equal 19, @game.money
      assert_equal [:pending, :rewarded], receipt[:rewards].map { |e| e[:status] }
      BA.sync_all
      assert_equal 19, @game.money
    end
  end

  def test_reentrant_callbacks_and_save_between_components
    saved = nil
    @game.quests.define_singleton_method(:add_item) do |*|
      BombanceAchievements.sync_all
      saved ||= Marshal.dump(BombanceAchievements.state)
    end
    capture(5)
    BA.unlock_category(:researcher)
    assert_equal 5, @game.bag.item_quantity(:poke_ball)
    assert_equal 2, @game.bag.item_quantity(:potion)
    data = Marshal.load(saved)
    assert_equal :rewarded, data[:tiers][ID][:species_5][:rewards].first[:status]
    assert_equal :pending, data[:tiers][ID][:species_5][:rewards].last[:status]
    assert_equal 1, BA::Notifications.queue.count { |e| e[:type] == :tier }
  end

  def test_migration_old_paid_hash_and_array_are_final
    [1, 2].each do |version|
      [{type: :money, amount: 9}, [{type: :item, id: :poke_ball, quantity: 1}]].each do |reward|
        setup
        data = {version: version, categories: {researcher: true}, counters: {trainer_battles_won: 4},
                manual: {secret: true}, identity: 'proof', acquisition_baseline: true,
                tiers: {ID => {species_5: {status: :rewarded, reward: reward}}}}
        @game.instance_variable_set(:@bombance_achievements, data)
        migrated = BA.state
        assert_equal 3, migrated[:version]
        assert_equal 'proof', migrated[:identity]
        assert_equal 4, BA.value(:trainer_battles_won)
        assert migrated[:manual][:secret]
        initial = Marshal.dump(migrated)
        5.times { BA.migrate_state(migrated) }
        assert_equal initial, Marshal.dump(migrated)
        BA.sync_all
        assert_equal 0, @game.money
        assert_equal 0, @game.bag.item_quantity(:poke_ball)
        assert_equal 0, @game.bag.item_quantity(:potion)
        assert BA.rewarded?(ID, first_tier)
      end
    end
  end

  def test_old_pending_hash_preserves_original_promise
    @game.instance_variable_set(:@bombance_achievements,
      {version: 2, categories: {researcher: true}, tiers: {ID => {species_5: {
        status: :pending, reward: {type: :item, id: :poke_ball, quantity: 1}}}}})
    reload
    BA.sync_all
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
    assert_equal 0, @game.bag.item_quantity(:potion)
    assert_equal 1, receipt[:rewards].size
    BA.sync_all
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
  end

  def test_old_pending_array_and_partially_migrated_receipt
    @game.instance_variable_set(:@bombance_achievements,
      {version: 2, categories: {researcher: true}, tiers: {ID => {species_5: {
        status: :pending, reward: [{type: :money, amount: 7}, {type: :item, id: :potion, quantity: 3}]}}}})
    BA.sync_all
    assert_equal 7, @game.money
    assert_equal 3, @game.bag.item_quantity(:potion)
    record = receipt
    record[:status] = :pending
    record[:rewards].last[:status] = :pending
    @game.bag.remove_item(:potion, 3)
    BA.state[:version] = 2
    reload
    BA.sync_all
    assert_equal 7, @game.money
    assert_equal 3, @game.bag.item_quantity(:potion)
  end

  def test_paid_lot_overrides_incomplete_component_statuses
    data = {version: 2, tiers: {ID => {species_5: {status: :rewarded,
      rewards: [{status: :pending, reward: {type: :money, amount: 10}}]}}}}
    @game.instance_variable_set(:@bombance_achievements, data)
    assert_equal :rewarded, BA.state[:tiers][ID][:species_5][:rewards].first[:status]
    BA.unlock_category(:researcher)
    assert_equal 0, @game.money
  end

  def test_threshold_history_is_semantic_not_positional
    old_ids = [5, 15, 30, 60, 100, 175, 275, 400, 550, 700, 50, 75]
    records = old_ids.to_h { |n| ["species_#{n}".to_sym, {status: :rewarded, reward: {type: :money, amount: 111}}] }
    records[:species_60] = {status: :pending, reward: {type: :money, amount: 17}}
    @game.instance_variable_set(:@bombance_achievements,
      {version: 2, categories: {researcher: true}, tiers: {ID => records}})
    native = @game.pokedex.method(:mark_captured).super_method
    140.times { |n| native.call("historic_#{n}".to_sym) }
    BA.sync_all
    assert_equal 317, @game.money # species_140's configured reward plus the old pending 60
    assert_equal :rewarded, records[:species_60][:status]
    assert_equal 0, @game.bag.item_quantity(:poke_ball)
    assert_equal [5, 15, 30, 50, 75, 105, 140, 275], received
    assert_equal 18, BA::DEFINITIONS[ID][:tiers].size
    old_ids.each { |n| assert records.key?("species_#{n}".to_sym) }
    assert_equal 2, BA::Notifications.queue.count { |e| e[:type] == :tier }
    reload
    BA.sync_all
    assert_equal 317, @game.money
    assert_empty BA::Notifications.queue
  end

  def test_changed_definition_cannot_augment_or_replace_snapshot
    @game.bag.locked = true
    capture(5)
    BA.unlock_category(:researcher)
    with_rewards([{type: :money, amount: 999_999}]) do
      @game.bag.locked = false
      BA.sync_all
      assert_equal 0, @game.money
      assert_equal 5, @game.bag.item_quantity(:poke_ball)
      assert_equal 2, @game.bag.item_quantity(:potion)
      assert_equal 2, BA.reward_entries(ID, first_tier).size
      reload
      BA.sync_all
      assert_equal 0, @game.money
    end
  end

  def test_missing_keys_future_version_and_missing_promise
    assert_equal 3, BA.migrate_state({})[:version]
    future = {version: 4}
    assert_equal 4, BA.migrate_state(future)[:version]
    data = {version: 2, tiers: {ID => {species_5: {status: :pending}}}}
    @game.instance_variable_set(:@bombance_achievements, data)
    BA.unlock_category(:researcher)
    assert_equal 0, @game.bag.item_quantity(:poke_ball)
    assert_equal :pending, receipt[:status]
  end

  def test_secret_unique_state_and_manual_proof_survive_migration
    secret = {category: :researcher, source: :manual, kind: :unique, title: 'Secret',
      description: 'Texte secret', secret: true, hidden_description: true, hidden_reward: true,
      tiers: [{id: :completed, value: 1, reward: [{type: :money, amount: 3}, {type: :item, id: :potion, quantity: 1}]}]}
    with_constant(:DEFINITIONS, BA::DEFINITIONS.merge(secret_test: secret)) do
      assert_equal '???', BA.achievement_title(:secret_test)
      assert_equal '???', BA.achievement_description(:secret_test)
      assert BA.reward_entries(:secret_test, secret[:tiers].first).all? { |e| e[:hidden] && e[:reward].nil? }
      BA.unlock_achievement(:secret_test)
      assert_equal 0, @game.money
      BA.state[:version] = 2
      reload
      BA.unlock_category(:researcher)
      assert_equal 'Secret', BA.achievement_title(:secret_test)
      assert_equal 'Obtenu', BA.unique_status(:secret_test)
      assert_equal 3, @game.money
      reload
      BA.sync_all
      assert_equal 3, @game.money
    end
  end

  def test_custom_counter_and_real_owned_sources
    pokemon = OpenStruct.new(data: OpenStruct.new(type1: :fire, type2: :__undef__),
      egg?: false, shiny?: false, level: 100, loyalty: 255)
    @game.actors << pokemon
    BA.sync_all
    assert_equal 'Obtenu', BA.unique_status(:best_friends)
    assert_equal 'Obtenu', BA.unique_status(:level_100)
    BA.increment(:trainer_battles_won, 5)
    assert BA.revealed?(:trainer_wins)
    BA.increment(:eggs_hatched)
    assert BA.revealed?(:eggs)
    BA.unlock_category(:researcher)
    BA.increment(:shinies_caught)
    assert BA.revealed?(:shinies)
    money = @game.money
    reload
    BA.sync_all
    assert_equal money, @game.money
  end

  def test_species_forms_zones_and_quests_use_real_sources
    BA.unlock_category(:researcher)
    @game.pokedex.mark_captured(:pikachu, 0)
    @game.pokedex.mark_captured(:pikachu, 1)
    assert_equal 1, BA.progress(ID)
    symbol, form = BA::ProgressSources.form_pairs.first
    @game.pokedex.mark_seen(symbol, form, forced: true)
    assert_operator BA.value(:pokedex_forms), :>=, 1
    assert_operator BA::ProgressSources.zone_total(@game), :>, 0
    zone = BA::ProgressSources.zone_pairs(@game).values.first
    zone.each { |s, f| @game.pokedex.mark_seen(s, f, forced: true) }
    assert_operator BA.value(:completed_zones), :>=, 1
    TestData::QUESTS.values.reject(&:is_primary).first(3).each do |q|
      @game.quests.finished_quests[q.id] = PFM::Quests::Quest.new(q.id)
    end
    assert_equal 3, BA.value(:secondary_quests_completed)
    BA.sync_all
    assert BA.revealed?(:secondary_quests)
    assert_empty $test_log
  end

  def test_categories_successes_tiers_scroll_and_remember_positions
    BA.unlock_category(:researcher)
    scene = open_ui
    press(scene, :A)
    4.times { press(scene, :DOWN) }
    assert_equal [4, 2], [scene.index, scene.offset]
    press(scene, :A)
    press(scene, :B)
    assert_equal [4, 2], [scene.index, scene.offset]
    press(scene, :B)
    press(scene, :DOWN)
    press(scene, :A)
    press(scene, :DOWN)
    press(scene, :A)
    17.times { press(scene, :DOWN) }
    assert_equal [17, 13], [scene.index, scene.offset]
    vp = scene.instance_variable_get(:@list_viewport)
    assert_equal [147, 100], [vp.rect.width, vp.rect.height]
    press(scene, :B)
    press(scene, :A)
    assert_equal [17, 13], [scene.index, scene.offset]
    press(scene, :DOWN)
    assert_equal [0, 0], [scene.index, scene.offset]
    scene.dispose
    cats = BA::CATEGORIES.merge((1..30).to_h { |n| ["cat_#{n}".to_sym, {title: "Catégorie #{n}"}] })
    with_constant(:CATEGORIES, cats) do
      scene = open_ui
      31.times { press(scene, :DOWN) }
      assert_equal [31, 30], [scene.index, scene.offset]
      scene.dispose
    end
  end

  def test_scrollbars_top_middle_bottom_and_huge_lists
    [18, 30, 1000].each do |total|
      top, thumb = BA::Panel.scroll_metrics(100, 0, 5, total)
      middle, = BA::Panel.scroll_metrics(100, (total - 5) / 2, 5, total)
      bottom, = BA::Panel.scroll_metrics(100, total - 5, 5, total)
      assert_equal 0, top
      assert_operator middle, :>, top
      assert_operator middle, :<, bottom
      assert_equal 100, bottom + thumb
      assert_operator thumb, :>=, 8
    end
  end

  def test_native_keyboard_dpad_stick_and_button_mapping
    require File.expand_path('../lib/LiteRGSS.so', File.dirname(RbConfig.ruby))
    path = File.join(NATIVE, '0_Dependencies.rb')
    lines = File.readlines(path, encoding: 'UTF-8')
    found = nil
    visit = lambda do |node|
      next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      if node.type == :MODULE && lines[node.first_lineno - 1].strip == 'module Input'
        found = node
      else
        node.children.each { |child| visit.call(child) }
      end
    end
    visit.call(RubyVM::AbstractSyntaxTree.parse(lines.join))
    scope = Module.new
    scope.module_eval(lines[(found.first_lineno - 1)..(found.last_lineno - 1)].join, path, found.first_lineno)
    input = scope.const_get(:Input)
    BA.unlock_category(:researcher)
    scene = open_ui
    # Execute the native event-to-action mapping. Physical devices and repeat
    # timing are not simulated; the scene receives each resulting action once.
    events = [[:on_key_down, [nil, Sf::Keyboard::Scancode::Down], :DOWN],
              [:on_axis_y, [100], :UP], [:on_axis_joy_y, [100], :DOWN],
              [:on_axis_x, [-100], :LEFT], [:on_axis_x, [100], :RIGHT],
              [:on_joystick_button_pressed, [0, 0], :A],
              [:on_joystick_button_pressed, [0, 1], :B]]
    events.each do |method, args, expected|
      input.instance_variable_set(:@current_state, Hash.new(false))
      input.send(method, *args)
      state = input.instance_variable_get(:@current_state)
      assert_equal [expected], state.select { |_key, active| active }.keys
      Input.stub(:trigger?, ->(key) { state[key] }) do
        Input.stub(:repeat?, ->(key) { state[key] }) { scene.update_inputs }
      end
    end
    assert_equal :categories, scene.screen
    assert_equal 1, scene.index
    scene.dispose
  end

  def test_reward_pages_long_text_bounds_and_disposal
    rewards = Array.new(9) { |i| {type: :money, amount: i + 1} }
    with_rewards(rewards) do
      BA.unlock_category(:researcher)
      scene = open_ui
      press(scene, :DOWN); press(scene, :A); press(scene, :DOWN); press(scene, :A)
      assert_equal 5, scene.reward_pages
      4.times { press(scene, :RIGHT) }
      assert_equal 4, scene.reward_page
      press(scene, :B); press(scene, :A)
      assert_equal 4, scene.reward_page
      press(scene, :RIGHT)
      assert_equal 0, scene.reward_page
      press(scene, :LEFT)
      assert_equal 4, scene.reward_page
      scene.instance_variable_get(:@panel).paragraph(12, 34, 200, 'Trèslongmot' * 100)
      [scene.instance_variable_get(:@panel), scene.instance_variable_get(:@list_panel)].each do |panel|
        panel.stack.grep(Text).each { |t| assert_operator t.text_width(t.text), :<=, t.width }
      end
      scene.dispose
      assert Drawable.objects.drop(@owned_start).all?(&:disposed?)
    end
  end

  def test_popup_pages_pause_duration_sound_and_queue
    rewards = Array.new(5) { |i| {type: :money, amount: i + 1} }
    with_rewards(rewards) do
      capture(5)
      BA.unlock_category(:researcher)
      BA::Notifications.reset
      $scene = map = Scene_Map.new
      sounds = []
      n = BA::Notifications
      Audio.stub(:se_play, ->(*args) { sounds << args }) do
        n.show(map, type: :tier, achievement: ID, tier: :species_5)
        assert_equal 3, n.instance_variable_get(:@pages)
        assert_operator n.instance_variable_get(:@duration), :>=, 7.2
        n.instance_variable_set(:@elapsed, 2.7)
        n.update(map)
        assert_equal 1, n.instance_variable_get(:@page)
        map.dialogue = true
        frozen = n.instance_variable_get(:@elapsed)
        10.times { n.update(map) }
        assert_equal frozen, n.instance_variable_get(:@elapsed)
        refute n.instance_variable_get(:@viewport).visible
        map.dialogue = false
        n.instance_variable_set(:@elapsed, 5.2)
        n.update(map)
        assert_equal 2, n.instance_variable_get(:@page)
        assert_equal 1, sounds.size
        n.instance_variable_set(:@elapsed, 8)
        n.update(map)
        assert_nil n.instance_variable_get(:@panel)
      end
      assert_empty $test_log
    end
  end

  def test_gem_rewards_are_concrete_objects_in_objets_pocket
    expected_gems = %i[normal_gem fire_gem water_gem electric_gem grass_gem ice_gem fighting_gem poison_gem
                       ground_gem flying_gem psychic_gem bug_gem rock_gem ghost_gem dragon_gem dark_gem steel_gem fairy_gem]
    assert_equal expected_gems, BA::RANDOM_GEM_ITEMS
    refute_includes BA::RANDOM_GEM_ITEMS, :joyau_primordial
    (expected_gems + [:joyau_primordial]).each do |item_id|
      item = TestData::ITEMS.fetch(item_id)
      assert_equal item_id, item.db_symbol
      assert_equal 1, item.socket, "#{item_id} must be in the Objets pocket"
    end
    assert_equal :researcher, BA::DEFINITIONS[:shinies][:category]
    BA.unlock_category(:researcher)

    {trainer_wins: 5, secondary_quests: 3, eggs: 1, shinies: 1, researcher_forms: 1}.each do |achievement, progress|
      BA.check(achievement, progress: progress)
      tier = BA::DEFINITIONS.fetch(achievement).fetch(:tiers).first
      record = tier_record(achievement, tier[:id])
      assert_equal :rewarded, record[:status], "#{achievement} receipt status"
      reward = record[:rewards].first.fetch(:reward)
      assert_equal :item, reward[:type], "#{achievement} concrete reward type"
      assert_equal 1, reward[:quantity], "#{achievement} reward quantity"
      assert_equal 1, TestData::ITEMS.fetch(reward[:id]).socket, "#{achievement} pocket socket"
      assert_includes @game.bag.get_order(1), reward[:id], "#{achievement} item order"
      if achievement == :secondary_quests
        assert_equal :joyau_primordial, reward[:id]
      else
        assert_includes expected_gems, reward[:id], "#{achievement} random gem pool"
      end
    end
  end

  def test_pokemon_rewards_use_the_triggering_pokemon_types
    friendship_tier = BA::DEFINITIONS[:best_friends][:tiers].first
    level_tier = BA::DEFINITIONS[:level_100][:tiers].first
    assert_equal [{type: :item, id: :joyau_primordial, quantity: 1},
                  {type: :hint, label: 'Joyau d’un type du Pokémon'}], BA.reward_entries(:best_friends, friendship_tier).map { |e| e[:reward] }

    friends = OpenStruct.new(data: OpenStruct.new(type1: :fire, type2: :flying), egg?: false, loyalty: 255, level: 40)
    levelled = OpenStruct.new(data: OpenStruct.new(type1: :water, type2: :dragon), egg?: false, loyalty: 255, level: 100)
    @game.actors.concat([friends, levelled])
    BA.owned_pokemon_changed(levelled)
    BA.owned_pokemon_changed(friends)

    friend_rewards = tier_record(:best_friends, :completed)[:rewards].map { |entry| entry[:reward] }
    level_rewards = tier_record(:level_100, :completed)[:rewards].map { |entry| entry[:reward] }
    assert_equal :joyau_primordial, friend_rewards.first[:id]
    assert_includes %i[water_gem dragon_gem], friend_rewards.last[:id]
    assert_equal :joyau_primordial, level_rewards.first[:id]
    assert_includes %i[water_gem dragon_gem], level_rewards.last[:id]
    assert_equal %i[fire flying], BA.pokemon_types(friends)
    assert_equal %i[water dragon], BA.pokemon_types(levelled)

    map = Scene_Map.new
    event = BA::Notifications.queue.find { |entry| entry[:type] == :tier && entry[:achievement] == :best_friends }
    BA::Notifications.show(map, event)
    assert_equal 1, BA::Notifications.instance_variable_get(:@pages)
    assert_equal friend_rewards, BA::Notifications.instance_variable_get(:@entries).map { |entry| entry[:reward] }
    assert_equal friend_rewards, BA.reward_entries(:best_friends, friendship_tier).map { |entry| entry[:reward] }
  end

  def test_collection_rewards_and_tier_ids_are_unchanged
    expected = [
      [:species_5, 5, [{type: :item, id: :poke_ball, quantity: 5}, {type: :item, id: :potion, quantity: 2}]],
      [:species_15, 15, {type: :item, id: :exp_share, quantity: 1}],
      [:species_30, 30, [{type: :item, id: :great_ball, quantity: 5}, {type: :item, id: :super_potion, quantity: 2}]],
      [:species_50, 50, {type: :item, id: :tm27, quantity: 1}],
      [:species_75, 75, {type: :money, amount: 300, hidden: true}],
      [:species_105, 105, {type: :item, id: :king_s_rock, quantity: 1}],
      [:species_140, 140, {type: :money, amount: 300, hidden: true}],
      [:species_180, 180, [{type: :item, id: :ultra_ball, quantity: 5}, {type: :item, id: :hyper_potion, quantity: 2}]],
      [:species_225, 225, {type: :money, amount: 100}],
      [:species_275, 275, {type: :item, id: :great_ball, quantity: 3}],
      [:species_330, 330, {type: :money, amount: 100}],
      [:species_390, 390, {type: :money, amount: 100}],
      [:species_455, 455, {type: :money, amount: 100}],
      [:species_525, 525, {type: :money, amount: 100}],
      [:species_600, 600, {type: :money, amount: 100}],
      [:species_680, 680, {type: :money, amount: 100}],
      [:species_765, 765, {type: :money, amount: 100}],
      [:species_855, 855, {type: :money, amount: 100, hidden: true}]
    ]
    actual = BA::DEFINITIONS[:researcher_collection][:tiers].map { |tier| [tier[:id], tier[:value], tier[:reward]] }
    assert_equal expected, actual
  end

  def test_zone_rewards_use_form_types_dominance_and_ties
    zones = {
      dominant: [[:charmander, 0], [:charizard, 0], [:pikachu, 0]],
      tied: [[:pikachu, 0], [:charizard, 0]]
    }
    with_zone_pairs(zones) do
      assert_equal({fire: 2, flying: 1, electric: 1}, BA::ProgressSources.zone_type_counts(@game, :dominant))
      assert_equal({electric: 1, fire: 1, flying: 1}, BA::ProgressSources.zone_type_counts(@game, :tied))
      BA.unlock_category(:researcher)
      BA.check(:researcher_zones, progress: 1, zone: :dominant)
      dominant = tier_record(:researcher_zones, :zones_1)[:rewards].map { |entry| entry[:reward][:id] }
      assert_equal [:joyau_primordial, :fire_gem], dominant
      BA.check(:researcher_zones, progress: 2, zone: :tied)
      tied = tier_record(:researcher_zones, :all_zones)[:rewards].map { |entry| entry[:reward][:id] }
      assert_equal :joyau_primordial, tied.first
      assert_includes %i[electric_gem fire_gem flying_gem], tied.last
    end
  end

  def test_all_zones_reward_snapshots_the_last_zone_completed
    zones = (1..20).to_h { |n| ["area_#{n}".to_sym, [[:pikachu, 0]]] }
    zones[:last_area] = [[:charmander, 0], [:charizard, 0]]
    with_zone_pairs(zones) do
      # These twenty areas are completed before Chercheur is unlocked; their order
      # is retained so the final tier can still use the newly completed area.
      @game.pokedex.mark_seen(:pikachu, 0, forced: true)
      BA.unlock_category(:researcher)
      @game.pokedex.mark_seen(:charmander, 0, forced: true)
      @game.pokedex.mark_seen(:charizard, 0, forced: true)
      record = tier_record(:researcher_zones, :all_zones)
      assert record, "progress=#{BA.progress(:researcher_zones)} completed=#{BA::ProgressSources.completed_zone_symbols(@game).inspect} order=#{BA.state[:zone_completion_order].inspect} errors=#{$test_log.inspect}"
      assert_equal [:joyau_primordial, :fire_gem], record[:rewards].map { |entry| entry[:reward][:id] }
      assert_equal :last_area, BA.state[:zone_completion_order].last
      snapshot = Marshal.load(Marshal.dump(record))
      reload
      assert_equal snapshot, tier_record(:researcher_zones, :all_zones)
      BA.sync_all
      assert_equal snapshot, tier_record(:researcher_zones, :all_zones)
      assert_equal 1, @game.bag.item_quantity(:fire_gem)
    end
  end

  def test_dynamic_receipt_is_a_stable_concrete_snapshot_after_reload
    BA.increment(:trainer_battles_won, 5)
    record = tier_record(:trainer_wins, :wins_5)
    snapshot = Marshal.load(Marshal.dump(record))
    item = snapshot[:rewards].first[:reward][:id]
    assert_equal :item, snapshot[:rewards].first[:reward][:type]
    assert_includes BA::RANDOM_GEM_ITEMS, item
    assert_equal 1, @game.bag.item_quantity(item)

    reload
    with_constant(:DEFINITIONS, BA::DEFINITIONS.merge(trainer_wins: BA::DEFINITIONS[:trainer_wins].merge(
      tiers: [BA::DEFINITIONS[:trainer_wins][:tiers].first.merge(reward: :primordial_gem)]
    ))) do
      3.times { BA.check(:trainer_wins, progress: 5) }
      assert_equal snapshot, tier_record(:trainer_wins, :wins_5)
      assert_equal 1, @game.bag.item_quantity(item)
      assert_equal :joyau_primordial, TestData::ITEMS.fetch(:joyau_primordial).db_symbol
    end
  end
end
