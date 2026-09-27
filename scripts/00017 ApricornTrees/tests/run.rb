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
    [[], [RPG::EventCommand.new(355, 0, ['<apricorn_tree: red>'])],
     [RPG::EventCommand.new(108, 0, ['A plain comment'])]].each do |commands|
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
    commands = [RPG::EventCommand.new(108, 0, ['Arbre du chemin']),
                RPG::EventCommand.new(408, 0, ['  <apricorn_tree: red>  ']), RPG::EventCommand.new]
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
    event.event.pages << OpenStruct.new(list: [RPG::EventCommand.new(108, 0, ['<apricorn_tree: blue>'])])
    event.refresh
    assert_equal :blue, event.apricorn_color
    assert_equal 'apr_blue', event.character_name
  end

  def test_malformed_or_duplicate_declarations_are_refused
    ['<apricorn_tree:>', '<apricorn_tree red>'].each do |line|
      commands = [RPG::EventCommand.new(108, 0, [line])]
      assert_raises(ArgumentError) { Game_Event.new(1, nil, commands: commands) }
    end
    commands = %w[red blue].map { |color| RPG::EventCommand.new(108, 0, ["<apricorn_tree: #{color}>"]) }
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

class BoxTest < ApricornTest
  def test_handler_navigation_details_and_consultation
    $apricorns.add(:red, 5)
    scene = GamePlay::ApricornBox.new
    before = $apricorns.quantities
    scene.send(:create_graphics)
    assert_equal 7, scene.instance_variable_get(:@collection).icons.size
    assert_equal :red, scene.selected_color
    assert_equal 'Noigrume Rouge', scene.instance_variable_get(:@name).text
    scene.move_selection(-1)
    assert_equal :black, scene.selected_color
    assert_equal :heavy_ball, scene.instance_variable_get(:@ball_icon).data
    7.times { scene.move_selection(1) }
    assert_equal :black, scene.selected_color
    Input.key = :UP
    scene.update_inputs
    assert_equal :white, scene.selected_color
    Input.key = :B
    scene.update_inputs
    assert_equal false, scene.instance_variable_get(:@running)
    assert_equal before, $apricorns.quantities
    before_use, handler = PFM::ItemDescriptor::HANDLERS.fetch(:apricorn_box)
    assert before_use
    parent = Object.new
    def parent.call_scene(klass); @opened = klass; end
    assert_equal :unused, handler.call(nil, parent)
    assert_equal GamePlay::ApricornBox, parent.instance_variable_get(:@opened)
    scene.dispose
    %i[@heading @collection @detail].each do |ivar|
      window = scene.instance_variable_get(ivar)
      assert window.disposed?
      assert window.sprite_stack.disposed
    end
  end

  def test_all_seven_selections_zero_and_large_quantities
    $apricorns.add(:white, 10_000)
    before = $apricorns.quantities
    scene = GamePlay::ApricornBox.new
    scene.send(:create_graphics)
    ApricornTrees::DISPLAY_ORDER.each do |color|
      assert_equal color, scene.selected_color
      assert_equal ApricornTrees::TYPES[color][:item], scene.instance_variable_get(:@icon).data
      assert_includes scene.instance_variable_get(:@description).text, color.to_s
      assert_includes scene.instance_variable_get(:@quantity).text, $apricorns[color].to_s
      scene.move_selection(1)
    end
    assert_equal before, $apricorns.quantities
  end
end

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
