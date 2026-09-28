# frozen_string_literal: true
require_relative 'support'

class StorageTest < ApricornTest
  def test_new_game_and_validation
    assert_equal ApricornTrees::COLORS.to_h { |c| [c, 0] }, $apricorns.quantities
    assert_same PFM.game_state, $apricorns.game_state
    assert $apricorns.add(:red, 2)
    assert_equal 2, $apricorns[:red]
    assert $apricorns.remove(:red)
    refute $apricorns.remove(:red, 2)
    assert_equal 1, $apricorns[:red]
    [:orange, 'red', nil, 485].each { |bad| assert_raises(ArgumentError) { $apricorns.add(bad) } }
    [-1, 1.5, nil, '2'].each do |bad|
      assert_raises(ArgumentError) { $apricorns.add(:red, bad) }
      assert_raises(ArgumentError) { $apricorns.remove(:red, bad) }
    end
    assert_raises(FrozenError) { $apricorns.quantities[:red] = -1 }
    assert_equal 1, $apricorns[:red]
  end

  def test_round_trip_and_game_state_rebinding
    $apricorns.add(:green, 4)
    restored = Marshal.load(Marshal.dump(PFM.game_state))
    restored.expand_global_var
    assert_equal 4, $apricorns[:green]
    assert_same restored, $apricorns.game_state
    assert_same restored.apricorns, $apricorns
  end

  def test_old_save_imports_without_replaying_quests_and_is_idempotent
    state = PFM.game_state
    state.remove_instance_variable(:@apricorns)
    state.bag.instance_variable_get(:@items)[:red_apricorn] = 3
    state.bag.instance_variable_get(:@items)[486] = 2
    state.bag.instance_variable_get(:@orders)[2] = [:red_apricorn, :poke_ball]
    state.bag.shortcuts[0] = :red_apricorn
    restored = Marshal.load(Marshal.dump(state))
    restored.expand_global_var
    assert_equal 3, $apricorns[:red]
    assert_equal 2, $apricorns[:blue]
    assert_empty restored.quests.acquisitions
    assert_empty restored.bag.instance_variable_get(:@items)
    assert_equal [:poke_ball], restored.bag.get_order(2)
    restored.expand_global_var
    assert_equal 3, $apricorns[:red]
  end

  def test_legacy_bag_calls_share_one_source_and_quests_fire_once
    $bag.add_item(:red_apricorn, 2)
    $bag.store_item(485, 1)
    assert_equal 3, $apricorns[:red]
    assert_equal 3, $bag.item_quantity(:red_apricorn)
    assert $bag.contain_item?(:red_apricorn, 3)
    assert_empty $bag.instance_variable_get(:@items)
    assert_equal [[:red_apricorn, 2], [:red_apricorn, 1]], PFM.game_state.quests.acquisitions
    $bag.drop_item(:red_apricorn, 99)
    assert_equal 0, $apricorns[:red]
    $bag.add_item(:poke_ball, 2)
    assert_equal 2, $bag.item_quantity(:poke_ball)
  end

  def test_acquisition_hook_and_hook_failure_do_not_duplicate
    acquired = []
    ApricornTrees.on_acquire(:test) { |store, color, amount, source| acquired << [color, amount, source] }
    ApricornTrees.on_acquire(:broken) { raise 'bad extension' }
    $apricorns.add(:yellow, 2, source: :harvest)
    assert_equal [[:yellow, 2, :harvest]], acquired
    assert_equal 2, $apricorns[:yellow]
    assert_equal 1, $test_log.size
  end

  def test_native_signed_bag_operations_and_locked_bag
    $bag.add_item(:red_apricorn, 3)
    $bag.add_item(:red_apricorn, -1)
    $bag.remove_item(:red_apricorn, -2)
    assert_equal 4, $apricorns[:red]
    $bag.locked = true
    refute $bag.add_item(:red_apricorn)
    assert_equal 0, $bag.item_quantity(:red_apricorn)
    assert_equal 4, $apricorns[:red]
  end

  def test_loading_an_interrupted_player_restores_walking
    $game_player.enter_in_apricorn_state
    PFM.game_state.game_player = $game_player
    restored = Marshal.load(Marshal.dump(PFM.game_state))
    restored.expand_global_var
    assert_equal :walking, restored.game_player.state
    assert_nil restored.game_player.update_callback
  end
end

