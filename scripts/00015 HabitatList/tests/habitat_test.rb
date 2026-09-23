require_relative 'support'
require 'json'
require 'digest'

HabitatMap = Struct.new(:map_id)
HabitatPlayer = Struct.new(:system_tag_db_symbol, :terrain_tag, :front_system_tag_db_symbol, :front_terrain_tag)
HabitatEnvironment = Struct.new(:zone) do
  def get_current_zone_data; zone; end
  def can_fish?; true; end
end
HabitatState = Struct.new(:game_switches, :game_variables, :game_map, :game_player, :env, :pokedex, :tint_time_set)

class HabitatTest < Minitest::Test
  def setup
    $habitat_database = LOCAL_DATABASE.dup
    $habitat_database[:groups] = {}
    $habitat_database[:zones__id] = []
    $habitat_database[:zones] = {}
    $habitat_errors = []
    $habitat_text_reads = []
    Input.key = nil
    Mouse.wheel = 0
    RPG::Cache.fail_icon = false
    RPG::Cache.icon_reads = []
    RPG::Cache.fail_front = RPG::Cache.fail_question = RPG::Cache.raise_front = false
    RPG::Cache.front_reads = []
    RPG::Cache.question_reads = []
    RPG::Cache.front_dimensions = {}
    RPG::Cache.front_bounds = {}
    RPG::Cache.capture_reads = []
    RPG::Cache.time_reads = []
    $habitat_front_resolutions = []
    PFM.game_state = HabitatState.new(Hash.new(false), Hash.new(0), HabitatMap.new(10000), HabitatPlayer.new, HabitatEnvironment.new)
    $env = PFM.game_state.env
    $pokedex = PFM::Pokedex.new(PFM.game_state)
    PFM.game_state.pokedex = $pokedex
    $pokedex.enable
    $pokedex.national = true
    @catalog = ElementZ::Habitat::Catalog.new
  end

  def encounter(specie = :rattata, form = 0, rate = 1)
    studio_object(Studio::Group::Encounter, specie: specie, form: form, encounter_rate: rate)
  end

  def condition(type, value, relation = :AND)
    studio_object(Studio::Group::CustomCondition, type: type, value: value, relation_with_previous_condition: relation)
  end

  def group(key, encounters = [encounter], conditions: [], system: :grass, terrain: 0, tool: nil)
    value = studio_object(Studio::Group, db_symbol: key, system_tag: system, terrain_tag: terrain,
                          tool: tool, custom_conditions: conditions, encounters: encounters)
    $habitat_database[:groups][key] = value
  end

  def zone(keys, key: :test_zone, maps: [10000])
    value = studio_object(Studio::Zone, id: maps.first, db_symbol: key, maps: maps, wild_groups: keys)
    $habitat_database[:zones__id] << value
    $habitat_database[:zones][key] = value
    $env.zone = value
  end

  def scene
    value = GamePlay::ZoneEncounters.new
    value.send(:create_graphics)
    value
  end

  def test_unknown_and_empty_zone
    assert_nil @catalog.snapshot.zone_key
    zone([])
    assert_empty @catalog.snapshot.entries
    assert_equal :test_zone, @catalog.snapshot.zone_key
  end

  def test_zone_change_and_stale_environment_on_unmapped_map
    group(:a)
    first = zone([:a])
    second = zone([], key: :second, maps: [10001])
    $env.zone = first
    PFM.game_state.game_map.map_id = 10001
    assert_equal second.db_symbol, @catalog.snapshot.zone_key
    PFM.game_state.game_map.map_id = 99999
    assert_nil @catalog.snapshot.zone_key
  end

  def test_unknown_seen_after_battle_mark_and_capture
    group(:a)
    zone([:a])
    refute @catalog.snapshot.entries.first.revealed?
    # Exactly the calls made by the local battle end/capture handlers.
    $pokedex.mark_seen(:rattata, 0, forced: true)
    assert @catalog.snapshot.entries.first.seen
    refute @catalog.snapshot.entries.first.caught
    $pokedex.mark_captured(:rattata, 0)
    assert @catalog.snapshot.entries.first.caught
  end

  def test_global_seen_survives_zone_change
    group(:a)
    zone([:a])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    zone([:a], key: :elsewhere, maps: [10001])
    PFM.game_state.game_map.map_id = 10001
    assert @catalog.snapshot.entries.first.revealed?
  end

  def test_day_night_morning_sunset_and_switch_refresh
    [11, 12, 13, 14].each { |switch| group("time#{switch}".to_sym, conditions: [condition(:enabled_switch, switch)]) }
    zone(%i[time11 time12 time13 time14])
    [11, 12, 13, 14].each do |switch|
      [11, 12, 13, 14].each { |other| PFM.game_state.game_switches[other] = other == switch }
      assert_equal ["time#{switch}".to_sym], @catalog.snapshot.groups.select { |g| g.status == :active }.map(&:key)
    end
  end

  def test_conditions_follow_actual_psdk_and_or_semantics
    conditions = [condition(:map_id, 10001), condition(:map_id, 10000, :OR), condition(:enabled_switch, 402)]
    group(:a, conditions: conditions)
    zone([:a])
    assert_empty @catalog.snapshot.entries
    PFM.game_state.game_switches[402] = true
    assert_equal 1, @catalog.snapshot.entries.size
    PFM.game_state.game_map.map_id = 10001
    $env.zone.instance_variable_set(:@maps, [10000, 10001])
    assert_equal 1, @catalog.snapshot.entries.size
  end

  def test_first_active_group_per_context_wins_like_actual_wild_manager
    group(:disabled, conditions: [condition(:enabled_switch, 402)])
    group(:first)
    group(:hidden, [encounter(:pikachu)])
    group(:different_terrain, [encounter(:geodude)], terrain: 1)
    zone(%i[disabled first hidden different_terrain])
    result = @catalog.snapshot
    assert_equal %i[inactive active shadowed active], result.groups.map(&:status)
    assert_equal %i[rattata geodude], result.entries.map(&:specie)
    manager = PFM::Wild_Battle.new(PFM.game_state)
    manager.instance_variable_set(:@groups, result.groups.reject { |g| g.status == :inactive }.map { |g| data_group(g.key) })
    PFM.game_state.game_player.system_tag_db_symbol = :grass
    [0, 1].each do |terrain|
      PFM.game_state.game_player.terrain_tag = terrain
      picked = manager.send(:current_selected_group)
      assert_equal :active, result.groups.find { |g| g.key == picked.db_symbol }.status
    end
  end

  def test_fishing_tools_do_not_mask_walking_and_use_first_matching_group
    group(:walk, system: :pond)
    group(:old, [encounter(:magikarp)], system: :pond, tool: :old_rod)
    group(:old_hidden, [encounter(:pikachu)], system: :pond, tool: :old_rod)
    group(:good, [encounter(:barboach)], system: :pond, tool: :good_rod)
    zone(%i[walk old old_hidden good])
    result = @catalog.snapshot
    assert_equal %i[active active shadowed active], result.groups.map(&:status)
    assert_equal %i[rattata magikarp barboach], result.entries.map(&:specie)
    manager = PFM::Wild_Battle.new(PFM.game_state)
    manager.instance_variable_set(:@groups, %i[walk old old_hidden good].map { |key| data_group(key) })
    PFM.game_state.game_player.front_system_tag_db_symbol = :pond
    PFM.game_state.game_player.front_terrain_tag = 0
    assert manager.any_fish?(:normal)
    manager.any_fish?(:normal, true)
    assert_equal :old, manager.send(:current_selected_group).db_symbol
  end

  def test_empty_first_group_masks_following_group_and_zero_rate_is_excluded
    group(:empty, [])
    group(:masked)
    group(:zero, [encounter(:pikachu, 0, 0)], system: :cave)
    zone(%i[empty masked zero])
    assert_empty @catalog.snapshot.entries
    assert_equal :shadowed, @catalog.snapshot.groups[1].status
  end

  def test_duplicates_merge_per_species_and_exact_form
    group(:grass, [encounter, encounter, encounter(:rattata, 1)])
    group(:cave, [encounter], system: :cave)
    zone(%i[grass grass cave])
    entries = @catalog.snapshot.entries
    assert_equal [[:rattata, 0], [:rattata, 1]], entries.map(&:key)
    assert_equal 2, entries.first.habitats.size
    $pokedex.mark_seen(:rattata, 0, forced: true)
    assert @catalog.snapshot.entries[0].revealed?
    refute @catalog.snapshot.entries[1].revealed?
  end

  def test_automatic_forms_use_all_existing_non_special_forms_without_mutating_database_or_rng
    group(:auto, [encounter(:vivillon, -1)])
    zone([:auto])
    original = data_creature(:vivillon).forms.dup
    expected = original.map(&:form).select { |form| form < 30 }
    srand(1234)
    expected_random = rand
    srand(1234)
    assert_equal expected, @catalog.snapshot.entries.map(&:form)
    assert_equal expected_random, rand
    assert_equal original, data_creature(:vivillon).forms
  end

  def test_special_automatic_form_is_explicitly_unresolved_without_adapter
    group(:auto, [encounter(:meowstic, -1)])
    zone([:auto])
    assert_empty @catalog.snapshot.entries
    refute_empty @catalog.snapshot.issues
    ElementZ::Habitat::Catalog::FORM_RESOLVERS[:meowstic] = proc { |_encounter| [0, 1] }
    assert_equal [0, 1], @catalog.snapshot.entries.map(&:form)
  ensure
    ElementZ::Habitat::Catalog::FORM_RESOLVERS.delete(:meowstic)
  end

  def test_missing_group_species_and_form_are_reported_without_fallback_leak
    group(:invalid, [encounter(:not_a_creature), encounter(:rattata, 999)])
    zone(%i[not_a_group invalid])
    assert_empty @catalog.snapshot.entries
    assert_equal 3, @catalog.snapshot.issues.size
  end

  def test_snapshot_never_writes_to_pokedex_or_wild_manager
    group(:a)
    zone([:a])
    previous = Marshal.dump($pokedex)
    3.times { @catalog.snapshot }
    assert_equal previous, Marshal.dump($pokedex)
  end

  def test_save_reload_preserves_exact_form_flags_without_extra_save_data
    group(:a, [encounter(:rattata, 1)])
    zone([:a])
    $pokedex.mark_seen(:rattata, 1, forced: true)
    $pokedex.mark_captured(:rattata, 1)
    expected_variables = $pokedex.instance_variables
    saved = Marshal.dump(PFM.game_state)
    PFM.game_state = Marshal.load(saved)
    $pokedex = PFM.game_state.pokedex
    $env = PFM.game_state.env
    assert @catalog.snapshot.entries.first.caught
    assert @catalog.snapshot.entries.first.seen
    assert_equal expected_variables, $pokedex.instance_variables
    refute_match(/ElementZ|Habitat::/, saved)
  end

  def test_hidden_ui_does_not_resolve_names_forms_or_sprites
    group(:a)
    zone([:a])
    view = scene.instance_variable_get(:@page)
    cell = view.instance_variable_get(:@cells).first
    assert_equal 'graphics/pokedex/pokefront/000.png', cell[:sprite].bitmap.asset
    assert cell[:sprite].visible
    assert_empty RPG::Cache.icon_reads
    assert_empty RPG::Cache.front_reads
    assert_empty $habitat_front_resolutions
    assert_equal ['000'], RPG::Cache.question_reads
    refute $habitat_text_reads.any? { |file, _id| [0, 67].include?(file) }
  end

  def test_live_scene_refresh_reveals_seen_then_caught_and_follows_zone
    group(:a)
    zone([:a])
    value = scene
    cell = value.instance_variable_get(:@page).instance_variable_get(:@cells).first
    refute cell[:badge].visible
    $pokedex.mark_seen(:rattata, 0, forced: true)
    value.send(:refresh_catalog, force: true)
    cell = value.instance_variable_get(:@page).instance_variable_get(:@cells).first
    assert_equal 'graphics/pokedex/pokefront/0019.png', cell[:sprite].bitmap.asset
    assert cell[:sprite].visible
    refute cell[:badge].visible
    assert_empty RPG::Cache.capture_reads
    $pokedex.mark_captured(:rattata, 0)
    value.send(:refresh_catalog, force: true)
    assert cell[:badge].visible
    assert_equal 'graphics/pokedex/Catch.png', cell[:badge].bitmap.asset
    assert_equal 16, cell[:badge].bitmap.width
    assert_equal 'Vus 1/1 · Capturés 1/1', value.instance_variable_get(:@page).instance_variable_get(:@counts).text
    value.send(:action_a)
    assert_equal 'Vus 1/1 · Capturés 1/1', value.instance_variable_get(:@page).instance_variable_get(:@counts).text
    zone([], key: :new, maps: [10001])
    PFM.game_state.game_map.map_id = 10001
    value.send(:refresh_catalog, force: true)
    refute cell[:sprite].visible
    refute cell[:badge].visible
  end

  def test_missing_front_uses_question_and_scene_remains_usable
    group(:a)
    zone([:a])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    RPG::Cache.fail_front = true
    value = scene
    cell = value.instance_variable_get(:@page).instance_variable_get(:@cells).first
    assert_equal 'graphics/pokedex/pokefront/000.png', cell[:sprite].bitmap.asset
    assert cell[:sprite].visible
    value.send(:action_b)
    refute value.instance_variable_get(:@running)
  end

  def test_fixed_meowstic_forms_are_rendered_without_random_generation
    group(:a, [encounter(:meowstic, 0), encounter(:meowstic, 1)])
    zone([:a])
    [0, 1].each { |form| $pokedex.mark_seen(:meowstic, form, forced: true) }
    value = scene
    cells = value.instance_variable_get(:@page).instance_variable_get(:@cells)
    assert_equal 'graphics/pokedex/pokefront/0678.png', cells[0][:sprite].bitmap.asset
    assert_equal 'graphics/pokedex/pokefront/0678_01.png', cells[1][:sprite].bitmap.asset
    assert_equal %w[0678 0678_01], RPG::Cache.front_reads
    refute $habitat_text_reads.any? { |file, _id| [0, 67].include?(file) }
  end

  def test_more_than_twelve_entries_and_empty_navigation
    group(:a, [encounter(:vivillon, -1)])
    zone([:a])
    value = scene
    assert_operator value.send(:current_entries).size, :>, 12
    value.send(:change_page, 1)
    assert_equal 12, value.instance_variable_get(:@offset)
    value.send(:change_page, 1)
    assert_equal 0, value.instance_variable_get(:@offset)
    zone([])
    value.send(:refresh_catalog, force: true)
    value.send(:change_group, 1)
    value.send(:change_page, 1)
    assert_equal 0, value.instance_variable_get(:@offset)
  end

  def test_inactive_group_is_consultable_but_not_in_overview_or_advertised_as_active
    group(:a, conditions: [condition(:enabled_switch, 402)])
    zone([:a])
    value = scene
    assert_empty value.send(:current_entries)
    value.send(:action_a)
    assert_equal 1, value.send(:current_entries).size
    assert_equal :inactive, value.send(:current_group).members.first.status
    assert_equal '', value.instance_variable_get(:@page).instance_variable_get(:@availability).text
  end

  def test_grid_centers_varied_dimensions_without_distortion_clipping_or_button_overlap
    group(:a, [encounter(:rattata), encounter(:pikachu), encounter(:meowstic, 1)])
    zone([:a])
    [[:rattata, 0], [:pikachu, 0], [:meowstic, 1]].each { |symbol, form| $pokedex.mark_seen(symbol, form, forced: true) }
    RPG::Cache.front_dimensions = {'0019' => [24, 32], '0025' => [96, 48], '0678_01' => [48, 96]}
    RPG::Cache.front_bounds = {'0019' => [0, 0, 24, 32], '0025' => [0, 3, 96, 45], '0678_01' => [0, 6, 48, 90]}
    cells = scene.instance_variable_get(:@page).instance_variable_get(:@cells)
    cells.first(3).each_with_index do |cell, index|
      sprite = cell[:sprite]
      assert_equal 1, sprite.zoom_x
      assert_equal 1, sprite.zoom_y
      bounds = RPG::Cache.front_bounds.values[index]
      left, top, width, height = bounds
      assert_operator sprite.x - sprite.ox + left, :>=, 8
      assert_operator sprite.x - sprite.ox + left + width, :<=, 312
      assert_operator sprite.y - sprite.oy + top, :>=, 52
      assert_operator sprite.y - sprite.oy + top + height, :<=, 192
      assert_equal 46 + index * 76, cell[:center_x]
      assert_equal 75, cell[:center_y]
    end
    cells.drop(3).each { |cell| refute cell[:sprite].visible }
  end

  def test_overview_is_sprite_only_and_pagination_clears_unused_cells
    group(:a, [encounter(:vivillon, -1)])
    zone([:a])
    value = scene
    view = value.instance_variable_get(:@page)
    assert_equal 'Vus 0/20 · Capturés 0/20', view.instance_variable_get(:@counts).text
    assert_equal 'Page 1/2', view.instance_variable_get(:@pagination).text
    assert_equal '', view.instance_variable_get(:@availability).text
    value.send(:change_page, 1)
    assert_equal 'Page 2/2', view.instance_variable_get(:@pagination).text
    cells = view.instance_variable_get(:@cells)
    assert_equal 8, cells.count { |cell| cell[:sprite].visible }
    refute $habitat_text_reads.any? { |file, _id| [0, 67].include?(file) }
  end

  def test_next_previous_change_milieu_and_up_down_wheel_change_only_grid_page
    group(:a, [encounter(:vivillon, -1)])
    group(:b, [encounter], system: :cave)
    zone(%i[a b])
    value = scene
    value.send(:action_a)
    assert_equal :a, value.send(:current_group).key
    Input.key = :DOWN
    value.send(:update_inputs)
    assert_equal 12, value.instance_variable_get(:@offset)
    assert_equal :a, value.send(:current_group).key
    Input.key = nil
    Mouse.wheel = -1
    value.send(:update_mouse, false)
    assert_equal 0, value.instance_variable_get(:@offset)
    assert_equal 0, Mouse.wheel
    value.send(:action_a)
    assert_equal :b, value.send(:current_group).key
    assert_equal 0, value.instance_variable_get(:@offset)
    value.send(:action_x)
    assert_equal :a, value.send(:current_group).key
    value.send(:action_y)
    assert_nil value.send(:current_group)
    assert_equal 0, value.instance_variable_get(:@offset)
  end

  def test_milieus_merge_times_terrains_and_priority_but_keep_tools_separate
    group(:morning, conditions: [condition(:enabled_switch, Yuki::Sw::TJN_MorningTime)])
    group(:night, conditions: [condition(:enabled_switch, Yuki::Sw::TJN_NightTime)])
    group(:cave, system: :cave, terrain: 2)
    group(:rod, system: :pond, tool: :old_rod)
    group(:masked, system: :pond, tool: :old_rod)
    zone(%i[morning night cave rod masked])
    value = scene
    view = value.instance_variable_get(:@page)
    value.send(:action_a)
    assert_match(/Herbes/, view.instance_variable_get(:@context).text)
    refute_match(/Matin|Nuit/, view.instance_variable_get(:@context).text)
    assert_equal %i[morning night], value.send(:current_group).members.map(&:key)
    assert_equal %i[inactive inactive], value.send(:current_group).members.map(&:status)
    value.send(:action_a)
    assert_match(/Grotte/, view.instance_variable_get(:@context).text)
    value.send(:action_a)
    assert_match(/Pêche.*Canne.*Lac/, view.instance_variable_get(:@context).text)
    assert_equal %i[active shadowed], value.send(:current_group).members.map(&:status)
    assert_equal '', view.instance_variable_get(:@availability).text
    value.send(:action_a)
    assert_nil value.send(:current_group)
  end

  def test_missing_question_and_corrupt_front_have_text_fallback
    group(:a)
    zone([:a])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    RPG::Cache.fail_question = RPG::Cache.raise_front = true
    cell = scene.instance_variable_get(:@page).instance_variable_get(:@cells).first
    refute cell[:sprite].visible
    assert cell[:fallback].visible
    assert_equal '?', cell[:fallback].text
    refute_empty $habitat_errors
  end

  def test_reused_known_cell_becomes_unknown_without_loading_hidden_creature
    group(:a)
    zone([:a])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    value = scene
    $pokedex.unmark_seen(:rattata)
    RPG::Cache.front_reads.clear
    $habitat_front_resolutions.clear
    value.send(:refresh_catalog, force: true)
    cell = value.instance_variable_get(:@page).instance_variable_get(:@cells).first
    assert_equal 'graphics/pokedex/pokefront/000.png', cell[:sprite].bitmap.asset
    assert_empty RPG::Cache.front_reads
    assert_empty $habitat_front_resolutions
  end

  def test_all_page_text_is_black_and_bounded_above_controls
    group(:a)
    zone([:a])
    snapshot = @catalog.snapshot
    snapshot.zone_name = 'Une zone au nom extrêmement long ' * 5
    view = UI::Dex::ZoneEncounterPage.new(nil)
    view.render(snapshot, nil, snapshot.entries, 0, 0)
    view.stack.select { |element| element.text }.each do |text|
      assert_equal [0, 0, 0, 255], text.fill_color.components
      refute text.draw_shadow
      assert_operator text.text_width(text.text), :<=, text.width
      assert_operator text.x, :>=, 0
      assert_operator text.x + text.width, :<=, 320
      assert_operator text.y, :>=, 0
      assert_operator text.y + text.height, :<=, 214
    end
    button = UI::Dex::ZoneEncounterControls::Button.new(nil, 0, :A, default_cache: :pokedex)
    assert_equal [0, 0, 0, 255], button.instance_variable_get(:@text).fill_color.components
  end

  def test_real_cave_simple_double_triple_merge_without_changing_catalog_or_data
    $habitat_database = LOCAL_DATABASE
    original_data = Marshal.dump(LOCAL_DATABASE[:groups])
    $env.zone = data_zone(:zone_22)
    PFM.game_state.game_map.map_id = 29
    raw = @catalog.snapshot
    original_snapshot = Marshal.dump(raw)
    technical = raw.groups.select { |g| %i[group_35 group_55 group_56].include?(g.key) }
    assert_equal [0, 1, 2], technical.map { |g| data_group(g.key).terrain_tag }
    assert_equal %i[simple double triple], technical.map { |g| data_group(g.key).vs_type }
    assert technical.all? { |g| g.entries.any? { |entry| entry.specie == :geodude } }
    display = UI::Dex::ZoneEncounterEnvironments.build(raw)
    cave = display.groups.find { |g| g.key == :group_35 }
    assert_equal 'Grotte', cave.label
    assert_equal 1, display.groups.count { |g| g.label == 'Grotte' }
    assert_equal technical.flat_map(&:entries).map(&:key).uniq, cave.entries.map(&:key)
    assert_equal 12, cave.entries.size
    assert_equal 1, cave.entries.count { |entry| entry.key == [:geodude, 0] }
    assert_equal 1, cave.entries.count { |entry| entry.key == [:geodude, 1] }
    assert_equal original_snapshot, Marshal.dump(raw)
    assert_equal original_data, Marshal.dump(LOCAL_DATABASE[:groups])
    value = scene
    value.send(:action_a)
    assert_equal 12, value.send(:current_entries).size
    value.send(:action_a)
    assert_equal :group_38, value.send(:current_group).key
    value.send(:action_x)
    assert_equal :group_35, value.send(:current_group).key
    value.send(:action_y)
    assert_nil value.send(:current_group)
  end

  def test_environment_union_adds_unique_entries_and_counts_each_form_once
    group(:a, [encounter, encounter(:rattata, 1)], system: :cave)
    group(:b, [encounter, encounter(:pikachu)], system: :cave, terrain: 1)
    group(:c, [encounter(:rattata, 1), encounter(:meowstic, 1)], system: :cave, terrain: 2)
    zone(%i[a b c])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    $pokedex.mark_captured(:meowstic, 1)
    value = scene
    view = value.instance_variable_get(:@page)
    assert_equal 'Vus 2/4 · Capturés 1/4', view.instance_variable_get(:@counts).text
    value.send(:action_a)
    assert_equal [[:rattata, 0], [:rattata, 1], [:pikachu, 0], [:meowstic, 1]], value.send(:current_entries).map(&:key)
    assert_equal 'Vus 2/4 · Capturés 1/4', view.instance_variable_get(:@counts).text
    cells = view.instance_variable_get(:@cells)
    refute cells[0][:badge].visible
    assert_equal 'graphics/pokedex/pokefront/000.png', cells[1][:sprite].bitmap.asset
    refute cells[1][:badge].visible
    assert_equal 'graphics/pokedex/pokefront/0678_01.png', cells[3][:sprite].bitmap.asset
    assert cells[3][:badge].visible
    value.send(:action_a)
    assert_nil value.send(:current_group)
  end

  def test_real_grass_simple_double_triple_merge_like_cave
    $habitat_database = LOCAL_DATABASE
    original_data = Marshal.dump(LOCAL_DATABASE[:groups])
    $env.zone = data_zone(:zone_32)
    PFM.game_state.game_map.map_id = 36
    raw = @catalog.snapshot
    original_snapshot = Marshal.dump(raw)
    technical = raw.groups.select { |g| %i[group_39 group_32 group_46].include?(g.key) }
    assert_equal [0, 1, 2], technical.map { |g| data_group(g.key).terrain_tag }
    assert_equal %i[simple double triple], technical.map { |g| data_group(g.key).vs_type }
    assert technical.all? { |g| g.entries.any? { |entry| entry.key == [:wurmple, 0] } }
    display = UI::Dex::ZoneEncounterEnvironments.build(raw)
    grass = display.groups.find { |g| g.key == :group_39 }
    assert_equal 'Herbes', grass.label
    assert_equal 1, display.groups.count { |g| g.label == 'Herbes' }
    assert_equal technical.flat_map(&:entries).map(&:key).uniq, grass.entries.map(&:key)
    assert_equal 35, grass.entries.size
    assert_equal 1, grass.entries.count { |entry| entry.key == [:wurmple, 0] }
    assert_equal 20, grass.entries.count { |entry| entry.specie == :vivillon }
    assert_includes grass.entries.map(&:key), [:venipede, 0] # Only in double/triple groups.
    assert_equal original_snapshot, Marshal.dump(raw)
    assert_equal original_data, Marshal.dump(LOCAL_DATABASE[:groups])
    value = scene
    value.send(:action_a)
    assert_equal :group_39, value.send(:current_group).key
    assert_equal 35, value.send(:current_entries).size
    value.send(:change_page, 1)
    assert_equal 12, value.instance_variable_get(:@offset)
    value.send(:action_a)
    assert_equal :group_31, value.send(:current_group).key
    value.send(:action_x)
    assert_equal :group_39, value.send(:current_group).key
    value.send(:action_y)
    assert_nil value.send(:current_group)
  end

  def test_technical_variants_merge_for_every_project_environment_without_using_labels
    used = LOCAL_DATABASE[:zones].values.flat_map(&:wild_groups).uniq
    contexts = used.filter_map do |key|
      data = LOCAL_DATABASE[:groups][key]
      [data.system_tag, data.tool] if data && data.db_symbol == key
    end.uniq
    assert_equal 13, contexts.size
    # Also prove that the translation table is not a classification whitelist.
    (contexts + [[:future_habitat, nil]]).each do |system, tool|
      contents = [[encounter, encounter(:rattata, 1)], [encounter, encounter(:pikachu)],
                  [encounter(:rattata, 1), encounter(:meowstic, 1)]]
      %i[simple double triple].each_with_index do |format, terrain|
        data = group("technical_#{terrain}".to_sym, contents[terrain], system: system, terrain: terrain, tool: tool)
        data.instance_variable_set(:@vs_type, format)
      end
      zone(%i[technical_0 technical_1 technical_2])
      raw = @catalog.snapshot
      raw.groups.each_with_index { |g, i| g.label = "Unrelated label #{i}" }
      before = Marshal.dump(raw)
      display = UI::Dex::ZoneEncounterEnvironments.build(raw)
      assert_equal 1, display.groups.size, [system, tool].inspect
      assert_equal [[:rattata, 0], [:rattata, 1], [:pikachu, 0], [:meowstic, 1]], display.groups.first.entries.map(&:key)
      assert_equal before, Marshal.dump(raw)
    end
  end

  def test_environment_grouping_preserves_conditions_tools_systems_and_status
    group(:a, system: :cave)
    group(:technical, system: :cave, terrain: 1)
    group(:masked, system: :cave)
    group(:night, conditions: [condition(:enabled_switch, 12)], system: :cave)
    group(:lake, system: :pond)
    group(:surf, system: :ocean)
    group(:rod, system: :pond, tool: :old_rod)
    group(:good_rod, system: :pond, tool: :good_rod)
    zone(%i[a technical masked night lake surf rod good_rod])
    display = UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot)
    assert_equal %i[a lake surf rod good_rod], display.groups.map(&:key)
    assert_equal %i[mixed active active active active], display.groups.map(&:status)
    assert_equal %i[active active shadowed inactive], display.groups.first.members.map(&:status)
    assert_equal [[:rattata, 0]], display.entries.map(&:key)
  end

  def test_full_three_rows_keep_native_scale_and_clear_badges_on_next_page
    group(:a, [encounter(:vivillon, -1)])
    zone([:a])
    12.times { |form| $pokedex.mark_captured(:vivillon, form) }
    value = scene
    cells = value.instance_variable_get(:@page).instance_variable_get(:@cells)
    assert_equal 12, cells.count { |cell| cell[:sprite].visible }
    assert_equal [75, 121, 167], cells.map { |cell| cell[:center_y] }.uniq
    cells.each do |cell|
      sprite = cell[:sprite]
      assert_equal [1, 1], [sprite.zoom_x, sprite.zoom_y]
      assert cell[:badge].visible
      assert_operator cell[:badge].z, :>, sprite.z
      assert_operator cell[:badge].y + 16, :<=, 192
    end
    value.send(:change_page, 1)
    assert_equal 8, cells.count { |cell| cell[:sprite].visible }
    assert cells.none? { |cell| cell[:badge].visible }
    assert_equal 'Vus 12/20 · Capturés 12/20', value.instance_variable_get(:@page).instance_variable_get(:@counts).text
  end

  def test_all_fifteen_time_combinations_follow_family_majority_after_union
    # Bits are Matin=1, Jour=2, Soir=4, Nuit=8. Four periods means BOTH.
    expected = {
      1 => %w[daytime], 2 => %w[daytime], 3 => %w[daytime], 4 => %w[nighttime],
      5 => %w[daytime nighttime], 6 => %w[daytime nighttime], 7 => %w[daytime],
      8 => %w[nighttime], 9 => %w[daytime nighttime], 10 => %w[daytime nighttime],
      11 => %w[daytime], 12 => %w[nighttime], 13 => %w[nighttime],
      14 => %w[nighttime], 15 => %w[daytime nighttime]
    }
    expected.each do |mask, icons|
      keys = []
      [13, 11, 14, 12].each_with_index do |switch, index|
        next if mask[index].zero?
        key = "period_#{index}".to_sym
        group(key, [encounter, encounter], conditions: [condition(:map_id, 10000), condition(:enabled_switch, switch)], terrain: index)
        keys << key
      end
      zone(keys)
      original_switches = Marshal.dump(PFM.game_state.game_switches)
      display = UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot)
      assert_equal 1, display.groups.size
      assert_equal [[:rattata, 0]], display.groups.first.entries.map(&:key)
      assert_equal mask, display.groups.first.periods[[:rattata, 0]]
      assert_equal icons, UI::Dex::ZoneEncounterPeriods.icons(mask)
      assert_equal original_switches, Marshal.dump(PFM.game_state.game_switches)
    end
    assert_empty UI::Dex::ZoneEncounterPeriods.icons(0)
  end

  def test_duplicate_groups_do_not_weight_majority_and_non_time_conditions_are_not_hours
    3.times { |i| group("day#{i}".to_sym, conditions: [condition(:enabled_switch, 13)], terrain: i) }
    group(:night, conditions: [condition(:enabled_switch, 12)])
    zone(%i[day0 day1 day2 night])
    display = UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot)
    assert_equal 9, display.groups.first.periods[[:rattata, 0]]
    assert_equal %w[daytime nighttime], UI::Dex::ZoneEncounterPeriods.icons(display.groups.first.periods[[:rattata, 0]])
    plain = group(:story, conditions: [condition(:map_id, 11), condition(:enabled_switch, 402)])
    assert_equal 15, UI::Dex::ZoneEncounterPeriods.for_group(plain)
    timed = group(:story_time, conditions: [condition(:map_id, 11), condition(:enabled_switch, 402), condition(:enabled_switch, 14)])
    assert_equal 4, UI::Dex::ZoneEncounterPeriods.for_group(timed)
    alternative = group(:alternative, conditions: [condition(:enabled_switch, 13), condition(:enabled_switch, 12, :OR)])
    assert_equal 9, UI::Dex::ZoneEncounterPeriods.for_group(alternative)
    zone(%i[day0 story])
    assert_equal 15, UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot).groups.first.periods[[:rattata, 0]]
  end

  def test_unknown_seen_caught_and_ensemble_indicators_and_reused_cells
    group(:a, [encounter(:rattata, 0), encounter(:rattata, 1)], conditions: [condition(:enabled_switch, 13)])
    zone([:a])
    PFM.game_state.game_switches[13] = true
    value = scene
    view = value.instance_variable_get(:@page)
    cells = view.instance_variable_get(:@cells)
    assert view.instance_variable_get(:@legend_icons).all?(&:visible)
    assert cells.none? { |c| c.key?(:times) }
    RPG::Cache.time_reads.clear
    value.send(:action_a)
    assert_empty RPG::Cache.time_reads # Collective banner reuses the legend texture.
    assert_equal 1, view.instance_variable_get(:@bands).count { |b| b[:background].visible }
    refute cells[0][:badge].visible
    assert_equal 'graphics/pokedex/pokefront/000.png', cells[0][:sprite].bitmap.asset
    assert view.instance_variable_get(:@legend_icons).none?(&:visible)
    $pokedex.mark_seen(:rattata, 0, forced: true)
    value.send(:refresh_catalog, force: true)
    assert_equal 1, view.instance_variable_get(:@bands).count { |b| b[:icon].visible }
    refute cells[0][:badge].visible
    assert_equal 'graphics/pokedex/pokefront/000.png', cells[1][:sprite].bitmap.asset
    $pokedex.mark_captured(:rattata, 0)
    value.send(:refresh_catalog, force: true)
    assert cells[0][:badge].visible
    assert_equal 0.75, cells[0][:badge].zoom_x
    assert_equal 1, cells[0][:sprite].zoom_x
    assert_equal 'Vus 1/2 · Capturés 1/2', view.instance_variable_get(:@counts).text
    value.send(:action_y)
    assert cells[0][:badge].visible
    assert view.instance_variable_get(:@bands).none? { |b| b[:icon].visible }
    group(:a, [encounter(:pikachu)])
    value.send(:refresh_catalog, force: true)
    value.send(:action_a)
    assert view.instance_variable_get(:@bands).none? { |b| b[:icon].visible }
    refute cells[0][:badge].visible
  end

  def test_real_map_and_time_variants_now_merge_into_one_environment
    $habitat_database = LOCAL_DATABASE
    $env.zone = data_zone(:zone_25)
    PFM.game_state.game_map.map_id = 35
    raw = @catalog.snapshot
    before = Marshal.dump(raw)
    display = UI::Dex::ZoneEncounterEnvironments.build(raw)
    grass = display.groups.find { |g| data_group(g.key).system_tag == :grass }
    assert_equal %i[group_36 group_33 group_34], grass.members.map(&:key)
    assert_equal 21, grass.entries.size
    assert_equal 1, display.groups.count { |g| g.label == 'Herbes' }
    assert_equal before, Marshal.dump(raw)
    $env.zone = data_zone(:zone_20)
    PFM.game_state.game_map.map_id = 27
    grass = UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot).groups.find { |g| g.label == 'Herbes' }
    assert_equal 7, grass.periods[[:rattata, 0]]
    assert_equal 14, grass.periods[[:rattata, 1]]
    assert_equal %w[daytime], UI::Dex::ZoneEncounterPeriods.icons(grass.periods[[:rattata, 0]])
    assert_equal %w[nighttime], UI::Dex::ZoneEncounterPeriods.icons(grass.periods[[:rattata, 1]])
  end

  def test_legend_uses_native_tjn_lookup_including_tone_only_fallback_and_live_changes
    group(:a)
    zone([:a])
    PFM.game_state.tint_time_set = :platinum_daynight
    assert_equal [22, 19, 11, 7], UI::Dex::ZoneEncounterPeriods.schedule
    value = scene
    view = value.instance_variable_get(:@page)
    assert_equal ['Matin/Jour 07h–11h–19h', 'Soir/Nuit 19h–22h–07h'], view.instance_variable_get(:@legend_texts).map(&:text)
    {winter: [17, 16, 12, 10], fall: [19, 17, 11, 9], spring: [19, 17, 11, 9], summer: [22, 19, 11, 7]}.each do |key, hours|
      PFM.game_state.tint_time_set = key
      assert_equal hours, UI::Dex::ZoneEncounterPeriods.schedule
    end
    PFM.game_state.tint_time_set = :winter
    value.instance_variable_set(:@last_refresh, 0)
    value.send(:refresh_catalog) # Same encounter snapshot, different time set.
    assert_equal ['Matin/Jour 10h–12h–16h', 'Soir/Nuit 16h–17h–10h'], view.instance_variable_get(:@legend_texts).map(&:text)
  end

  def test_zone_opens_with_native_private_tjn_schedule_and_reads_public_configuration_only
    assert Yuki::TJN.singleton_class.private_method_defined?(:current_time_set)
    refute Yuki::TJN.respond_to?(:current_time_set)
    assert_raises(NoMethodError) { Yuki::TJN.public_send(:current_time_set) }
    assert_equal %i[current_tone force_update_tone init_variables update update_timed_events], Yuki::TJN.singleton_class.public_instance_methods(false).sort
    original_sets = Marshal.dump(Yuki::TJN::TIME_SETS)
    original_default = Yuki::TJN::TIME.dup
    group(:a)
    zone([:a])
    [nil, :default, :winter, :fall, :spring, :summer, :platinum_daynight, :unknown_setting].each do |key|
      PFM.game_state.tint_time_set = key
      expected = Yuki::TJN::TIME_SETS[key] || Yuki::TJN::TIME
      value = scene # Reproduce create_graphics -> refresh_catalog -> schedule.
      assert_instance_of UI::Dex::ZoneEncounterPage, value.instance_variable_get(:@page)
      assert_equal expected, UI::Dex::ZoneEncounterPeriods.schedule
      refute_same expected, UI::Dex::ZoneEncounterPeriods.schedule
      UI::Dex::ZoneEncounterPeriods.schedule[0] = -1
    end
    assert_equal original_sets, Marshal.dump(Yuki::TJN::TIME_SETS)
    assert_equal original_default, Yuki::TJN::TIME
    assert Yuki::TJN.singleton_class.private_method_defined?(:current_time_set)
  end

  def test_category_order_is_stable_after_aggregation_and_before_pagination
    expected = {15 => :all, 1 => :day, 2 => :day, 3 => :day, 7 => :day, 11 => :day,
                4 => :night, 8 => :night, 12 => :night, 13 => :night, 14 => :night}
    expected.each { |mask, category| assert_equal category, UI::Dex::ZoneEncounterPeriods.category(mask) }
    group(:night, [encounter(:rattata, 1), encounter(:meowstic, 1)], conditions: [condition(:enabled_switch, 12)])
    group(:day, [encounter(:pikachu), encounter(:rattata)], conditions: [condition(:enabled_switch, 11)])
    group(:all, [encounter(:onix), encounter(:bulbasaur)])
    zone(%i[night day all])
    display = UI::Dex::ZoneEncounterEnvironments.build(@catalog.snapshot)
    assert_equal [[:onix, 0], [:bulbasaur, 0], [:pikachu, 0], [:rattata, 0], [:rattata, 1], [:meowstic, 1]], display.groups.first.entries.map(&:key)
    assert_equal 6, display.groups.first.entries.size
  end

  def layout_entries(count)
    Array.new(count) { |i| ElementZ::Habitat::Entry.new(specie: :vivillon, form: i, seen: false, caught: false, habitats: []) }
  end

  def test_three_rows_and_two_bands_fit_when_silhouettes_allow_it
    entries = layout_entries(12)
    periods = entries.each_with_index.to_h { |e, i| [e.key, [15, 3, 12][i / 4]] }
    pages = UI::Dex::ZoneEncounterLayout.pages(entries, periods) { 30 }
    assert_equal 1, pages.size
    assert_equal 12, pages.first[:slots].size
    assert_equal %i[day night], pages.first[:bands].map { |b| b[:category] }
    assert_equal 3, pages.first[:slots].map { |slot| slot[:cy] }.uniq.size
    pages.first[:slots].each do |slot|
      pages.first[:bands].each { |band| assert slot[:bottom] <= band[:y] || slot[:top] >= band[:y] + 18 }
      assert_operator slot[:bottom], :<=, 192
    end
  end

  def test_pagination_keeps_order_and_repeats_only_continuing_category_header
    entries = layout_entries(28)
    periods = entries.each_with_index.to_h { |e, i| [e.key, i < 4 ? 15 : (i < 24 ? 3 : 12)] }
    pages = UI::Dex::ZoneEncounterLayout.pages(entries, periods) { 44 }
    assert_equal [12, 12, 4], pages.map { |p| p[:count] }
    assert_equal [0, 12, 24], pages.map { |p| p[:offset] }
    assert_equal entries, pages.flat_map { |p| p[:slots].map { |s| s[:entry] } }
    assert_equal [[:day], [:day], [:night]], pages.map { |p| p[:bands].map { |b| b[:category] } }
    assert_equal 32, pages[1][:bands].first[:y]
    assert_equal 32, pages[2][:bands].first[:y]
  end

  def test_band_is_deferred_with_its_creatures_when_vertical_space_runs_out
    entries = layout_entries(12)
    periods = entries.each_with_index.to_h { |e, i| [e.key, i < 8 ? 15 : 3] }
    pages = UI::Dex::ZoneEncounterLayout.pages(entries, periods) { 74 }
    assert_equal [8, 4], pages.map { |p| p[:count] }
    assert_empty pages.first[:bands]
    assert_equal :day, pages.last[:bands].first[:category]
    assert_equal entries.last(4), pages.last[:slots].map { |s| s[:entry] }
  end

  def test_scene_navigation_uses_variable_page_sizes_and_preserves_environment
    all = %i[wailord onix steelix gyarados dragonite charizard venusaur blastoise]
    day = %i[bulbasaur caterpie weedle pichu]
    group(:all, all.map { |symbol| encounter(symbol) })
    group(:day, day.map { |symbol| encounter(symbol) }, conditions: [condition(:enabled_switch, 11)])
    zone(%i[all day])
    (all + day).each { |symbol| $pokedex.mark_captured(symbol, 0) }
    value = scene
    value.send(:action_a)
    assert_equal [8, 4], value.instance_variable_get(:@pages).map { |page| page[:count] }
    view = value.instance_variable_get(:@page)
    assert_equal 'Vus 12/12 · Capturés 12/12', view.instance_variable_get(:@counts).text
    value.send(:change_page, 1)
    assert_equal 8, value.instance_variable_get(:@offset)
    assert_equal :all, value.send(:current_group).key
    assert_equal 'Page 2/2', view.instance_variable_get(:@pagination).text
    assert_equal 'MATIN / JOUR', view.instance_variable_get(:@bands).first[:label].text
    assert view.instance_variable_get(:@bands).first[:background].visible
    value.send(:change_page, -1)
    assert_equal 0, value.instance_variable_get(:@offset)
    refute view.instance_variable_get(:@bands).first[:background].visible
    value.send(:action_y)
    assert_nil value.send(:current_group)
    assert_equal 0, value.instance_variable_get(:@offset)
  end

  def test_badges_follow_visible_upper_right_and_only_unknown_front_is_scaled
    group(:a, [encounter(:bulbasaur), encounter(:meowstic, 1), encounter(:onix), encounter(:pikachu)])
    zone([:a])
    [[:bulbasaur, 0], [:meowstic, 1], [:onix, 0]].each { |symbol, form| $pokedex.mark_captured(symbol, form) }
    RPG::Cache.front_bounds = {'0001' => [28, 63, 35, 33], '0678_01' => [23, 38, 50, 58], '0095' => [1, 6, 94, 90]}
    cells = scene.instance_variable_get(:@page).instance_variable_get(:@cells)
    cells.first(3).each do |cell|
      sprite, badge = cell.values_at(:sprite, :badge)
      assert_equal [1, 1], [sprite.zoom_x, sprite.zoom_y]
      assert_equal [12, 12], [badge.bitmap.width * badge.zoom_x, badge.bitmap.height * badge.zoom_y]
      assert badge.visible
      assert_operator badge.x, :>, sprite.x
      assert_operator badge.y, :<=, sprite.y
      assert_operator sprite.y - badge.y, :<=, 4
    end
    assert_equal 0.83, cells[3][:sprite].zoom_x
    assert_equal 0.83, cells[3][:sprite].zoom_y
    refute cells[3][:badge].visible
    assert_empty $habitat_front_resolutions.select { |args| args.first == :pikachu }
  end

  def test_actual_dex_initializer_and_two_method_extension_preserve_other_actions
    value = GamePlay::Dex.new($pokedex)
    assert_equal 0, value.instance_variable_get(:@state)
    assert_instance_of GamePlay::Dex::Presenter, value.instance_variable_get(:@presenter)
    assert_equal 'Zone', value.send(:button_texts)[0][1]
    assert_equal GamePlay::Dex, value.method(:initialize).owner
    assert_equal GamePlay::Dex, value.method(:change_state).owner
    assert_equal GamePlay::Dex, value.method(:action_y).owner
    value.send(:action_x)
    assert_instance_of GamePlay::ZoneEncounters, value.called_scene
    value.instance_variable_set(:@state, GamePlay::Dex::STATE_INFO)
    value.define_singleton_method(:cycle_creature_form) { @form_cycle_called = true }
    value.send(:action_x)
    assert value.instance_variable_get(:@form_cycle_called)
    map = OpenStruct.new
    def map.on_toggle_zoom; self.zoom_called = true; end
    value.instance_variable_set(:@state, GamePlay::Dex::STATE_WORLDMAP)
    value.instance_variable_set(:@pokemon_worldmap, map)
    value.send(:action_x)
    assert map.zoom_called
    assert_equal GamePlay::DexInfo, GamePlay.dex_info_class
  end

  def test_real_project_database_all_zones_times_and_forms
    $habitat_database = LOCAL_DATABASE
    all_issues = []
    each_data_zone.each do |area|
      next if area.db_symbol == :__undef__
      $env.zone = area
      area.maps.each do |map_id|
        PFM.game_state.game_map.map_id = map_id
        [11, 12, 13, 14].each do |time_switch|
          [11, 12, 13, 14].each { |other| PFM.game_state.game_switches[other] = time_switch == other }
          result = @catalog.snapshot
          assert_equal area.db_symbol, result.zone_key
          assert_equal result.entries.map(&:key).uniq, result.entries.map(&:key)
          all_issues.concat(result.issues)
          all_issues.concat(result.groups.flat_map(&:issues))
        end
      end
    end
    assert_empty all_issues.uniq, all_issues.uniq.join('; ')
  end

  def test_studio_json_matches_compiled_zone_and_group_configuration
    skip 'psdk.dat absent: compiled cache comparison cannot run; other tests use real JSON models.' if DATABASE_SOURCE != :compiled
    # Detect stale compiled data: the game reads psdk.dat, not JSON directly.
    require File.join(ENGINE, 'tools/Studio2PSDK')
    Dir[File.join(PROJECT, 'Data/Studio/groups/*.json')].each do |filename|
      json = JSON.parse(File.read(filename, encoding: 'UTF-8'))
      compiled = LOCAL_DATABASE[:groups][json['dbSymbol'].to_sym]
      refute_nil compiled, filename
      assert_equal json['encounters'].map { |e| [e['specie'].to_sym, e['form']] }, compiled.encounters.map { |e| [e.specie, e.form] }, filename
      assert_equal json['customConditions'].map { |c| [c['value'], c['relationWithPreviousCondition'].to_sym] }, compiled.custom_conditions.map { |c| [c.value, c.relation_with_previous_condition] }, filename
    end
    Dir[File.join(PROJECT, 'Data/Studio/zones/*.json')].each do |filename|
      json = JSON.parse(File.read(filename, encoding: 'UTF-8'))
      compiled = LOCAL_DATABASE[:zones][json['dbSymbol'].to_sym]
      assert_equal json['wildGroups'].map(&:to_sym), compiled.wild_groups, filename
      assert_equal json['maps'], compiled.maps, filename
    end
  end

  def test_archive_is_inert_and_original_resources_are_preserved
    require File.join(ENGINE, 'tools/PluginManager')
    read = lambda do |filename|
      raw = File.binread(File.join(SCRIPTS, filename))
      index = Marshal.load(raw.byteslice(raw.unpack1('L')..-1))
      index.transform_values { |pos| raw.byteslice(pos + 4, raw.byteslice(pos, 4).unpack1('L')) }
    end
    current = read.call('HabitatList.psdkplug')
    original = read.call('HabitatList.psdkplug.disabled')
    script = 'scripts/54000 Dex_Zones.rb'
    assert current[script].lines.all? { |line| line.start_with?('#') || line.strip.empty? }
    assert_equal original.reject { |key, _| [script, "\x00"].include?(key) }, current.reject { |key, _| [script, "\x00"].include?(key) }
    legacy = File.read(File.join(SCRIPTS, '00015 HabitatList/54000 Dex_Zones.rb'))
    assert legacy.lines.all? { |line| line.lstrip.start_with?('#') || line.strip.empty? }
  end
end
