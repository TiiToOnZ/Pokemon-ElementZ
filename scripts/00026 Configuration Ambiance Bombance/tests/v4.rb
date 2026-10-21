# frozen_string_literal: true
require_relative 'v3'

class FirefliesTest < Minitest::Test
  def setup
    reset_fixture(27, effects: { fireflies: true })
    $game_map.display_x, $game_map.display_y = 32 * 128, 15 * 128
    draw
  end
  def manager; BombanceAmbiance.manager; end
  def flies; $scene.spriteset.instance_variable_get(:@ambiance_fireflies); end
  def draw; $scene.spriteset.send(:update_sprites); end
  def tick(count = 1); count.times { $game_map.update; draw }; end
  def settle; tick(241); end
  def hour(value)
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = (value * 60).round.divmod(60)
    night, evening, day, morning = Yuki::TJN.current_time_set
    period = value >= night || value < morning ? :night : value >= evening ? :sunset : value >= day ? :day : :morning
    %i[Morning Day Sunset Night].each do |name|
      $game_switches[Yuki::Sw.const_get("TJN_#{name}Time")] = name.to_s.downcase.to_sym == period
    end
    draw
  end
  def night; hour(1); settle; end
  def visible_count; flies ? flies.sprites.values.count(&:visible) : 0; end
  def snapshot; flies.sprites.transform_values { |sprite| [sprite.x, sprite.y, sprite.opacity, sprite.object_id] }; end
  def with_setting(name, value)
    old = BombanceAmbiance::Settings.const_get(name)
    RaysRegressionConfig.set(name, value)
    yield
  ensure
    RaysRegressionConfig.set(name, old)
  end

  def test_hourly_progression_and_fixed_pool
    assert_nil flies # Day creates no graphics before first activation.
    hour(7); settle
    assert_equal 11, visible_count # 4 + 3 + 4
    assert_in_delta 0.45, flies.density
    sprites = flies.sprites.dup
    assert_equal 21, sprites.size
    hour(9); settle
    assert_operator visible_count, :<, 11
    assert_in_delta 0.225, flies.density
    hour(10.9); settle
    assert_operator flies.base_opacity, :<, 1
    hour(11); settle
    assert_equal 0, visible_count
    assert_equal sprites, flies.sprites
    hour(19); settle
    assert_equal 6, visible_count
    hour(21.9); settle
    assert_equal 11, visible_count
    night
    assert_equal 21, visible_count
    assert_equal sprites, flies.sprites
  end

  def test_period_boundaries_and_interrupted_transitions_are_continuous
    night
    pool = flies.sprites.dup
    hour(7)
    assert_in_delta 1, flies.density
    tick(120)
    assert_in_delta 0.725, flies.density
    assert_in_delta 167.5, flies.base_opacity
    hour(19)
    assert_in_delta 0.725, flies.density
    assert_in_delta 167.5, flies.base_opacity
    settle
    assert_in_delta 0.25, flies.density
    assert_equal pool, flies.sprites
    hour(23.99); settle
    previous = flies.density
    hour(0); settle
    assert_in_delta previous, flies.density
  end

  def test_real_tjn_seasonal_bounds_and_disabled_tjn
    Yuki::TJN.time_set = [17, 16, 12, 10].freeze
    hour(10); settle
    assert_in_delta 0.45, flies.density
    hour(11); settle
    assert_in_delta 0.225, flies.density
    hour(12); settle
    assert_equal 0, visible_count
    hour(16.5); settle
    assert_in_delta 0.375, flies.density
    $game_switches[Yuki::Sw::TJN_Enabled] = false
    draw
    assert_nil flies
  end

  def test_weather_activity_and_fog_are_independent_of_clouds
    night
    pool = flies.sprites.dup
    { rain: 0.25, fog: 0.55, hardrain: 0, strong_winds: 0, sandstorm: 0,
      snow: 0, hail: 0, future_weather: 0, none: 1 }.each do |weather, factor|
      $env.current_weather_db_symbol = weather
      draw; settle
      assert_in_delta factor, flies.density
      assert_in_delta 220 * factor, flies.base_opacity
      assert_equal pool, flies.sprites
      assert_equal weather, $env.current_weather_db_symbol
      assert_equal 90, $game_map.fog_opacity
    end
    before = snapshot
    BombanceAmbiance.override_effects(clouds: false)
    draw
    assert_equal before, snapshot
    BombanceAmbiance.override_effects(clouds: true)
    draw
    assert_equal before, snapshot
    # A V4 update cannot read the cloud bitmap (sun ray updates are bypassed).
    fog = $scene.spriteset.fog
    fog.texture.sample = ->(*) { raise 'Cloud sampled by fireflies' }
    100.times { flies.update(manager) }
    assert_equal before, snapshot
  end

  def test_motion_is_bounded_slow_unsynchronized_and_camera_anchored
    night
    first = snapshot
    changed = {}
    180.times do
      previous = snapshot
      tick
      snapshot.each do |key, (x, y, opacity, _)|
        assert_operator (x - previous[key][0]).abs, :<=, 1
        assert_operator (y - previous[key][1]).abs, :<=, 1
        zone = flies.particles[key].zone
        assert_operator x, :>=, zone.x - $game_map.display_x / 8.0
        assert_operator x, :<=, zone.x + zone.width - $game_map.display_x / 8.0
        assert_operator y, :>=, zone.y - $game_map.display_y / 8.0
        assert_operator y, :<=, zone.y + zone.height - $game_map.display_y / 8.0
        changed[key] = true if [x, y] != first[key].first(2)
      end
    end
    assert_operator changed.size, :>, 15
    assert_operator flies.sprites.values.map(&:opacity).uniq.size, :>, 10
    before = snapshot
    $game_map.display_x += 80
    $game_map.display_y -= 40
    draw
    snapshot.each do |key, current|
      assert_equal before[key][0] - 10, current[0]
      assert_equal before[key][1] + 5, current[1]
      assert_equal before[key][2..3], current[2..3]
    end
  end

  def test_menu_redraws_and_offscreen_culling_keep_world_trajectory
    night
    before, logical_tick = snapshot, manager.fireflies_tick
    120.times { draw }
    assert_equal before, snapshot
    assert_equal logical_tick, manager.fireflies_tick
    $game_map.display_x += 20000
    draw; tick(120)
    assert_equal 0, visible_count
    tick_at_return = manager.fireflies_tick
    $game_map.display_x -= 20000
    draw
    after = snapshot
    assert_equal 21, visible_count
    assert_equal before.values.map(&:last), after.values.map(&:last)
    # Recreate on the same tick: deterministic trajectory, no simulation lag.
    old = flies
    $scene.spriteset.dispose
    $scene = Scene_Map.new
    tick(241) # settle opacity only; animation remains tied to session tick
    assert_equal tick_at_return + 241, manager.fireflies_tick
    assert_empty old.sprites
    assert_equal after.keys, flies.sprites.keys
  end

  def test_excluded_maps_building_and_return_release_owned_texture
    night
    [23, 30, 36, 80, 71].each do |id|
      texture, old = flies.texture, flies.sprites.values
      source = RPG::Cache.animation('bombance_ambiance/firefly')
      transfer(id, 10, 10)
      assert_nil flies
      assert old.all?(&:disposed?)
      assert texture.disposed?
      refute source.disposed?
      transfer(27, 40, 25)
      settle
      refute_nil flies
    end
    assert_empty $game_map.instance_variables.grep(/firefl/)
  end

  def test_fireflies_work_without_other_effects_and_do_not_advance_their_clocks
    night
    BombanceAmbiance.override_effects(rays: false, diffuse_light: false)
    draw
    rays_tick, light_tick = manager.state.rays_tick, manager.state.light_tick
    before = snapshot
    tick(120)
    assert_equal rays_tick, manager.state.rays_tick
    assert_equal light_tick, manager.state.light_tick
    assert_equal 21, visible_count
    refute_equal before, snapshot
    BombanceAmbiance.override_effects(fireflies: false, rays: true, diffuse_light: true)
    draw
    assert_nil flies
    refute_nil $scene.spriteset.instance_variable_get(:@ambiance_rays)
    refute_nil $scene.spriteset.instance_variable_get(:@ambiance_light)
  end

  def test_same_tick_v4_update_never_changes_v1_v2_v3
    night
    fog = $scene.spriteset.fog
    light = $scene.spriteset.instance_variable_get(:@ambiance_light)
    rays = $scene.spriteset.instance_variable_get(:@ambiance_rays)
    before = [fog.ox, fog.oy, fog.opacity, light.base_opacity, rays.base_opacity,
              manager.light_plan.object_id, manager.rays_plan.object_id,
              rays.sprites.transform_values { |sprite| [sprite.x, sprite.y, sprite.opacity] }]
    120.times { flies.update(manager) }
    after = [fog.ox, fog.oy, fog.opacity, light.base_opacity, rays.base_opacity,
             manager.light_plan.object_id, manager.rays_plan.object_id,
             rays.sprites.transform_values { |sprite| [sprite.x, sprite.y, sprite.opacity] }]
    assert_equal before, after
  end

  def test_layout_configuration_limits_count_and_reuses_linked_zone_instances
    link = Yuki::MapLinker.map_datas.find { |data| data.map_id == 23 }
    ox, oy = link.offset_x, link.offset_y
    map = { fireflies: true, fireflies_profile: :natural_fireflies, outdoor: true }
    maps = BombanceAmbiance::Settings::MAPS.merge(
      27 => map.merge(fireflies_zones: [{ x: 29, y: 43, width: 4, height: 2, count: 4 }]),
      23 => map.merge(fireflies_zones: [{ x: 29 + ox, y: 43 + oy, width: 4, height: 2, count: 20 }])
    )
    with_setting(:MAPS, maps) do
      reset_fixture(27, effects: {fireflies: true})
      $game_player.moveto(31, $game_map.height)
      night
      assert_equal 12, flies.sprites.size # 4 + profile cap of 8
      pool, before, layer = flies.sprites.dup, snapshot, flies
      transfer(23, 31 + ox, $game_map.height + oy)
      assert_same layer, flies
      assert_equal pool, flies.sprites
      snapshot.each do |key, current|
        assert_in_delta before[key][0], current[0], 1
        assert_in_delta before[key][1], current[1], 1
      end
    end
  end

  def test_profile_change_and_session_reset_clean_up_and_reseed
    night
    original_motion = snapshot.transform_values { |values| values.first(3) }
    old, texture = flies.sprites.values, flies.texture
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES[:bombance_ambiance_session].call
    $game_map.setup(27)
    $game_map.display_x, $game_map.display_y = 32 * 128, 15 * 128
    draw
    assert old.all?(&:disposed?)
    assert texture.disposed?
    assert_equal 0, manager.fireflies_tick
    settle
    assert_equal original_motion, snapshot.transform_values { |values| values.first(3) }
    profiles = BombanceAmbiance::Settings::FIREFLIES_PROFILES
    maps = BombanceAmbiance::Settings::MAPS
    with_setting(:FIREFLIES_PROFILES, profiles.merge(custom: profiles[:natural_fireflies].merge(rgb: [150, 200, 255], max_per_zone: 3))) do
      with_setting(:MAPS, maps.merge(27 => maps[27].merge(fireflies_profile: :custom))) do
        BombanceAmbiance.clear_overrides
        draw; settle
        assert_equal :custom, flies.profile_name
        assert_equal 9, flies.sprites.size
        color = flies.sprites.values.first.color
        assert_equal [150, 200, 255], [color.red, color.green, color.blue]
      end
    end
  end
end