class TreesTest < ApricornTest
  def test_native_event_commands_created_through_refresh
    blank = RPG::EventCommand.new
    assert_nil blank.code
    assert_nil blank.indent
    assert_nil blank.parameters
    assert_raises(ArgumentError) { RPG::EventCommand.new(355, 0, ['apricorn_tree']) }
    event = tree.event # Calls the patched refresh on top of native page refresh.
    source = Marshal.dump(event.event)
    event.refresh
    assert_equal [[355, 0, ['apricorn_tree']], [0, 0, []]],
                 event.list.map { |command| [command.code, command.indent, command.parameters] }
    assert_equal source, Marshal.dump(event.event)
    assert_equal [108, 0], event.event.pages.first.list.map(&:code)
  end

  def test_ordinary_event_keeps_native_page_behavior
    commands = [event_command(355, 0, ['ordinary_action']), event_command]
    event = Game_Event.new(1, nil, commands: commands)
    page = event.event.pages.first
    replacement = event_page(commands, graphic: 'ordinary_npc', direction: 6, pattern: 1)
    replacement.trigger = 2
    replacement.condition.switch1_valid = true
    replacement.condition.switch1_id = 400
    event.event.pages << replacement
    event.refresh
    assert_same page, event.apricorn_page
    $game_switches[400] = true
    # Keep native automatic contact checking out of this headless test.
    event.instance_variable_set(:@can_parallel_execute, false)
    event.refresh
    assert_nil event.apricorn_color
    assert_same replacement, event.apricorn_page
    assert_same commands, event.list
    assert_equal ['ordinary_npc', 6, 1], [event.character_name, event.direction, event.pattern]
    assert_equal 2, event.instance_variable_get(:@trigger)
    assert event.instance_variable_get(:@walk_anime)
    event.send(:update_pattern)
    assert_equal 2, event.pattern
  end

  def test_explicit_red_declaration_ignores_event_name
    t = tree(:red)
    ['Noigrumier', 'Arbre route 1', 'Event 42', 'apricorn_blue'].each do |name|
      t.event.event.name = name
      t.event.refresh
      assert_equal :red, ApricornTrees::ApricornTree.new(t.event).color
      assert_equal 'apr_Red', t.event.character_name
    end
    # Even an accidental name read must not enter our recognition path.
    data = t.event.event
    def data.name; raise 'Event name must not be read'; end
    t.event.refresh
    assert t.harvest!
    assert_equal 1, $apricorns[:red]
    assert_equal 0, $apricorns[:blue]
  end

  def test_invalid_declared_color_is_refused
    error = assert_raises(ArgumentError) { tree(:orange) }
    assert_includes error.message, '<apricorn_tree: orange>'
    assert_equal 0, $apricorns[:red]
    assert_nil PFM.game_state.user_data[:tjn_events]
  end

  def test_old_name_and_non_comment_commands_do_not_declare_a_tree
    [[], [event_command(355, 0, ['<apricorn_tree: red>'])],
     [event_command(108, 0, ['A plain comment'])]].each do |commands|
      event = Game_Event.new(1, nil, name: 'apricorn_red', commands: commands)
      assert_nil event.apricorn_color
      assert_same commands, event.list
      assert_raises(ArgumentError) { ApricornTrees::ApricornTree.new(event) }
      $game_map.events[1] = event
      interpreter = Interpreter.new
      interpreter.setup([], 1)
      refute interpreter.apricorn_tree
    end
  end

  def test_comment_continuation_and_runtime_refresh_preserve_source_page
    commands = [event_command(108, 0, ['Arbre du chemin']),
                event_command(408, 0, ['  <apricorn_tree: red>  ']), event_command]
    event = Game_Event.new(1, nil, commands: commands)
    original = Marshal.dump(event.event)
    2.times do
      event.refresh
      assert_equal :red, event.apricorn_color
      assert_equal [355, 0], event.list.map(&:code)
      assert_equal ['apricorn_tree'], event.list.first.parameters
      assert_equal original, Marshal.dump(event.event)
    end
    event.event.pages.clear
    event.refresh
    assert_nil event.apricorn_color
    assert_nil event.list
    event.event.pages << event_page([event_command(108, 0, ['<apricorn_tree: blue>'])])
    event.refresh
    assert_equal :blue, event.apricorn_color
    assert_equal 'apr_blue', event.character_name
  end

  def test_malformed_or_duplicate_declarations_are_refused
    ['<apricorn_tree:>', '<apricorn_tree red>'].each do |line|
      commands = [event_command(108, 0, [line])]
      assert_raises(ArgumentError) { Game_Event.new(1, nil, commands: commands) }
    end
    commands = %w[red blue].map { |color| event_command(108, 0, ["<apricorn_tree: #{color}>"]) }
    assert_raises(ArgumentError) { Game_Event.new(1, nil, commands: commands) }
  end

  ApricornTrees::COLORS.each do |color|
    define_method("test_harvest_#{color}_once_and_empty_frame") do
      t = tree(color)
      assert t.available?
      assert_equal ApricornTrees::TYPES[color][:graphic], t.event.character_name
      assert_equal [2, 0], [t.event.direction, t.event.pattern]
      interpreter = run_sequence(t)
      assert_equal 1, $apricorns[color]
      refute t.available?
      refute t.harvest!
      assert_equal [8, 2], [t.event.direction, t.event.pattern]
      assert_equal :walking, $game_player.state
      assert_nil $game_player.update_callback
      assert_nil ApricornTrees.session
      assert_equal 2, interpreter.messages.size
      run_sequence(t)
      assert_equal 1, $apricorns[color]
      t.event.send(:update_pattern)
      assert_equal 2, t.event.pattern
    end
  end

  def test_two_same_color_trees_and_maplinker_identity
    a = tree(:red, id: 41, map: 9, original: 2)
    b = tree(:red, id: 42, map: 9, original: 3)
    c = tree(:red, id: 43, map: 10, original: 2)
    assert a.harvest!
    assert b.available?
    assert c.available?
    a_on_own_map = tree(:red, id: 2, map: 9, original: 2)
    refute a_on_own_map.available?
    assert_equal [8, 2], [a_on_own_map.event.direction, a_on_own_map.event.pattern]
    assert PFM.game_state.user_data[:tjn_events][9].key?(2)
    refute PFM.game_state.user_data[:tjn_events].key?(1)
  end

  def test_next_day_not_24_hours_with_save_load_and_clock_changes
    ApricornTrees.test_time = Time.new(2026, 12, 31, 23, 55, 0, '+01:00')
    t = tree
    t.harvest!
    restored = Marshal.load(Marshal.dump(PFM.game_state))
    restored.expand_global_var
    t = tree
    refute t.available?
    assert_equal 1, $apricorns[:red]
    ApricornTrees.test_time = Time.new(2026, 12, 30, 10, 0, 0, '+01:00')
    refute t.available?
    ApricornTrees.test_time = Time.new(2027, 1, 1, 0, 0, 0, '+01:00')
    $game_map.update
    assert t.available?
    assert_equal [2, 0], [t.event.direction, t.event.pattern]
    assert t.harvest!
    assert_equal 2, $apricorns[:red]
  end

  def test_real_midnight_even_when_tjn_virtual_and_dst_offset_changes
    $game_switches[Yuki::Sw::TJN_RealTime] = false
    ApricornTrees.test_time = Time.new(2026, 10, 24, 12, 0, 0, '+02:00')
    t = tree
    t.harvest!
    ApricornTrees.test_time = Time.new(2026, 10, 25, 12, 0, 0, '+01:00')
    assert t.available?
    assert_equal false, $game_switches[7]
  end

  def test_native_mining_timer_is_untouched
    PFM.game_state.user_data[:tjn_events] = {1 => {90 => [123456, 'B']}}
    t = tree
    t.harvest!
    ApricornTrees.test_time += 86400
    $game_map.update
    assert_equal [123456, 'B'], PFM.game_state.user_data[:tjn_events][1][90]
  end

  def test_interrupt_before_commit_and_reentry
    t = tree
    checked = false
    run_sequence(t) do
      unless checked
        assert_nil ApricornTrees.begin_session(t)
        assert $game_player.apricorn_state?
        checked = true
        $game_temp.player_transferring = true
      end
    end
    assert_equal 0, $apricorns[:red]
    assert t.available?
    assert_equal :walking, $game_player.state
    assert_nil ApricornTrees.session
    $game_temp.player_transferring = false
    run_sequence(t)
    assert_equal 1, $apricorns[:red]
  end

  def test_abandoned_fiber_releases_player_via_watchdog
    t = tree
    token = ApricornTrees.begin_session(t)
    t.event.apricorn_animating = true
    $game_player.enter_in_apricorn_state
    ApricornTrees.test_tick = 6
    $game_player.update_apricorn_state
    assert_nil ApricornTrees.session
    assert_equal :walking, $game_player.state
    assert_nil $game_player.update_callback
    refute t.event.apricorn_animating
    assert_equal 0, $apricorns[:red]
  end

  def test_rmxp_helper_uses_child_fiber
    t = tree
    interpreter = Interpreter.new
    interpreter.setup([], t.event.id)
    assert interpreter.apricorn_tree
    child = interpreter.instance_variable_get(:@child_interpreter)
    assert child.instance_variable_get(:@fiber)
    assert_equal 0, $apricorns[:red]
  end

  def test_failure_during_animation_releases_everything_without_award
    t = tree
    event = t.event
    def event.apricorn_set_frame(direction, pattern)
      raise 'Animation failed' if direction == 6
      super
    end
    assert_raises(RuntimeError) { run_sequence(t) }
    assert t.available?
    assert_equal 0, $apricorns[:red]
    assert_equal :walking, $game_player.state
    assert_nil $game_player.update_callback
    assert_nil ApricornTrees.session
    assert_equal [2, 0], [t.event.direction, t.event.pattern]
  end

  def test_timer_writer_uses_a_single_clock_sample_at_midnight
    minute = ApricornTrees.real_minute
    clock = ApricornTrees::RealClockInterpreter.new(minute)
    ApricornTrees.test_time += 86400
    clock.trigger_event_in(ApricornTrees.next_day_minute(minute) - minute, 'D', 4, 9)
    assert_equal [ApricornTrees.next_day_minute(minute), 'D'], PFM.game_state.user_data[:tjn_events][9][4]
  end
