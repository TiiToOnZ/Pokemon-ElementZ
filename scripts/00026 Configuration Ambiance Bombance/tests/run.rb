# frozen_string_literal: true
require 'minitest/autorun'
require 'minitest/mock'
require_relative 'support'

class CloudContinuityTest < Minitest::Test
  def setup
    reset_fixture
  end

  def state; BombanceAmbiance.manager.state; end
  def fog; $scene.spriteset.fog; end
  def draw; $scene.spriteset.send(:update_sprites); end
  def tick(n = 1); n.times { $game_map.update }; draw; end

  def linked_transfer(target_id, x, y)
    link = Yuki::MapLinker.map_datas.find { |data| data.map_id == target_id }
    refute_nil link
    $game_player.moveto(x, y)
    draw
    old_x, old_y = fog.ox, fog.oy
    next_x, next_y = x + link.offset_x, y + link.offset_y
    phase_x, phase_y = state.phase_x, state.phase_y
    plane_id = fog.object_id
    transfer(target_id, next_x, next_y)
    # The native transfer intentionally contains one Game_Map#update. Its exact
    # displacement is the only accepted change when the camera keeps its framing.
    assert_in_delta old_x + state.phase_x - phase_x, fog.ox, 1e-9
    assert_in_delta old_y + state.phase_y - phase_y, fog.oy, 1e-9
    assert_equal plane_id, fog.object_id
    refute fog.disposed?
  end

  def test_original_single_map_render_and_update_frequency
    plane = fog
    context = BombanceAmbiance.manager.context
    130.times do |i|
      tick
      $game_map.display_x = i * 3 - 101
      $game_map.display_y = i * 5 - 21
      NATIVE_FOG.bind($scene.spriteset).call
      expected = [fog.ox, fog.oy, fog.zoom, fog.opacity, fog.blend_type, fog.tone, fog.z, fog.texture]
      draw
      assert_equal expected, [fog.ox, fog.oy, fog.zoom, fog.opacity, fog.blend_type, fog.tone, fog.z, fog.texture]
    end
    assert_in_delta(-130 * 2 / 8.0, state.phase_x)
    assert_in_delta(-130 / 8.0, state.phase_y)
    assert_same plane, fog
    assert_same context, BombanceAmbiance.manager.context
    assert_equal 0.5, fog.zoom
    assert_equal 90, fog.opacity
  end

  def test_route_to_bourg_and_back_while_moving
    tick(173)
    linked_transfer(23, 31, $game_map.height)
    tick(47)
    linked_transfer(27, 20, -1)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
  end

  def test_bourg_to_route_from_a_fresh_bourg_session
    reset_fixture(23)
    tick(81)
    linked_transfer(27, 20, -1)
  end

  def test_route_to_cocovin_and_back
    tick(201)
    linked_transfer(25, 12, -1)
    tick(21)
    linked_transfer(27, 25, $game_map.height)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
  end

  def test_cocovin_to_route_from_a_fresh_cocovin_session
    reset_fixture(25)
    tick(34)
    linked_transfer(27, 25, $game_map.height)
  end

  def test_many_successive_transfers_no_drift_or_new_planes
    initial_plane = fog
    25.times do
      linked_transfer(25, 12, -1)
      tick(3)
      linked_transfer(28, 50, -1)
      linked_transfer(25, 12, $game_map.height)
      linked_transfer(27, 25, $game_map.height)
      linked_transfer(23, 31, $game_map.height)
      linked_transfer(27, 20, -1)
      assert_equal [0, 0], [state.anchor_x, state.anchor_y]
    end
    assert_same initial_plane, fog
  end

  def test_border_camera_and_fractional_native_camera_coordinate
    tick(50)
    # Clamped/stationary camera at a border: the world feature must stay in place,
    # even if its screen position changes with a native camera recentering.
    $game_map.display_x = 0
    $game_map.display_y = ($game_map.height - 15) * 128 + 3
    draw
    phase = state.phase_y
    link = Yuki::MapLinker.map_datas.find { |v| v.map_id == 23 }
    offset_y = link.offset_y
    source_origin = fog.oy
    source_camera = $game_map.display_y / 4
    transfer(23, 8, 0)
    expected_camera_change = $game_map.display_y / 4 - offset_y * 32 - source_camera
    assert_in_delta source_origin + expected_camera_change + state.phase_y - phase, fog.oy, 1e-9
    tick(8)
    assert_in_delta(-59 / 8.0, state.phase_y)
  end

  def test_interior_freezes_phase_and_native_plane_is_empty
    tick(45)
    phases = [state.phase_x, state.phase_y]
    old_texture = fog.texture
    transfer(30, 10, 10) # real cloud-free tileset
    assert_nil fog.texture
    assert old_texture.disposed?
    tick(120)
    assert_equal phases, [state.phase_x, state.phase_y]
    transfer(27, 20, 20)
    assert_in_delta phases[0] - 0.25, state.phase_x
    assert_in_delta phases[1] - 0.125, state.phase_y
    refute_nil fog.texture
  end

  def test_distant_teleport_preserves_time_not_screen_origin
    tick(30)
    phase = state.phase_x
    old_x = fog.ox
    transfer(71, 40, 40)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
    assert_in_delta phase - 0.25, state.phase_x
    refute_equal old_x, fog.ox
    assert_in_delta $game_map.display_x / 4 + state.phase_x, fog.ox
    transfer(27, 20, 20)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
    assert_in_delta phase - 0.5, state.phase_x
  end

  def test_menu_redraw_without_logic_does_not_advance_or_catch_up
    tick(13)
    before = [fog.ox, fog.oy, state.phase_x, state.phase_y]
    200.times { draw }
    assert_equal before, [fog.ox, fog.oy, state.phase_x, state.phase_y]
    tick
    assert_in_delta before[2] - 0.25, state.phase_x
  end

  def test_load_hook_resets_session_even_with_stale_maplinker_data
    tick(30)
    old = state
    # Real callback used by GameState#expand_global_var. The loaded map still has
    # an id and saved native offsets; MapLinker still belongs to the previous game.
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(:bombance_ambiance_session).call
    $game_map.setup(25)
    draw
    refute_same old, state
    assert_equal [0.0, 0.0, 0, 0], [state.phase_x, state.phase_y, state.anchor_x, state.anchor_y]
    assert_empty $game_map.instance_variables.grep(/ambiance/)
  end

  def test_other_fog_unchanged_and_no_double_ownership
    transfer(35, 20, 20) # real forest fog
    assert_equal 'eterna-forest-style-fog2', $game_map.fog_name
    plane = fog
    before_phase = state.phase_x
    tick(18)
    patched = [fog.ox, fog.oy, fog.zoom, fog.opacity, fog.blend_type]
    NATIVE_FOG.bind($scene.spriteset).call
    assert_equal patched, [fog.ox, fog.oy, fog.zoom, fog.opacity, fog.blend_type]
    assert_equal before_phase, state.phase_x
    assert_same plane, fog
    $scene.spriteset.dispose
    assert plane.disposed?
    numeric_tree = lambda do |value|
      case value
      when Numeric then true
      when Array then value.all? { |v| numeric_tree.call(v) }
      when Hash then value.all? { |k, v| numeric_tree.call(k) && numeric_tree.call(v) }
      else false
      end
    end
    assert state.instance_variables.all? { |key| numeric_tree.call(state.instance_variable_get(key)) }
  end

  def test_native_speed_change_and_other_texture_do_not_pollute_phase
    tick(8)
    $game_map.fog_sx = 6
    tick(8)
    assert_in_delta(-8.0, state.phase_x)
    $game_map.fog_name = 'rising_smoke_3'
    tick(70)
    assert_in_delta(-8.0, state.phase_x)
    $game_map.fog_name = 'clouds'
    tick
    assert_in_delta(-8.75, state.phase_x)
  end

  def test_maplinker_disabled_does_not_use_old_neighbor_offsets
    tick(5)
    $game_switches[Yuki::Sw::MapLinkerDisabled] = true
    transfer(23, 10, 10)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
  end

  def test_configuration_priority_and_context_are_read_only
    rules = BombanceAmbiance::Configuration.resolve(27, nil,
      groups: { routes: { maps: [27, 28], effects: { clouds: true } } },
      maps: { 27 => { clouds: false } })
    assert_equal false, rules[:clouds]
    $env.current_weather_db_symbol = :fog
    $game_switches[Yuki::Sw::TJN_DayTime] = false
    $game_switches[Yuki::Sw::TJN_NightTime] = true
    draw
    context = BombanceAmbiance.manager.context
    assert_equal [27, 20, :night, :fog, :map], [context.map_id, context.zone_id, context.period, context.weather, context.scene]
    assert_equal :fog, $env.current_weather_db_symbol
    assert_equal 'clouds', $game_map.fog_name
  end

  def test_same_map_teleport_keeps_phase_and_camera_behavior
    tick(10)
    old = state.phase_x
    transfer(27, 40, 40)
    assert_in_delta old - 0.25, state.phase_x
    assert_in_delta $game_map.display_x / 4 + state.phase_x, fog.ox
  end

  def test_scene_reconstruction_keeps_phase_but_not_old_plane
    tick(39)
    position = [fog.ox, fog.oy]
    old_plane = fog
    $scene.spriteset.dispose
    $scene = Scene_Map.new
    assert old_plane.disposed?
    refute_same old_plane, fog
    assert_equal position, [fog.ox, fog.oy]
  end

  def test_render_rate_does_not_replace_native_logic_rate
    [1, 2, 5, 0, 3, 0, 1].each do |logic_updates|
      logic_updates.times { $game_map.update }
      4.times { draw }
    end
    assert_in_delta(-12 * 0.25, state.phase_x)
    assert_in_delta(-12 * 0.125, state.phase_y)
  end

  def test_non_active_map_does_not_modify_session
    tick(5)
    previous = [state.map_id, state.phase_x, state.phase_y]
    other = Game_Map.new
    other.setup(23)
    other.update
    assert_equal previous, [state.map_id, state.phase_x, state.phase_y]
  end

  def test_battle_extension_contract_is_inert
    implementation = Object.new
    def implementation.apply(*); raise 'Battle effect should not run in V1'; end
    BombanceAmbiance.register_effect(:battle, :future, implementation)
    assert_same implementation, BombanceAmbiance.effect(:battle, :future)
    assert_raises(ArgumentError) { BombanceAmbiance.register_effect(:battle, :invalid, Object.new) }
    tick
    assert_equal :map, BombanceAmbiance.manager.context.scene
  end

  def test_maplinker_reusing_mutable_mapdata_does_not_erase_copied_anchor
    tick(7)
    old_target = Yuki::MapLinker.map_datas.find { |v| v.map_id == 25 }
    expected = [-old_target.offset_x, -old_target.offset_y]
    native_load = Yuki::MapLinker.method(:load_map)
    replacement = lambda do |id|
      # The SDK reuses this object and calls load_position(:self) while loading.
      old_target.load_position(old_target.map, :self, 0)
      native_load.call(id)
    end
    Yuki::MapLinker.stub(:load_map, replacement) { transfer(25, 20, 20) }
    assert_equal [0, 0], [old_target.offset_x, old_target.offset_y]
    assert_equal expected, [state.anchor_x, state.anchor_y]
  end

  def test_foreign_maplinker_table_cannot_invent_a_spatial_connection
    tick(9)
    Yuki::MapLinker.load_map(25) # foreign data: 27 is now a neighbor, not central
    $game_map.setup(27)
    assert_equal [0, 0], [state.anchor_x, state.anchor_y]
  end
end
