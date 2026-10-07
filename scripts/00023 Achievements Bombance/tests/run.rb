# frozen_string_literal: true
require_relative 'support'
require_relative 'legacy_content'

class EngineTests < AchievementTest
  # Preserve every original regression scenario using its original six-tier
  # content fixture. Production content has its own A-W suite in finalization.rb.
  def setup
    @production_definitions ||= BA::DEFINITIONS
    @production_sources ||= BA::SOURCES
    BA.send(:remove_const, :DEFINITIONS)
    BA.const_set(:DEFINITIONS, LegacyAchievementContent::DEFINITIONS)
    BA.send(:remove_const, :SOURCES)
    BA.const_set(:SOURCES, LegacyAchievementContent::SOURCES)
    super
  end

  def teardown
    super
    BA.send(:remove_const, :DEFINITIONS)
    BA.const_set(:DEFINITIONS, @production_definitions)
    BA.send(:remove_const, :SOURCES)
    BA.const_set(:SOURCES, @production_sources)
  end
  def test_a_new_game_and_menu
    assert BA.category_unlocked?(:general)
    refute BA.category_unlocked?(:researcher)
    assert_equal [0, 0], BA.totals
    menu = GamePlay::Menu.new
    indexes = menu.instance_variable_get(:@image_indexes)
    assert_includes indexes, GamePlay::Menu::ACTION_LIST.index(:open_bombance_achievements)
    scene = open_ui
    assert_equal :categories, scene.screen
    press(scene, :A)
    assert_empty scene.entries
    assert scene.instance_variable_get(:@panel).stack.grep(Text).any? { |t| t.text.include?('Aucun succès') }
    scene.dispose
    menu.dispose
  end

  def test_b_legacy_save_lazy_getter
    @game.remove_instance_variable(:@bombance_achievements)
    loaded = Marshal.load(Marshal.dump(@game))
    refute loaded.instance_variable_defined?(:@bombance_achievements)
    activate(loaded)
    assert_equal({version: 2, categories: {}, counters: {}, tiers: {}, manual: {}, acquisition_baseline: true}, loaded.bombance_achievements)
    BA.on_map_ready
    assert_empty received
  end

  def test_c_unlock_with_zero
    BA.unlock_category(:researcher)
    assert_equal 0, BA.progress(ID)
    assert_equal 5, BA.next_tier(ID)[:value]
    assert_empty received
    assert_equal 1, BA::Notifications.queue.size
  end

  def test_d_retroactive_twelve
    capture(12)
    BA.unlock_category(:researcher)
    assert_equal [5], received
    assert_equal [12, 15], [BA.progress(ID), BA.next_tier(ID)[:value]]
    assert_equal 100, @game.money
    assert_equal 0, @game.bag.item_quantity(:poke_ball)
  end

  def test_e_retroactive_twenty_three
    capture(23)
    BA.unlock_category(:researcher)
    assert_equal [5, 15], received
    assert_equal [23, 30], [BA.progress(ID), BA.next_tier(ID)[:value]]
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
    assert_equal [:category, :tier, :tier], BA::Notifications.queue.map { |event| event[:type] }
  end

  def test_f_twenty_nine_to_thirty
    capture(29)
    BA.unlock_category(:researcher)
    BA::Notifications.reset
    @game.pokedex.mark_captured(:new_species)
    assert_equal [5, 15, 30], received
    assert_equal 300, @game.money
    assert_equal 1, BA::Notifications.queue.size
    5.times { BA.check(ID) }
    assert_equal 300, @game.money
    assert_equal 1, BA::Notifications.queue.size
  end

  def test_g_four_to_thirty_one_single_sync
    capture(4)
    BA.unlock_category(:researcher)
    BA::Notifications.reset
    # Simulate a bulk import using the real native implementation, followed by one sync.
    native = @game.pokedex.method(:mark_captured).super_method
    (4...31).each { |i| native.call("species_#{i}".to_sym) }
    BA.check(ID)
    assert_equal [5, 15, 30], received
    assert_equal 300, @game.money
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
    assert_equal 3, BA::Notifications.queue.size
  end

  def test_h_save_load_keeps_receipts_and_inventory
    capture(100)
    BA.unlock_category(:researcher)
    @game = Marshal.load(Marshal.dump(@game))
    activate(@game)
    BA.sync_all
    assert_equal [5, 15, 30, 50, 75, 100], received
    assert_equal 600, @game.money
    assert_equal 6, @game.bag.item_quantity(:poke_ball)
    assert_equal 100, BA.percentage
  end

  def test_i_one_hundred_menu_openings
    capture(31)
    BA.unlock_category(:researcher)
    initial = Marshal.dump(@game)
    100.times do
      scene = open_ui
      scene.dispose
    end
    assert_equal initial, Marshal.dump(@game)
    assert Drawable.objects.drop(@owned_start).all?(&:disposed?)
  end

  def test_j_locked_category_is_not_exploitable
    capture(100)
    BA.check(ID)
    BA.sync_category(:researcher)
    assert_empty received
    assert_equal 0, @game.money
    assert_equal 0, BA.progress(ID)
    scene = open_ui
    press(scene, :DOWN)
    press(scene, :A)
    assert_equal :categories, scene.screen
    scene.dispose
  end

  def test_k_hidden_reward
    tier = BA::DEFINITIONS[ID][:tiers][4]
    assert_equal '???', BA.reward_text(ID, tier)
    capture(75)
    BA.unlock_category(:researcher)
    assert_equal '300 $', BA.reward_text(ID, tier)
  end

  def test_l_navigation_scrolling_and_disposal
    BA.unlock_category(:researcher)
    scene = open_ui
    press(scene, :DOWN)
    press(scene, :A)
    assert_equal :category, scene.screen
    press(scene, :A)
    assert_equal :detail, scene.screen
    7.times { press(scene, :DOWN) }
    assert_equal 1, scene.index
    press(scene, :B)
    assert_equal :category, scene.screen
    press(scene, :B)
    assert_equal :categories, scene.screen
    press(scene, :B)
    refute scene.running
    scene.dispose
    scene.dispose
    assert Drawable.objects.drop(@owned_start).all?(&:disposed?)

    many = BA::DEFINITIONS.merge((1..8).to_h { |i| ["test_#{i}".to_sym, BA::DEFINITIONS[ID]] })
    with_constant(:DEFINITIONS, many) do
      scene = open_ui
      press(scene, :DOWN)
      press(scene, :A)
      7.times { press(scene, :DOWN) }
      assert_equal 7, scene.index
      assert_equal 5, scene.offset
      press(scene, :A)
      press(scene, :B)
      assert_equal 7, scene.index
      scene.dispose
    end
  end

  def test_m_existing_menu_and_quest_start_preserved
    @game.bag.add_item(:journal)
    $game_switches[110] = true
    menu = GamePlay::Menu.new
    actions = menu.instance_variable_get(:@image_indexes).map { |i| GamePlay::Menu::ACTION_LIST[i] }
    assert_equal [:open_party, :open_bag, :open_elementz_quests, :open_bombance_achievements,
                  :open_tcard, :open_option, :open_save, :open_quit], actions
    menu.send(:open_elementz_quests)
    assert GamePlay.quest_opened
    menu.send(:open_bombance_achievements)
    assert_equal GamePlay::BombanceAchievementsScene, menu.instance_variable_get(:@called_scene)
    assert_equal 'Quêtes', ElementZ::QuestJournal::MenuButton.allocate.send(:text)
    assert @game.quests.start(49)
    assert @game.quests.active_quests.key?(49)
    assert BA.category_unlocked?(:researcher)
    refute @game.quests.start(49)
    menu.dispose
  end

  def test_n_notifications_are_not_serialized
    capture(5)
    BA.unlock_category(:researcher)
    assert_equal 2, BA::Notifications.queue.size
    bytes = Marshal.dump(@game)
    refute_includes bytes, 'Notifications'
    refute_includes @game.bombance_achievements.keys, :notifications
    @game = Marshal.load(bytes)
    activate(@game)
    BA.on_map_ready
    assert_empty BA::Notifications.queue
    assert_equal [5], received
    assert_equal 100, @game.money
  end

  def test_o_idempotent_unlock
    capture(23)
    assert BA.unlock_category(:researcher)
    100.times { refute BA.unlock_category(:researcher) }
    assert_equal 3, BA::Notifications.queue.size
    assert_equal [5, 15], received
    assert_equal 100, @game.money
  end

  def test_p_duplicate_and_form_do_not_increment
    BA.unlock_category(:researcher)
    capture(4)
    2.times { @game.pokedex.mark_captured(:species_0) }
    @game.pokedex.mark_captured(:species_0, 2)
    assert_equal 4, @game.pokedex.creature_caught
    assert_equal 4, BA.progress(ID)
    assert_empty received
  end

  def test_q_new_species_checks_once_and_other_dex_does_not
    BA.unlock_category(:researcher)
    calls = []
    original = BA.method(:check)
    BA.stub(:check, ->(id) { calls << id; original.call(id) }) do
      @game.pokedex.mark_captured(:new_species)
      @game.pokedex.mark_captured(:new_species)
      PFM::Pokedex.new(@game).mark_captured(:foreign_species)
    end
    assert_equal [ID], calls
    assert_equal 1, BA.progress(ID)
  end

  def test_r_legacy_researcher_active_or_finished_later_level
    [:active_quests, :finished_quests].each do |collection|
      [49, 14, 69].each do |quest_id|
        setup
        capture(23)
        @game.quests.public_send(collection)[quest_id] = PFM::Quests::Quest.new(quest_id)
        @game.remove_instance_variable(:@bombance_achievements)
        @game = Marshal.load(Marshal.dump(@game))
        activate(@game)
        BA.on_map_ready
        5.times { BA.on_map_ready; BA.sync_all }
        assert BA.category_unlocked?(:researcher)
        assert_equal 23, BA.progress(ID)
        assert_equal [5, 15], received
        assert_equal 100, @game.money
        assert_equal 1, @game.bag.item_quantity(:poke_ball)
      end
    end
  end

  def test_pending_locked_bag_survives_reload_without_money_duplication
    capture(15)
    @game.bag.locked = true
    BA.unlock_category(:researcher)
    tier = BA::DEFINITIONS[ID][:tiers][1]
    assert BA.obtained?(ID, tier)
    refute BA.rewarded?(ID, tier)
    assert_equal :pending, BA.tier_record(ID, tier)[:status]
    @game = Marshal.load(Marshal.dump(@game))
    activate(@game)
    @game.bag.locked = false
    BA.sync_all
    BA.sync_all
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
    assert_equal 100, @game.money
    assert_equal 1, BA::Notifications.queue.size
  end

  def test_failed_item_preparation_does_not_partially_credit
    capture(15)
    @game.bag.singleton_class.class_eval { def clone; raise 'Simulated insertion failure'; end }
    BA.unlock_category(:researcher)
    assert_equal [5], received
    assert_equal 0, @game.bag.item_quantity(:poke_ball)
    @game.bag.singleton_class.send(:remove_method, :clone)
    BA.sync_all
    assert_equal [5, 15], received
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
  end

  def test_reentrant_post_commit_callback_cannot_duplicate
    capture(15)
    @game.quests.define_singleton_method(:add_item) do |*|
      BombanceAchievements.sync_all
      raise 'Simulated quest callback failure after inventory commit'
    end
    BA.unlock_category(:researcher)
    10.times { BA.sync_all }
    assert_equal [5, 15], received
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
    assert_equal 3, BA::Notifications.queue.size
    assert_equal 1, $test_log.size
  end

  def test_custom_counter_and_hidden_categories_are_configuration_only
    counter = BA::DEFINITIONS[ID].merge(category: :general, source: :crafted_items)
    with_constant(:DEFINITIONS, {crafted: counter}) do
      BA.increment(:crafted_items, 4)
      BA.increment(:crafted_items)
      assert_equal 5, BA.value(:crafted_items)
      assert_equal 100, @game.money
      BA.set(:crafted_items, 2)
      BA.set(:crafted_items, 5)
      assert_equal 100, @game.money
      assert_equal 16, BA.percentage(:general)
    end
    categories = BA::CATEGORIES.merge(secret: {title: 'Secret', hidden_until_unlocked: true},
                                      invisible: {title: 'Invisible', invisible_until_unlocked: true})
    with_constant(:CATEGORIES, categories) do
      assert_equal '???', BA.category_title(:secret)
      refute_includes BA.visible_categories, :invisible
      BA.unlock_category(:secret)
      assert_equal 'Secret', BA.category_title(:secret)
    end
    assert_raises(ArgumentError) { BA.increment(:pokedex_species) }
  end

  def test_notification_queue_is_sequential_and_safe_across_scenes
    capture(31)
    BA.unlock_category(:researcher)
    $scene = map = Scene_Map.new
    BA::Notifications.update(map)
    assert_equal 3, BA::Notifications.queue.size
    panel = BA::Notifications.instance_variable_get(:@panel)
    map.dialogue = true
    10.times { BA::Notifications.update(map) }
    assert_equal 3, BA::Notifications.queue.size
    refute BA::Notifications.instance_variable_get(:@viewport).visible
    map.dialogue = false
    BA::Notifications.instance_variable_set(:@elapsed, 4)
    BA::Notifications.update(map)
    assert_empty panel.stack
    BA::Notifications.update(map)
    assert_equal 2, BA::Notifications.queue.size
    map.call_scene(Object)
    assert_nil BA::Notifications.instance_variable_get(:@panel)
    map.dispose
    map.dispose
    $scene = Scene_Map.new
    $game_temp.in_battle = true
    BA::Notifications.update($scene)
    assert_equal 2, BA::Notifications.queue.size
    $game_temp.in_battle = false
    $scene.spriteset.instance_variable_set(:@map_panel, Object.new)
    BA::Notifications.update($scene)
    assert_equal 2, BA::Notifications.queue.size
    assert_empty $test_log
  end

  def test_save_preview_does_not_grant_and_idle_frames_do_not_check
    capture(23)
    @game.quests.active_quests[49] = PFM::Quests::Quest.new(49)
    bytes = Marshal.dump(@game)
    PFM.game_state = Marshal.load(bytes) # Same operation as native Save.load preview.
    assert_equal 0, $game_party.gold
    assert_empty BA::Notifications.queue
    PFM.game_state = @game
    $scene = Scene_Map.new
    assert_equal 100, @game.money
    BA.stub(:check, ->(*) { raise 'Per-frame achievement polling' }) do
      100.times { $scene.update_graphics }
    end
    assert_empty $test_log
  end

  def test_scrolling_categories_and_more_than_six_tiers
    categories = BA::CATEGORIES.merge((1..8).to_h { |i| ["category_#{i}".to_sym, {title: "Catégorie #{i}"}] })
    with_constant(:CATEGORIES, categories) do
      scene = open_ui
      8.times { press(scene, :DOWN) }
      assert_equal 4, scene.offset
      scene.dispose
    end
    more = BA::DEFINITIONS[ID].merge(tiers: BA::DEFINITIONS[ID][:tiers] +
      [{id: :species_150, value: 150, reward: {type: :money, amount: 100}}])
    with_constant(:DEFINITIONS, {ID => more}) do
      BA.unlock_category(:researcher)
      scene = open_ui
      press(scene, :DOWN)
      press(scene, :A)
      press(scene, :A)
      6.times { press(scene, :DOWN) }
      assert_equal [6, 1], [scene.index, scene.offset]
      scene.dispose
    end
  end

  def test_full_bag_keeps_reward_pending_and_snapshot_is_stable
    Configs.settings.max_bag_item_count = 1
    @game.bag.add_item(:poke_ball)
    capture(15)
    BA.unlock_category(:researcher)
    assert_equal [5], received
    tier = BA::DEFINITIONS[ID][:tiers][1]
    assert_equal({type: :item, id: :poke_ball, quantity: 1}, BA.tier_record(ID, tier)[:reward])
    @game.bag.remove_item(:poke_ball)
    BA.sync_all
    assert_equal [5, 15], received
    assert_equal 1, @game.bag.item_quantity(:poke_ball)
  end

  def test_native_capture_registration_path
    # Actual native battle method; its animation/message dependencies are not used
    # while the Pokedex UI is disabled, but capture registration remains identical.
    file = File.join(NATIVE, '5_Battle_01_Scene.rb')
    lines = File.readlines(file)
    start = lines.index { |line| line.include?('def update_pokedex_related_infos(pkmn)') }
    finish = (start + 1...lines.size).find { |i| lines[i].match?(/^    end/) }
    klass = Class.new
    klass.class_eval(lines[start..finish].join, file, start + 1)
    BA.unlock_category(:researcher)
    capture(4)
    pokemon = OpenStruct.new(id: 9999, form: 0)
    2.times { klass.new.update_pokedex_related_infos(pokemon) }
    assert_equal 5, @game.pokedex.creature_caught
    assert_equal [5], received
    assert_equal 100, @game.money
  end
end