end

class PlayerRestorationTest < ApricornTest
  def test_walking_restores_native_movement
    run_sequence(tree)
    assert_equal :walking, $game_player.state
    assert_equal [3, 4], [$game_player.move_speed, $game_player.move_frequency]
    assert_equal 'player_m_walk', $game_player.character_name
    assert_nil $game_player.update_callback
  end

  def test_surfing_restores_flag_appearance_and_native_speed
    $game_switches[Yuki::Sw::Gender] = true
    $game_player.instance_variable_set(:@surfing, true)
    $game_player.enter_in_surfing_state
    run_sequence(tree)
    assert_equal :surfing, $game_player.state
    assert $game_player.instance_variable_get(:@surfing)
    assert_equal [4, 4], [$game_player.move_speed, $game_player.move_frequency]
    assert_equal 'player_f_surf', $game_player.character_name
    assert_nil $game_player.update_callback
  end

  %i[enter_in_cycling_state enter_in_acro_bike_state].each do |entry|
    define_method("test_#{entry}_preserves_existing_dismount_policy") do
      $game_player.send(entry)
      assert $game_player.cycling?
      run_sequence(tree)
      assert_equal :walking, $game_player.state
      refute $game_switches[Yuki::Sw::EV_Bicycle]
      refute $game_switches[Yuki::Sw::EV_AccroBike]
      refute $game_player.on_acro_bike
      assert_equal [3, 4], [$game_player.move_speed, $game_player.move_frequency]
      assert_equal 'player_m_walk', $game_player.character_name
      assert_nil $game_player.update_callback
    end
  end

  def test_running_returns_to_walking_as_in_native_return
    $game_player.enter_in_running_state
    run_sequence(tree)
    assert_equal :walking, $game_player.state
    refute $game_switches[Yuki::Sw::EV_Run]
    assert_equal [3, 4], [$game_player.move_speed, $game_player.move_frequency]
    assert_nil $game_player.update_callback
  end

  def test_swamp_context_is_preserved_by_native_return
    $game_player.instance_variable_set(:@in_swamp, true)
    $game_player.enter_in_walking_state
    run_sequence(tree)
    assert_equal :swamp, $game_player.state
    assert_equal 'player_m_swamp', $game_player.character_name
    assert_equal [3, 4], [$game_player.move_speed, $game_player.move_frequency]
    assert_nil $game_player.update_callback
  end

  def test_external_walking_state_does_not_leave_an_apricorn_callback
    run_sequence(tree) { $game_player.enter_in_walking_state }
    assert_equal :walking, $game_player.state
    assert_nil $game_player.update_callback
    assert_nil ApricornTrees.session
    assert_nil $game_player.instance_variable_get(:@apricorn_started_at)
    assert_nil $game_player.instance_variable_get(:@apricorn_previous_graphic)
  end

  def test_cleanup_never_clears_a_foreign_callback_even_if_state_is_still_apricorn
    player = $game_player
    def player.external_animation; end
    run_sequence(tree) { player.instance_variable_set(:@update_callback, :external_animation) }
    assert_equal :external_animation, player.update_callback
    assert_nil ApricornTrees.session
    player.instance_variable_set(:@state, :using_skill)
    player.leave_apricorn_state
    assert_equal :external_animation, player.update_callback
    assert_equal :using_skill, player.state
  end

  def test_cancellation_clears_both_apricorn_callbacks_after_external_state_change
    %i[update_enter_apricorn_state update_apricorn_state].each do |callback|
      ApricornTrees.begin_session(tree)
      $game_player.enter_in_apricorn_state
      $game_player.instance_variable_set(:@update_callback, callback)
      $game_player.enter_in_walking_state
      ApricornTrees.cancel_session
      assert_nil $game_player.update_callback
      assert_nil ApricornTrees.session
      assert_equal :walking, $game_player.state
    end
  end
