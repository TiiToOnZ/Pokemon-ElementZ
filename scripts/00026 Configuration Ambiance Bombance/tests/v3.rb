# frozen_string_literal: true
require_relative 'v2'
require_relative 'rays_regression_config'

class SunRaysTest < Minitest::Test
  def setup
    @original_ray_settings = RaysRegressionConfig.install
    reset_fixture
    $game_map.display_x, $game_map.display_y = 32 * 128, 15 * 128
    draw
  end
  def teardown
    RaysRegressionConfig.restore(@original_ray_settings)
  end
  def manager; BombanceAmbiance.manager; end
  def rays; $scene.spriteset.instance_variable_get(:@ambiance_rays); end
  def draw; $scene.spriteset.send(:update_sprites); end
  def tick(count = 1); count.times { $game_map.update; draw }; end
  def settle; tick(241); end
  def period(value)
    %i[Morning Day Sunset Night].each do |name|
      $game_switches[Yuki::Sw.const_get("TJN_#{name}Time")] = name.to_s.downcase.to_sym == value
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

  def hour(value)
    minutes = (value * 60).round
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = minutes.divmod(60)
    night, evening, day, morning = Yuki::TJN.current_time_set
    period(value >= night || value < morning ? :night : value >= evening ? :sunset : value >= day ? :day : :morning)
  end

  def test_hourly_density_selects_real_subset_and_reuses_ten_sprites
    settle
    original = rays.sprites.dup
    light_plan, layout = manager.light_plan, manager.rays_emitters
    {11 => 5, 15 => 10, 18 => 5.78125}.each do |time, expected|
      hour(time); settle
      assert_in_delta expected, rays.density
      assert_equal expected.ceil, rays.sprites.values.count(&:visible)
      assert_equal original, rays.sprites
      assert_same light_plan, manager.light_plan # no minute-driven V2 retarget
      assert_same layout, manager.rays_emitters
    end
    hour(11)
    assert_in_delta 5.78125, rays.density # no abrupt count jump
    tick(90)
    assert_in_delta (5.78125 + 5) / 2, rays.density
    hour(15) # retarget a running fade
    current = rays.density
    draw
    assert_in_delta current, rays.density
    settle
    assert_equal 10, rays.sprites.values.count(&:visible)
  end

  def test_tjn_period_peaks_moon_palette_midnight_and_seasonal_bounds
    settle
    pool = rays.sprites.dup
    {9 => [5, [255, 232, 176]], 20.5 => [6, [255, 207, 151]],
     1 => [3, [183, 210, 255]]}.each do |time, (count, rgb)|
      hour(time); settle
      assert_in_delta count, rays.density
      assert_equal count, rays.sprites.values.count(&:visible)
      color = rays.sprites.values.first.color
      assert_equal rgb, [color.red, color.green, color.blue]
      assert_equal pool, rays.sprites
    end
    hour(23 + 59 / 60.0); settle
    before = manager.rays_plan.density
    hour(0)
    assert_in_delta before, manager.rays_plan.density, 0.03
    Yuki::TJN.time_set = [17, 16, 12, 10].freeze
    hour(11); settle
    assert_equal :morning, manager.context.period
    assert_in_delta 5, rays.density # morning peak follows winter 10..12
    hour(16.5); settle
    assert_in_delta 6, rays.density # sunset midpoint follows winter 16..17
    hour(1); settle
    assert_in_delta 3, rays.density
  end

  def test_cloud_sampling_budget_hidden_pool_and_fog_recovery
    settle
    pool = rays.sprites.dup
    image = rays.instance_variable_get(:@clouds).instance_variable_get(:@image)
    before = image.reads.size
    100.times { draw }
    assert_equal before, image.reads.size
    tick(4)
    assert_equal 50, image.reads.size - before # ten rays x five, once
    hour(1); settle
    before = image.reads.size
    tick(4)
    assert_equal 15, image.reads.size - before # only three moon rays
    $env.current_weather_db_symbol = :fog
    draw; settle
    before = image.reads.size
    tick(60)
    assert_equal before, image.reads.size
    assert rays.sprites.values.none?(&:visible)
    assert_equal pool, rays.sprites
    $env.current_weather_db_symbol = :none
    draw; settle
    assert_equal 3, rays.sprites.values.count(&:visible)
    assert_equal pool, rays.sprites
  end

  def test_map_capacity_lunar_opt_out_and_fog_cannot_be_overridden
    maps = BombanceAmbiance::Settings::MAPS
    with_maps(maps.merge(27 => maps[27].merge(rays_max: 4, lunar_rays: false))) do
      reset_fixture
      $game_map.display_x, $game_map.display_y = 32 * 128, 15 * 128
      draw; settle
      assert_equal 4, rays.sprites.size
      assert_equal 4, rays.sprites.values.count(&:visible)
      hour(1); settle
      assert rays.sprites.values.none?(&:visible)
      assert_equal 4, rays.sprites.size
      hour(15); settle
      assert_equal 4, rays.sprites.values.count(&:visible)
      $env.current_weather_db_symbol = :fog
      BombanceAmbiance.override_effects(rays: true)
      draw; settle
      assert rays.hidden?
    end
  end

  def test_config_is_opt_in_and_needs_explicit_placements
    assert manager.settings[:rays]
    assert_equal :forest_sunlight, manager.rays_plan.name
    assert_equal 10, manager.rays_emitters.size
    [23, 30, 36, 80, 71].each do |id|
      transfer(id, 10, 10)
      refute manager.settings[:rays]
      assert_nil rays
    end
    $game_switches[Yuki::Sw::Env_CanFly] = true
    BombanceAmbiance.override_effects(rays: true)
    draw
    assert manager.rays_plan.enabled
    assert_empty manager.rays_emitters
    assert_nil rays # no automatic or random placement, no sprite allocation
  end

  def test_camera_and_repeated_redraws_do_not_move_the_world
    settle
    snapshot = rays.sprites.transform_values { |s| [s.x, s.y, s.opacity, s.angle, s.object_id] }
    tick_before = manager.state.rays_tick
    120.times { draw }
    assert_equal tick_before, manager.state.rays_tick
    assert_equal snapshot, rays.sprites.transform_values { |s| [s.x, s.y, s.opacity, s.angle, s.object_id] }
    $game_map.display_x += 37
    $game_map.display_y -= 51
    draw
    snapshot.each do |key, values|
      assert_in_delta values[0] - 37 / 8.0, rays.sprites[key].x
      assert_in_delta values[1] + 51 / 8.0, rays.sprites[key].y
    end
  end

  def test_hour_palette_angle_and_opacity_interpolate_without_new_sprites
    settle
    sprites = rays.sprites.dup
    period(:sunset)
    assert_in_delta 110, rays.base_opacity
    assert_in_delta(24, rays.angle)
    tick(120)
    assert_in_delta 95, rays.base_opacity
    assert_in_delta(28, rays.angle)
    assert_equal sprites, rays.sprites
    settle
    assert_in_delta 80, rays.base_opacity
    assert_in_delta(32, rays.angle)
    period(:morning); settle
    assert_in_delta 92, rays.base_opacity
    assert_in_delta(18, rays.angle)
    color = rays.sprites.values.first.color
    assert_equal [255, 232, 176], [color.red, color.green, color.blue]
    assert_equal sprites, rays.sprites
  end

  def test_night_can_disable_lunar_rays_and_reuses_pool_at_dawn
    maps = BombanceAmbiance::Settings::MAPS
    with_maps(maps.merge(27 => maps[27].merge(lunar_rays: false))) do
      reset_fixture
      $game_map.display_x, $game_map.display_y = 32 * 128, 15 * 128
      draw; settle
      old = rays.sprites.dup
      texture = old.values.first.bitmap
      period(:night)
      tick(120)
      assert_operator rays.base_opacity, :>, 0
      assert_operator rays.base_opacity, :<, 110
      settle
      assert rays.hidden?
      assert old.values.none?(&:disposed?)
      assert old.values.none?(&:visible)
      refute texture.disposed?
      BombanceAmbiance.override_effects(rays: true)
      draw
      assert_equal 0, manager.rays_plan.opacity
      previous_tick = manager.state.rays_tick
      period(:morning)
      assert_equal previous_tick, manager.state.rays_tick
      settle
      assert_equal old, rays.sprites
      assert_operator rays.base_opacity, :>, 0
    end
  end

  def test_weather_fades_retarget_without_flash_and_fog_wins_over_events
    settle
    sprites = rays.sprites.dup
    $env.current_weather_db_symbol = :rain
    draw
    assert_in_delta 110, rays.base_opacity
    tick(90)
    assert_in_delta 59.4, rays.base_opacity
    $env.current_weather_db_symbol = :fog
    draw
    assert_in_delta 59.4, rays.base_opacity
    tick(25)
    previous = rays.base_opacity
    $env.current_weather_db_symbol = :none
    draw
    assert_in_delta previous, rays.base_opacity
    assert_equal sprites, rays.sprites
    settle
    $env.current_weather_db_symbol = :rain
    draw; settle
    assert_in_delta 8.8, rays.base_opacity
    $env.current_weather_db_symbol = :fog
    BombanceAmbiance.override_effects(rays: true)
    draw; settle
    assert rays.hidden?
    assert sprites.values.none?(&:disposed?)
    assert sprites.values.none?(&:visible)
    assert_equal :fog, $env.current_weather_db_symbol
    assert_equal 90, $game_map.fog_opacity
    assert_equal 90, $scene.spriteset.fog.opacity
  end

  def test_incompatible_weather_hides_pool_and_tjn_disabled_disposes_it
    [:hardrain, :fog, :sandstorm, :hail, :snow, :strong_winds, :future_weather].each do |weather|
      $env.current_weather_db_symbol = weather
      draw; settle
      assert rays.hidden?
      assert rays.sprites.values.none?(&:visible)
    end
    $env.current_weather_db_symbol = :none
    $game_switches[Yuki::Sw::TJN_Enabled] = false
    draw
    assert_nil rays
    refute_nil $scene.spriteset.instance_variable_get(:@ambiance_light)
  end

  def test_disabled_maps_and_buildings_remove_rays_even_during_a_fade
    tick(20)
    [23, 30, 36, 80, 71].each do |id|
      previous = rays.sprites.values
      phase = manager.state.rays_tick
      transfer(id, 20, 20)
      assert_nil rays
      assert previous.all?(&:disposed?)
      tick(10)
      assert_equal phase, manager.state.rays_tick
      transfer(27, 40, 25)
      refute_nil rays
      assert_equal 0, rays.base_opacity
      assert_equal phase + 1, manager.state.rays_tick
    end
  end

  def test_rays_clouds_and_diffuse_can_be_switched_independently
    settle
    diffuse = $scene.spriteset.instance_variable_get(:@ambiance_light).plane
    clouds = $scene.spriteset.fog
    BombanceAmbiance.override_effects(rays: false)
    draw
    assert_nil rays
    assert_same diffuse, $scene.spriteset.instance_variable_get(:@ambiance_light).plane
    assert_equal 90, clouds.opacity
    BombanceAmbiance.override_effects(rays: true, diffuse_light: false, clouds: false)
    draw; settle
    refute_nil rays
    assert_nil $scene.spriteset.instance_variable_get(:@ambiance_light)
    assert_equal 0, clouds.opacity
    $game_map.fog_name = 'rising_smoke_3'
    draw
    assert_equal 90, clouds.opacity
  end

  def test_linked_maps_keep_instances_world_positions_and_v1_v2_continuity
    link = Yuki::MapLinker.map_datas.find { |data| data.map_id == 23 }
    ox, oy = link.offset_x, link.offset_y
    maps = BombanceAmbiance::Settings::MAPS.merge(
      27 => { rays: true, diffuse_light: true, outdoor: true,
              rays_positions: [{x: 31.5, y: 44.7}] },
      23 => { rays: true, diffuse_light: true, outdoor: true,
              rays_positions: [{x: 31.5 + ox, y: 44.7 + oy}] }
    )
    with_maps(maps) do
      reset_fixture
      $game_player.moveto(31, $game_map.height)
      draw; settle
      layer = rays
      assert_equal 2, rays.sprites.size
      sprites = rays.sprites.dup
      positions = sprites.transform_values { |sprite| [sprite.x, sprite.y] }
      diffuse = $scene.spriteset.instance_variable_get(:@ambiance_light).plane
      diffuse_xy = [diffuse.ox, diffuse.oy]
      clouds = $scene.spriteset.fog
      cloud_xy = [clouds.ox, clouds.oy]
      emitters = manager.rays_emitters.to_h { |e| [e.key, [e.world_x, e.world_y]] }
      transfer(23, 31 + ox, $game_map.height + oy)
      assert_same layer, rays
      assert_equal sprites, rays.sprites
      assert_equal emitters, manager.rays_emitters.to_h { |e| [e.key, [e.world_x, e.world_y]] }
      positions.each do |key, pos|
        assert_in_delta pos[0], rays.sprites[key].x, 0.005
        assert_in_delta pos[1], rays.sprites[key].y, 0.005
      end
      assert_same diffuse, $scene.spriteset.instance_variable_get(:@ambiance_light).plane
      assert_in_delta diffuse_xy[0] + 0.012, diffuse.ox
      assert_in_delta diffuse_xy[1] - 0.006, diffuse.oy
      assert_same clouds, $scene.spriteset.fog
      assert_in_delta cloud_xy[0] - 0.25, clouds.ox
      assert_in_delta cloud_xy[1] - 0.125, clouds.oy
      # Loading directly on the other side derives the same on-screen anchors.
      reset_fixture(23)
      $game_player.moveto(31 + ox, 45 + oy)
      draw; tick(242)
      positions.each do |key, pos|
        assert_in_delta pos[0], rays.sprites[key].x, 0.005
        assert_in_delta pos[1], rays.sprites[key].y, 0.005
      end
    end
  end

  def test_culling_hides_pool_and_returns_to_deterministic_positions
    settle
    layer = rays
    positions = layer.sprites.transform_values { |s| [s.x, s.y] }
    $game_map.display_x += 20000
    draw
    assert layer.sprites.values.none?(&:visible)
    $game_map.display_x -= 20000
    draw
    assert_same layer, rays
    assert_equal positions, rays.sprites.transform_values { |s| [s.x, s.y] }
    assert rays.sprites.values.all?(&:visible)
  end

  def test_load_and_disposal_release_sprites_without_disposing_shared_texture
    settle
    old = rays.sprites.values
    texture = old.first.bitmap
    BombanceAmbiance.override_effects(clouds: false)
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES[:bombance_ambiance_session].call
    $game_map.setup(27)
    draw
    assert old.all?(&:disposed?)
    assert_equal 0, manager.state.rays_tick
    assert_equal 90, $scene.spriteset.fog.opacity
    current = rays.sprites.values
    $scene.spriteset.dispose
    assert current.all?(&:disposed?)
    refute texture.disposed?
    assert_empty $game_map.instance_variables.grep(/ambiance|rays/)
  end

  def test_stable_context_reuses_profile_layout_sprites_and_texture
    settle
    plan, emitters, sprites = manager.rays_plan, manager.rays_emitters, rays.sprites.dup
    bitmap_ids = sprites.values.map { |s| s.bitmap.object_id }
    tick(500)
    assert_same plan, manager.rays_plan
    assert_same emitters, manager.rays_emitters
    assert_equal sprites, rays.sprites
    assert_equal bitmap_ids, rays.sprites.values.map { |s| s.bitmap.object_id }
  end

  def test_configuration_controls_placement_geometry_and_count_without_renderer_changes
    positions = 12.times.map { |i| {x: 40 + i * 0.2, y: 25, width: 0.7, length: 1.2, angle: 5, opacity: 0.5} }
    maps = BombanceAmbiance::Settings::MAPS.merge(27 => {rays: true, outdoor: true, rays_positions: positions})
    with_maps(maps) do
      reset_fixture
      $game_player.moveto(40, 25)
      draw; settle
      assert_equal 10, manager.rays_emitters.size # profile count limits explicit list
      assert_equal 10, rays.sprites.size
      sprite = rays.sprites.fetch('27:0')
      assert_in_delta 0.7, sprite.zoom_x
      assert_in_delta 1.2, sprite.zoom_y
      assert_in_delta(29, sprite.angle)
      assert_operator sprite.opacity, :<, 64
      assert_equal 40 * 16, manager.rays_emitters.first.world_x
    end
    # Declaring the same map interior blocks event activation too.
    with_maps(maps.merge(27 => maps[27].merge(outdoor: false))) do
      reset_fixture(27, effects: { rays: true })
      draw
      assert_nil rays
    end
  end

  def test_scene_recreation_and_teleport_keep_phase_but_release_old_graphics
    settle
    tick_before = manager.state.rays_tick
    old = rays.sprites.dup
    positions = old.transform_values { |s| [s.x, s.y] }
    $scene.spriteset.dispose
    $scene = Scene_Map.new
    assert old.values.all?(&:disposed?)
    assert_equal tick_before, manager.state.rays_tick
    assert_equal positions, rays.sprites.transform_values { |s| [s.x, s.y] }
    old.each do |key, sprite|
      refute_same sprite, rays.sprites[key]
      assert_same sprite.bitmap, rays.sprites[key].bitmap
    end
    transfer(27, 40, 25)
    assert_equal tick_before + 1, manager.state.rays_tick
    transfer(30, 10, 10)
    BombanceAmbiance.override_effects(rays: true)
    $game_switches[Yuki::Sw::Env_CanFly] = false
    draw
    assert_nil rays
  end

  def test_cloud_shadow_fades_out_and_back_without_recreating_any_sprite
    settle
    sprites = rays.sprites.dup
    fog = $scene.spriteset.fog
    fog.texture.sample = ->(*) { Color.new(37, 33, 30, 255) }
    tick(18)
    factors = rays.instance_variable_get(:@transmissions)
    factors.each_value { |value| assert_in_delta 0.5, value, 4.0 / 36 }
    opacities = rays.sprites.transform_values(&:opacity)
    120.times { draw } # menus / high rendering FPS cannot accelerate the fade
    assert_equal opacities, rays.sprites.transform_values(&:opacity)
    factors.each_value { |value| assert_in_delta 0.5, value, 4.0 / 36 }
    tick(22)
    assert rays.sprites.values.all? { |sprite| sprite.opacity.zero? }
    assert_equal sprites, rays.sprites
    tick(100)
    assert rays.sprites.values.all? { |sprite| sprite.opacity.zero? }
    fog.texture.sample = ->(*) { Color.new(255, 255, 255, 0) }
    tick(18)
    factors.each_value { |value| assert_in_delta 0.5, value, 4.0 / 36 }
    tick(22)
    assert rays.sprites.values.all? { |sprite| sprite.opacity > 0 }
    factors.each_value { |value| assert_in_delta 1.0, value }
    assert_equal sprites, rays.sprites
  end

  def test_sampler_uses_native_origin_zoom_rotation_and_wrap_and_reuses_image
    settle
    fog = $scene.spriteset.fog
    fog.set_origin(-523.25, 1044.75)
    fog.zoom = 0.75
    sprite = rays.sprites.values.first
    sampler = BombanceAmbiance::RayCloudShadow.new
    sampler.prepare(fog)
    image = sampler.instance_variable_get(:@image)
    sampler.transmission(sprite, manager.rays_plan.profile)
    expected = BombanceAmbiance::RayCloudShadow::POINTS.map do |dx, dy|
      angle = sprite.angle * Math::PI / 180
      x = sprite.x + dx * sprite.zoom_x * Math.cos(angle) + dy * sprite.zoom_y * Math.sin(angle)
      y = sprite.y - dx * sprite.zoom_x * Math.sin(angle) + dy * sprite.zoom_y * Math.cos(angle)
      [(fog.ox + x / 0.75).floor % 512, (fog.oy + y / 0.75).floor % 512]
    end
    assert_equal expected, image.reads
    sampler.prepare(fog)
    assert_same image, sampler.instance_variable_get(:@image)
    fog.texture = FakeTexture.new
    sampler.prepare(fog)
    assert image.disposed?
    refute fog.texture.disposed?
    current_image = sampler.instance_variable_get(:@image)
    sampler.dispose
    assert current_image.disposed?
    refute fog.texture.disposed?
    sampler.dispose # idempotent on scene teardown
  end

  def test_five_point_coverage_threshold_and_transparency
    settle
    fog = $scene.spriteset.fog
    sampler = BombanceAmbiance::RayCloudShadow.new
    sampler.prepare(fog)
    sprite, profile = rays.sprites.values.first, manager.rays_plan.profile
    index = 0
    fog.texture.sample = lambda do |*|
      index += 1
      index % 5 < 2 ? Color.new(37, 33, 30, 255) : Color.new(255, 255, 255, 0)
    end
    value = sampler.transmission(sprite, profile)
    assert_operator value, :>, 0
    assert_operator value, :<, 1
    assert_equal 1, sampler.transmission(sprite, profile.merge(cloud_threshold: 1.0))
    fog.texture.sample = ->(*) { Color.new(37, 33, 30, 255) }
    assert_equal 0, sampler.transmission(sprite, profile)
    fog.opacity = 0
    sampler.prepare(fog)
    assert_equal 1, sampler.transmission(sprite, profile)
    fog.opacity = 90
    fog.texture.sample = ->(*) { Color.new(255, 255, 255, 255) }
    sampler.prepare(fog)
    assert_equal 1, sampler.transmission(sprite, profile) # white is not a shadow
  ensure
    sampler&.dispose
  end

  def test_missing_or_disabled_clouds_restore_rays_and_other_fogs_are_not_sampled
    settle
    fog = $scene.spriteset.fog
    fog.texture.sample = ->(*) { Color.new(37, 33, 30, 255) }
    tick(40)
    assert rays.sprites.values.all? { |sprite| sprite.opacity.zero? }
    BombanceAmbiance.override_effects(clouds: false)
    tick(40)
    assert rays.sprites.values.all? { |sprite| sprite.opacity > 0 }
    assert_equal 0, fog.opacity
    $game_map.fog_name = 'rising_smoke_3'
    draw
    fog.texture.sample = ->(*) { raise 'Non-cloud Fog sampled' }
    tick(40)
    assert_equal 90, fog.opacity
    assert rays.sprites.values.all? { |sprite| sprite.opacity > 0 }
    $env.current_weather_db_symbol = :fog
    draw; settle
    assert rays.hidden?
    assert_equal 90, fog.opacity
  end

  def test_shadow_state_does_not_leak_after_transfer_and_images_are_disposed
    settle
    fog = $scene.spriteset.fog
    fog.texture.sample = ->(*) { Color.new(37, 33, 30, 255) }
    tick(40)
    old = rays
    image = old.instance_variable_get(:@clouds).instance_variable_get(:@image)
    transfer(36, 20, 20)
    assert_nil rays
    assert image.disposed?
    assert_empty old.sprites
    transfer(80, 20, 20)
    assert_nil rays
    transfer(27, 40, 25)
    settle
    assert rays.sprites.values.all? { |sprite| sprite.opacity > 0 }
    assert rays.instance_variable_get(:@transmissions).values.all? { |value| value == 1 }
  end
end
