require_relative 'support'
require 'json'
require 'digest'

HabitatMap = Struct.new(:map_id)
HabitatPlayer = Struct.new(:system_tag_db_symbol, :terrain_tag, :front_system_tag_db_symbol, :front_terrain_tag)
HabitatEnvironment = Struct.new(:zone) do
  def get_current_zone_data; zone; end
  def can_fish?; true; end
end
HabitatState = Struct.new(:game_switches, :game_variables, :game_map, :game_player, :env, :pokedex)

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
    row = view.instance_variable_get(:@rows).first
    assert_equal '?', row[:name].text
    refute row[:icon].visible
    assert_empty RPG::Cache.icon_reads
    refute $habitat_text_reads.any? { |file, _id| [0, 67].include?(file) }
  end

  def test_live_scene_refresh_reveals_seen_then_caught_and_follows_zone
    group(:a)
    zone([:a])
    value = scene
    $pokedex.mark_seen(:rattata, 0, forced: true)
    value.send(:refresh_catalog, force: true)
    row = value.instance_variable_get(:@page).instance_variable_get(:@rows).first
    assert_equal 'Vu', row[:status].text
    assert row[:icon].visible
    $pokedex.mark_captured(:rattata, 0)
    value.send(:refresh_catalog, force: true)
    assert_equal 'Capturé', row[:status].text
    zone([], key: :new, maps: [10001])
    PFM.game_state.game_map.map_id = 10001
    value.send(:refresh_catalog, force: true)
    refute row[:name].visible
  end

  def test_missing_icon_keeps_revealed_name_and_scene_usable
    group(:a)
    zone([:a])
    $pokedex.mark_seen(:rattata, 0, forced: true)
    RPG::Cache.fail_icon = true
    value = scene
    row = value.instance_variable_get(:@page).instance_variable_get(:@rows).first
    refute_equal '?', row[:name].text
    refute row[:icon].visible
    value.send(:action_b)
    refute value.instance_variable_get(:@running)
  end

  def test_fixed_meowstic_forms_are_rendered_without_random_generation
    group(:a, [encounter(:meowstic, 0), encounter(:meowstic, 1)])
    zone([:a])
    [0, 1].each { |form| $pokedex.mark_seen(:meowstic, form, forced: true) }
    value = scene
    rows = value.instance_variable_get(:@page).instance_variable_get(:@rows)
    assert_match(/^F0/, rows[0][:detail].text)
    assert_match(/^F1/, rows[1][:detail].text)
    assert_equal [0, 1].map { |form| PFM::Pokemon.icon_filename(:meowstic, form, false, false, false) }, RPG::Cache.icon_reads
  end

  def test_more_than_twelve_entries_and_empty_navigation
    group(:a, [encounter(:vivillon, -1)])
    zone([:a])
    value = scene
    assert_operator value.send(:current_entries).size, :>, 12
    value.send(:change_page, 1)
    assert_equal 5, value.instance_variable_get(:@offset)
    value.send(:change_page, 1)
    assert_equal 10, value.instance_variable_get(:@offset)
    zone([])
    value.send(:refresh_catalog, force: true)
    value.send(:change_group, 1)
    value.send(:change_page, 1)
    assert_equal 0, value.instance_variable_get(:@offset)
  end

  def test_inactive_group_has_explicit_label_and_is_not_in_overview
    group(:a, conditions: [condition(:enabled_switch, 402)])
    zone([:a])
    value = scene
    assert_empty value.send(:current_entries)
    value.send(:action_a)
    assert_equal 1, value.send(:current_entries).size
    assert_match(/Inactif/, value.instance_variable_get(:@page).instance_variable_get(:@availability).text)
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