end

class SessionInvalidationTest < ApricornTest
  def assert_interruption
    t = tree
    calls = []
    ApricornTrees.on_acquire(:audit) { |*args| calls << args }
    changed = false
    frame_after_change = nil
    run_sequence(t) do
      next if changed
      changed = true
      yield t
      frame_after_change = [t.event.character_name, t.event.direction, t.event.pattern]
    end
    assert_equal ApricornTrees::COLORS.to_h { |color| [color, 0] }, $apricorns.quantities
    assert_empty PFM.game_state.quests.acquisitions
    assert_empty calls
    assert_nil t.timer
    refute $game_self_switches[[*t.key, ApricornTrees::TIMER_SWITCH]]
    assert_nil ApricornTrees.session
    assert_nil $game_player.update_callback
    assert_equal :walking, $game_player.state
    refute t.event.apricorn_animating
    assert_equal frame_after_change, [t.event.character_name, t.event.direction, t.event.pattern]
    t
  end

  def test_erased_event_cancels_without_award
    assert_interruption { |t| t.event.erase }
  end

  def test_no_active_page_cancels_without_award
    assert_interruption do |t|
      t.event.event.pages.clear
      t.event.refresh
    end
  end

  def test_new_non_tree_page_keeps_its_own_graphics
    assert_interruption do |t|
      t.event.event.pages << event_page([event_command], graphic: 'ordinary_npc', direction: 6, pattern: 3)
      t.event.refresh
    end
  end

  def test_new_page_with_same_color_is_a_different_logical_tree
    assert_interruption do |t|
      commands = [event_command(108, 0, ['<apricorn_tree: red>']), event_command]
      t.event.event.pages << event_page(commands, direction: 4, pattern: 1)
      t.event.refresh
    end
  end

  def test_color_change_on_same_page_cancels
    assert_interruption do |t|
      t.page.list.first.parameters = ['<apricorn_tree: blue>']
      t.event.refresh
    end
  end

  def test_declaration_removed_without_refresh_cancels
    assert_interruption { |t| t.page.list.first.parameters = ['Just a tree now'] }
  end

  def test_invalid_declaration_without_refresh_cancels
    assert_interruption { |t| t.page.list.first.parameters = ['<apricorn_tree: orange>'] }
  end

  def test_replaced_event_is_not_modified
    replacement = nil
    assert_interruption do |t|
      replacement = Game_Event.new(t.event.id, nil, commands: [event_command])
      replacement.event.pages.replace([event_page([event_command], graphic: 'replacement', direction: 4, pattern: 2)])
      replacement.refresh
      $game_map.events[t.event.id] = replacement
    end
    assert_equal ['replacement', 4, 2], [replacement.character_name, replacement.direction, replacement.pattern]
  end

  def test_original_identity_change_cancels
    assert_interruption { |t| t.event.instance_variable_set(:@original_id, 99) }
  end
