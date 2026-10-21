# frozen_string_literal: true
require 'minitest/autorun'
require_relative 'support'

class AmbientOverlayTest < Minitest::Test
  def setup; reset_fixture(23); end
  def teardown; $scene.spriteset.dispose; end
  def manager; BombanceAmbiance.manager; end
  def renderer; $scene.spriteset.instance_variable_get(:@ambiance_overlay); end
  def sprite; renderer&.sprites&.[](23); end
  def draw; $scene.spriteset.send(:update_sprites); end
  def at(minute)
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = minute.divmod(60)
    draw
  end
  def profile; BombanceAmbiance::Settings::MAP_AMBIENT_OVERLAY_PROFILES[:village_night]; end

  def test_real_map_and_texture_dimensions
    map = read_data('Data/Map023.rxdata')
    assert_equal [74, 59], [map.width, map.height]
    png = File.binread(File.join(ROOT, 'graphics/fogs/BourgGuignon_Light.png'))
    assert_equal [2368, 1888], png.byteslice(16, 8).unpack('N2')
    assert_equal 6, png.getbyte(25) # PNG RGBA, not an opaque RGB replacement.
    at(1380)
    assert_equal 0.5, sprite.zoom_x
    assert_equal 2900, sprite.z
    assert_equal 0, sprite.shader.blend_type
  end

  def test_hourly_curve_and_midnight
    {0 => 1, 240 => 1, 420 => 1, 540 => 0.5, 660 => 0, 720 => 0,
     1140 => 0, 1170 => 0.25, 1200 => 0.5, 1215 => 0.75, 1230 => 1,
     1380 => 1, 1440 => 1}.each do |minute, factor|
      assert_in_delta profile[:max_opacity] * factor, BombanceAmbiance::MapAmbientOverlay.opacity(profile, minute)
    end
    previous = nil
    (0..1440).each do |minute|
      opacity = BombanceAmbiance::MapAmbientOverlay.opacity(profile, minute)
      assert_operator (opacity - previous).abs, :<=, profile[:max_opacity] / 60.0 + 0.00001 if previous
      previous = opacity
    end
    sparse = profile.merge(time_points: [[420, 100], [660, 0], [1140, 0], [1230, 100]])
    assert_equal profile[:max_opacity], BombanceAmbiance::MapAmbientOverlay.opacity(sparse, 0)
  end

  def test_live_clock_initial_opacity_and_daytime_cleanup
    at(720)
    assert_nil sprite
    at(1200)
    first = sprite
    assert_equal 64, first.opacity
    at(1230)
    assert_same first, sprite
    assert_equal 128, sprite.opacity
    at(0)
    assert_same first, sprite
    at(660)
    assert_nil sprite
    assert first.disposed?
    refute first.bitmap.disposed? # Cache owns the borrowed texture.
  end

  def test_camera_moves_in_world_pixels_without_parallax
    at(1380)
    before = [sprite.x, sprite.y]
    $game_map.display_x += 137
    $game_map.display_y -= 73
    draw
    assert_in_delta before[0] - 137 / 8.0, sprite.x
    assert_in_delta before[1] + 73 / 8.0, sprite.y
  end

  def test_native_fog_unchanged_and_weather_independent
    at(1380)
    fog = $scene.spriteset.fog
    before = [fog.object_id, fog.ox, fog.oy, fog.zoom, fog.opacity, fog.texture]
    %i[rain fog none sunny].each do |weather|
      $env.current_weather_db_symbol = weather
      draw
      assert_equal 128, sprite.opacity
      assert_equal before, [fog.object_id, fog.ox, fog.oy, fog.zoom, fog.opacity, fog.texture]
      assert_equal weather, $env.current_weather_db_symbol
    end
  end

  def test_linked_map_keeps_only_bourg_portion_without_jumping
    at(1380)
    $game_player.moveto(20, -1)
    draw
    old = sprite
    before = [old.x, old.y]
    link = Yuki::MapLinker.map_datas.find { |data| data.map_id == 27 }
    transfer(27, 20 + link.offset_x, -1 + link.offset_y)
    assert_same old, sprite
    assert_equal before, [sprite.x, sprite.y]
    assert_equal [23], renderer.sprites.keys
    $game_player.moveto(40, 20)
    draw
    assert_nil sprite
    assert old.disposed?
  end

  def test_other_maps_and_overrides_do_not_leak
    at(1380)
    BombanceAmbiance.override_effects(map_ambient_overlay: false)
    draw
    assert_nil sprite
    BombanceAmbiance.clear_overrides
    draw
    assert sprite
    assert_raises(ArgumentError) { BombanceAmbiance.override_effects(map_ambient_overlay: :native) }
    [27, 36, 80, 30].each do |map|
      transfer(map, 10, 10)
      assert_nil sprite
      assert_equal false, BombanceAmbiance::Configuration.resolve(map)[:map_ambient_overlay]
    end
  end

  def test_recreated_scene_and_loaded_session_immediately_match_clock
    at(1380)
    old = sprite
    $scene.spriteset.dispose
    assert old.disposed?
    $scene = Scene_Map.new
    assert_equal 128, sprite.opacity
    assert_equal old.x, sprite.x
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(:bombance_ambiance_session).call
    draw
    assert_equal 128, sprite.opacity
    assert_empty $game_map.instance_variables.grep(/overlay/)
    $game_switches[Yuki::Sw::TJN_Enabled] = false
    draw
    assert_nil sprite
  end
end
