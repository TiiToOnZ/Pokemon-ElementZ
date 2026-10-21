# frozen_string_literal: true
require_relative 'run'

class DiffuseLightTest < Minitest::Test
  def setup; reset_fixture; end
  def manager; BombanceAmbiance.manager; end
  def light; $scene.spriteset.instance_variable_get(:@ambiance_light); end
  def draw; $scene.spriteset.send(:update_sprites); end
  def tick(n = 1); n.times { $game_map.update; draw }; end
  def settle; tick(BombanceAmbiance::Settings::LIGHT[:transition_steps] + 1); end

  def period(value)
    %i[morning day sunset night].each do |name|
      id = {morning: Yuki::Sw::TJN_MorningTime, day: Yuki::Sw::TJN_DayTime,
            sunset: Yuki::Sw::TJN_SunsetTime, night: Yuki::Sw::TJN_NightTime}.fetch(name)
      $game_switches[id] = name == value
    end
    draw
  end

  def with_maps(maps)
    old = BombanceAmbiance::Settings::MAPS
    BombanceAmbiance::Settings.send(:remove_const, :MAPS)
    BombanceAmbiance::Settings.const_set(:MAPS, maps.freeze)
    yield
  ensure
    BombanceAmbiance::Settings.send(:remove_const, :MAPS)
    BombanceAmbiance::Settings.const_set(:MAPS, old)
  end

  def test_four_periods_and_smooth_retarget_without_graphics_recreation
    plane = light.plane
    %i[morning day sunset night].each do |name|
      previous = light.base_opacity
      period(name)
      assert_in_delta previous, light.base_opacity
      settle
      profile = BombanceAmbiance::Settings::PROFILES[:natural][name]
      assert_in_delta profile[:opacity], light.base_opacity
      assert_equal profile[:rgb], [plane.color.red, plane.color.green, plane.color.blue]
      assert_same plane, light.plane
    end
    assert_operator plane.opacity, :<=, 15
  end

  def test_clear_rain_fog_and_fast_changes
    settle
    plane = light.plane
    $env.current_weather_db_symbol = :rain
    draw
    assert_in_delta 24, light.base_opacity
    tick(30)
    midway = light.base_opacity
    assert_operator midway, :<, 24
    $env.current_weather_db_symbol = :fog
    draw
    assert_in_delta midway, light.base_opacity
    tick(20)
    $env.current_weather_db_symbol = :none
    draw
    assert_same plane, light.plane
    settle
    assert_in_delta 24, light.base_opacity
    $env.current_weather_db_symbol = :rain
    draw; settle
    assert_in_delta 7.2, light.base_opacity
    $env.current_weather_db_symbol = :fog
    draw; settle
    assert_nil light
    assert plane.disposed?
    $env.current_weather_db_symbol = :none
    draw
    refute_nil light
    refute_same plane, light.plane
    assert_equal 0, light.plane.opacity
  end

  def test_map_masks_remove_immediately_even_mid_fade
    tick(15)
    old = light.plane
    phase = manager.state.light_x
    transfer(23, 20, 10)
    assert_nil light
    assert old.disposed?
    tick(50)
    assert_in_delta phase, manager.state.light_x
    transfer(27, 20, 20)
    refute_nil light
    assert_operator manager.state.light_x, :>, phase
    assert_equal 0, light.plane.opacity
    transfer(36, 20, 20)
    assert_nil light
    transfer(80, 20, 20)
    assert_nil light
  end

  def test_interior_and_unconfigured_map_never_get_light
    transfer(30, 10, 10)
    BombanceAmbiance.override_effects(diffuse_light: true)
    $game_switches[Yuki::Sw::Env_CanFly] = false
    draw; tick(12)
    assert_nil light
    transfer(71, 10, 10)
    $game_switches[Yuki::Sw::Env_CanFly] = true
    draw
    assert_nil light
    assert_equal :native, manager.settings[:clouds]
  end

  def test_two_configured_linked_maps_keep_light_plane_and_world_coordinates
    settings = BombanceAmbiance::Settings::MAPS.merge(23 => {diffuse_light: true, outdoor: true})
    with_maps(settings) do
      settle
      plane = light.plane
      $game_player.moveto(31, $game_map.height)
      draw
      before_x, before_y = plane.ox, plane.oy
      link = Yuki::MapLinker.map_datas.find { |d| d.map_id == 23 }
      transfer(23, 31 + link.offset_x, $game_map.height + link.offset_y)
      assert_same plane, light.plane
      assert_in_delta before_x + BombanceAmbiance::Settings::LIGHT[:step_x], plane.ox, 1e-8
      assert_in_delta before_y + BombanceAmbiance::Settings::LIGHT[:step_y], plane.oy, 1e-8
      assert_in_delta 24, light.base_opacity
    end
  end

  def test_menu_redraw_freezes_light_and_teleport_keeps_phase
    settle
    before = [light.plane.ox, light.plane.oy, light.plane.opacity, manager.state.light_tick]
    120.times { draw }
    assert_equal before, [light.plane.ox, light.plane.oy, light.plane.opacity, manager.state.light_tick]
    phase = manager.state.light_x
    transfer(27, 45, 40)
    assert_in_delta phase + BombanceAmbiance::Settings::LIGHT[:step_x], manager.state.light_x
    assert_same manager, $scene.spriteset.instance_variable_get(:@ambiance_manager)
  end

  def test_cloud_disable_never_changes_weather_or_other_fog
    settle
    BombanceAmbiance.override_effects(clouds: false)
    $env.current_weather_db_symbol = :fog
    draw
    assert_equal 0, $scene.spriteset.fog.opacity
    assert_equal :fog, $env.current_weather_db_symbol
    assert_equal 90, $game_map.fog_opacity
    assert_equal 'clouds', $game_map.fog_name
    $game_map.fog_name = 'rising_smoke_3'
    draw
    assert_equal 90, $scene.spriteset.fog.opacity
    assert_equal :fog, $env.current_weather_db_symbol
    transfer(23, 10, 10)
    assert_equal 90, $scene.spriteset.fog.opacity
    assert_nil light
  end

  def test_map_configuration_can_disable_clouds_independently
    with_maps(BombanceAmbiance::Settings::MAPS.merge(27 => {clouds: false, diffuse_light: true, outdoor: true})) do
      BombanceAmbiance.clear_overrides
      draw
      assert_equal 0, $scene.spriteset.fog.opacity
      refute_nil light
      transfer(23, 20, 20)
      assert_equal 90, $scene.spriteset.fog.opacity
      assert_nil light
    end
  end

  def test_event_priority_scoping_weather_gate_and_reserved_effects
    transfer(23, 10, 10)
    $game_switches[Yuki::Sw::Env_CanFly] = true
    BombanceAmbiance.override_effects(diffuse_light: true, rays: true, atmospherics: true)
    draw; settle
    refute_nil light
    assert manager.settings[:rays]
    assert manager.settings[:atmospherics]
    $env.current_weather_db_symbol = :fog
    draw; settle
    assert_nil light # event does not bypass weather gate
    transfer(28, 10, 10)
    $env.current_weather_db_symbol = :none
    draw
    assert_nil light # map-scoped override did not leak
    BombanceAmbiance.override_effects(rays: true, atmospherics: true)
    draw
    assert_nil light # reserved fields don't instantiate anything
    BombanceAmbiance.clear_overrides(23)
    transfer(23, 10, 10)
    assert_nil light
  end

  def test_tjn_disabled_fallback_and_unknown_weather
    period(:night); settle
    $game_switches[Yuki::Sw::TJN_Enabled] = false
    draw; settle
    assert_in_delta 24, light.base_opacity
    $env.current_weather_db_symbol = :future_unknown_weather
    draw; settle
    assert_nil light
    assert_equal :future_unknown_weather, $env.current_weather_db_symbol
  end

  def test_load_clears_numeric_phase_overrides_and_old_graphics
    settle
    old = light.plane
    BombanceAmbiance.override_effects(clouds: false)
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES[:bombance_ambiance_session].call
    $game_map.setup(27)
    draw
    assert old.disposed?
    refute_same old, light.plane
    assert_equal 0, manager.state.light_tick
    assert_equal 90, $scene.spriteset.fog.opacity
    assert_empty $game_map.instance_variables.grep(/ambiance/)
  end

  def test_no_rebuild_for_stable_context_and_disposal_preserves_shared_bitmap
    settle
    plan = manager.light_plan
    plane = light.plane
    texture = plane.bitmap
    tick(500)
    assert_same plan, manager.light_plan
    assert_same plane, light.plane
    assert_same texture, light.plane.bitmap
    $scene.spriteset.dispose
    assert plane.disposed?
    refute texture.disposed?
  end
end