end

require_relative 'box'

class CraftTest < ApricornTest
  def add_recipe(key, ingredients, result: :level_ball)
    CraftSystem::Recipes.data[key] = {ingredients: ingredients, result: result, quantity: 1, category: :ball}
  end

  def test_six_existing_recipes_and_black_recipe
    ApricornTrees::TYPES.each do |color, data|
      refute_nil CraftSystem::Recipes[data[:ball]], "Missing recipe #{data[:ball]}"
      $apricorns.add(color, 1)
      assert_equal 1, CraftSystem.max_craft(data[:ball])
      assert CraftSystem.craft(data[:ball])
      assert_equal 0, $apricorns[color]
      assert_equal 1, $bag.item_quantity(data[:ball])
    end
  end

  def test_insufficient_sufficient_and_invalid_amounts
    add_recipe(:test_two, {red_apricorn: 2})
    $apricorns.add(:red)
    refute CraftSystem.craft(:test_two)
    assert_equal 1, $apricorns[:red]
    assert_equal 0, $bag.item_quantity(:level_ball)
    $apricorns.add(:red)
    [-1, 0, 1.5, '1'].each { |n| refute CraftSystem.craft(:test_two, n) }
    assert CraftSystem.craft(:test_two)
    assert_equal 0, $apricorns[:red]
    assert_equal 1, $bag.item_quantity(:level_ball)
  end

  def test_failed_result_addition_and_mixed_materials_are_atomic
    add_recipe(:test_mixed, {red_apricorn: 2, oran_berry: 3})
    $apricorns.add(:red, 4)
    $bag.add_item(:oran_berry, 6)
    before_quests = PFM.game_state.quests.acquisitions.dup
    def $bag.add_item(item, amount = 1)
      raise 'Cannot insert result' if item == :level_ball
      super
    end
    refute CraftSystem.craft(:test_mixed)
    assert_equal 4, $apricorns[:red]
    assert_equal 6, $bag.item_quantity(:oran_berry)
    assert_equal 0, $bag.item_quantity(:level_ball)
    assert_equal before_quests, PFM.game_state.quests.acquisitions
    $bag.singleton_class.remove_method(:add_item)
    assert CraftSystem.craft(:test_mixed, 2)
    assert_equal 0, $apricorns[:red]
    assert_equal 0, $bag.item_quantity(:oran_berry)
    assert_equal 2, $bag.item_quantity(:level_ball)
    assert_equal [:level_ball, 2], PFM.game_state.quests.acquisitions.last
  end

  def test_silent_output_failure_and_capacity
    add_recipe(:test_silent, {red_apricorn: 1})
    $apricorns.add(:red, 2)
    def $bag.add_item(*); false; end
    refute CraftSystem.craft(:test_silent)
    assert_equal 2, $apricorns[:red]
    $bag.singleton_class.remove_method(:add_item)
    $bag.add_item(:level_ball, 999)
    refute CraftSystem.craft(:test_silent)
    assert_equal 2, $apricorns[:red]
  end

  def test_other_recipes_still_use_original_crafting
    add_recipe(:test_ordinary, {oran_berry: 2}, result: :berry_juice)
    $bag.add_item(:oran_berry, 2)
    before = $apricorns.quantities
    assert CraftSystem.craft(:test_ordinary)
    assert_equal 1, $bag.item_quantity(:berry_juice)
    assert_equal 0, $bag.item_quantity(:oran_berry)
    assert_equal before, $apricorns.quantities
  end

  def test_other_recipe_errors_are_not_swallowed_by_apricorn_patch
    add_recipe(:test_native_error, {oran_berry: 2}, result: :berry_juice)
    $bag.add_item(:oran_berry, 2)
    def $bag.add_item(*); raise 'Native error'; end
    assert_raises(RuntimeError) { CraftSystem.craft(:test_native_error) }
  end
end

class ResourceTest < ApricornTest
  def test_installed_assets_are_identical_4_by_4_sheets
    ApricornTrees::TYPES.each_value do |data|
      original = File.binread(File.join(PROJECT, '../../Noigrumes', "#{data[:graphic]}.png"))
      installed = File.binread(File.join(PROJECT, '../graphics/characters', "#{data[:graphic]}.png"))
      assert_equal original, installed
      assert_equal [192, 256], installed.byteslice(16, 8).unpack('N2')
    end
  end
end

class NativeQuestAdapter
  attr_accessor :active_quests
  def initialize(quest); @active_quests = {1 => quest}; end
  def check_quest(*); end
end
native_methods(NativeQuestAdapter, '4_Systems_800_Quest.rb', [:add_item])

class NativeQuestObjective
  attr_reader :count
  def objective?(method, item); method == :objective_obtain_item && item == :red_apricorn; end
  def data_get(*); @count || 0; end
  def data_set(key, item, value); @count = value; end
  def quest_id; 1; end
end

class QuestTest < ApricornTest
  def test_native_obtain_item_objective_receives_the_acquisition
    objective = NativeQuestObjective.new
    PFM.game_state.quests = NativeQuestAdapter.new(objective)
    $apricorns.add(:red, 3)
    $apricorns.add(:blue, 2)
    assert_equal 3, objective.count
    tree(:red).harvest!
    assert_equal 4, objective.count
    assert_empty $bag.instance_variable_get(:@items)
  end
end
