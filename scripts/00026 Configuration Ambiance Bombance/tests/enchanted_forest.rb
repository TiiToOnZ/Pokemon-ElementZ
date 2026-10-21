# frozen_string_literal: true
require 'minitest/autorun'
require 'benchmark'
require_relative 'support'

# Only the headless Sprite double lacks this native rectangle API.
class Sprite
  Rect = Struct.new(:x, :y, :width, :height) do
    def set(*values); self.x, self.y, self.width, self.height = values; end
  end
  def src_rect; @src_rect ||= Rect.new; end
end

class EnchantedForestTest < Minitest::Test
  def setup
    reset_fixture(35, effects: { fireflies: true })
  end
  def teardown; $scene.spriteset.dispose; end
  def manager; BombanceAmbiance.manager; end
  def leaves; $scene.spriteset.instance_variable_get(:@ambiance_leaves); end
  def draw; $scene.spriteset.send(:update_sprites); end
  def tick(count = 1); count.times { $game_map.update; draw }; end
  def state; leaves.sprites.map { |s| [s.x, s.y, s.angle, s.opacity, s.visible, s.object_id] }; end
  def camera; [$game_map.display_x / 8.0 + manager.state.anchor_x * 16,
               $game_map.display_y / 8.0 + manager.state.anchor_y * 16]; end

  def test_real_map_fog_and_profiles
    map = read_data('Data/Map035.rxdata')
    assert_equal [130, 100, 30], [map.width, map.height, map.tileset_id]
    assert_equal ['eterna-forest-style-fog2', 100, 70, 0, 0],
                 [$game_map.fog_name, $game_map.fog_zoom, $game_map.fog_opacity, $game_map.fog_sx, $game_map.fog_sy]
    assert_equal :enchanted_forest_sunlight, manager.rays_plan.name
    assert_equal :natural_fireflies, manager.fireflies_plan.name
    assert_equal 8, manager.rays_emitters.size
    assert_equal 10, manager.fireflies_zones.size
    assert_equal 24, leaves.sprites.size
    assert leaves.particles.all? { |p| p.y < camera[1] }
    refute defined?(BombanceAmbiance::WindowLights)
  end

  def test_pool_recycles_only_after_exit_without_allocating_textures
    original = leaves.sprites.map(&:object_id)
    texture = leaves.texture
    seen = {}
    3000.times do
      before = leaves.particles.map { |p| [p.x, p.y] }
      tick
      leaves.particles.each_with_index do |p, i|
        seen[i] = true if (p.y - camera[1]).between?(0, 240)
        next unless p.y < before[i][1]
        assert before[i][1] - camera[1] > 240 || before[i][0] - camera[0] > 320 || before[i][0] < camera[0]
        assert_operator p.y, :<, camera[1]
      end
    end
    assert_equal 24, seen.size
    assert_equal original, leaves.sprites.map(&:object_id)
    assert_same texture, leaves.texture
    assert_operator leaves.sprites.count(&:visible), :>=, 15
    assert_operator leaves.sprites.count(&:visible), :<=, 24
    assert_operator leaves.particles.map(&:speed).uniq.size, :>, 15
  end

  def test_camera_projection_and_menu_redraws_preserve_world_state
    tick(1200)
    before, time = state, manager.leaves_tick
    world = leaves.particles.map(&:to_a)
    $game_map.display_x += 128 * 10
    $game_map.display_y += 128 * 5
    90.times { draw }
    assert_equal world, leaves.particles.map(&:to_a)
    before.zip(state).each do |a, b|
      assert_equal [a[0] - 160, a[1] - 80], b.first(2)
      assert_equal a.values_at(2, 3, 5), b.values_at(2, 3, 5)
    end
    assert_equal time, manager.leaves_tick
    tick
    refute_equal before, state
    assert_in_delta $game_map.display_x / 4, $scene.spriteset.fog.ox
    assert_in_delta 0.5, $scene.spriteset.fog.zoom
  end

  def test_redraw_batching_has_the_same_motion_as_each_logical_update
    tick(1200)
    expected = state.map { |s| s.first(5) }
    $scene.spriteset.dispose
    reset_fixture(35, effects: { fireflies: true })
    400.times { 3.times { $game_map.update }; draw }
    assert_equal expected, state.map { |s| s.first(5) }
  end

  def test_effective_weather_preserved_and_density_changes_smoothly
    tick(1200)
    texture, ids = leaves.texture, leaves.sprites.map(&:object_id)
    manager.leaves_profile[:weather].each do |weather, factors|
      $env.current_weather_db_symbol = weather
      previous = leaves.density
      tick
      assert_operator (leaves.density - previous).abs, :<=, 1.0 / 180 + 0.00001
      tick(300)
      assert_in_delta factors[:density], leaves.density
      assert_equal weather, $env.current_weather_db_symbol
      assert_equal 'eterna-forest-style-fog2', $game_map.fog_name
      assert_same texture, leaves.texture
      assert_equal ids, leaves.sprites.map(&:object_id)
      assert leaves.sprites.none?(&:visible) if factors[:density].zero?
      assert_equal 0, manager.rays_plan.opacity if weather == :fog
    end
  end

  def test_transfers_clean_up_and_restore_forest
    [23, 27, 36, 80, 25, 78, 30].each do |map|
      tick(10)
      old, texture = leaves.sprites.dup, leaves.texture
      transfer(map, 10, 10)
      assert_nil leaves
      assert old.all?(&:disposed?)
      refute texture.disposed?
      transfer(35, 35, 67)
      assert_equal 24, leaves.sprites.size
    end
  end

  def test_same_profile_link_keeps_particles_and_pool
    settings = BombanceAmbiance::Settings
    original = settings::MAPS
    settings.send(:remove_const, :MAPS)
    settings.const_set(:MAPS, original.merge(25 => { falling_leaves: true, outdoor: true }.freeze).freeze)
    tick(1200)
    renderer, ids, time = leaves, leaves.sprites.map(&:object_id), manager.leaves_tick
    transfer(25, 10, 60)
    assert_same renderer, leaves
    assert_equal ids, leaves.sprites.map(&:object_id)
    assert_equal time + 1, manager.leaves_tick
    transfer(35, 1, 60)
    assert_same renderer, leaves
  ensure
    settings.send(:remove_const, :MAPS)
    settings.const_set(:MAPS, original)
  end

  def test_ordinary_scene_rebuild_and_session_reset_start_from_above
    tick(600)
    old, texture = leaves.sprites.dup, leaves.texture
    $scene.spriteset.dispose
    assert old.all?(&:disposed?)
    refute texture.disposed?
    $scene = Scene_Map.new
    assert_equal 24, leaves.sprites.size
    assert leaves.particles.all? { |p| p.y < camera[1] }
    old = leaves.sprites.dup
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(:bombance_ambiance_session).call
    $game_map.update
    draw
    assert old.all?(&:disposed?)
    assert_equal 24, leaves.sprites.size
    assert_empty $game_map.instance_variables.grep(/leaves/)
  end

  def test_battle_snapshot_resumes_exactly_once_without_graphics
    tick(1200)
    battle = Object.new
    before = leaves.particles.map(&:to_a)
    visible = state.map { |s| s.first(5) }
    $game_temp.in_battle = true
    manager.suspend_leaves_for_battle(leaves, battle)
    assert_nil manager.take_leaves_battle_snapshot
    $scene.spriteset.dispose
    $game_temp.in_battle = false
    manager.finish_leaves_battle(battle)
    $scene = Scene_Map.new
    assert_equal before, leaves.particles.map(&:to_a)
    assert_equal visible, state.map { |s| s.first(5) }
    assert_nil manager.take_leaves_battle_snapshot
    assert leaves.particles.flat_map(&:to_a).all? { |value| value.is_a?(Numeric) }
    tick
    refute_equal before, leaves.particles.map(&:to_a)
  end

  def test_battle_snapshot_discarded_for_teleport_other_battle_disabled_effect_and_load
    tick(1200)
    battle = Object.new
    manager.suspend_leaves_for_battle(leaves, battle)
    $game_player.moveto(21, 20)
    manager.finish_leaves_battle(battle)
    assert_nil manager.instance_variable_get(:@leaves_battle)
    manager.suspend_leaves_for_battle(leaves, battle)
    manager.finish_leaves_battle(Object.new)
    assert_nil manager.instance_variable_get(:@leaves_battle)
    manager.suspend_leaves_for_battle(leaves, battle)
    BombanceAmbiance.override_effects(falling_leaves: false)
    tick
    assert_nil manager.instance_variable_get(:@leaves_battle)
    BombanceAmbiance.clear_overrides
    tick
    manager.suspend_leaves_for_battle(leaves, battle)
    PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(:bombance_ambiance_session).call
    assert_nil manager.instance_variable_get(:@leaves_battle)
  end

  def test_fast_camera_all_directions_never_recycles_visible_particles
    tick(1200)
    ids = leaves.sprites.map(&:object_id)
    [[16, 0], [-16, 0], [0, 16], [0, -16], [16, 16], [-16, -16], [160, 80], [-160, -80], [0, 0]].each do |dx, dy|
      $game_map.display_x += dx * 8
      $game_map.display_y += dy * 8
      draw # An extra render must not lose the pending logical camera delta.
      before = leaves.particles.map(&:dup)
      visible = leaves.sprites.map(&:visible)
      tick
      before.zip(leaves.particles).each_with_index do |(a, b), i|
        next unless visible[i] && a.wait.zero?
        assert_in_delta a.x + manager.leaves_profile[:drift_x] * a.drift, b.x
        assert_in_delta a.y + manager.leaves_profile[:fall_speed] * a.speed, b.y
      end
      assert_equal ids, leaves.sprites.map(&:object_id)
    end
    tick(1200)
    assert_operator leaves.sprites.count(&:visible), :>=, 15
    ratios = leaves.particles.map { |p| 0.09 * p.drift / (0.40 * p.speed) }
    assert_in_delta 0.225, ratios.sum / ratios.size, 0.04
  end

  def test_linked_camera_uses_the_same_world_origin
    settings = BombanceAmbiance::Settings
    original = settings::MAPS
    settings.send(:remove_const, :MAPS)
    settings.const_set(:MAPS, original.merge(25 => { falling_leaves: true, outdoor: true }.freeze).freeze)
    $game_player.moveto(-1, 60)
    tick(1200)
    link = Yuki::MapLinker.map_datas.find { |entry| entry.map_id == 25 }
    refute_nil link
    origin = camera
    before = leaves.particles.map(&:dup)
    transfer(25, -1 + link.offset_x, 60 + link.offset_y)
    assert_equal origin, camera
    before.zip(leaves.particles).each do |a, b|
      next if a.wait.positive? || (b.y - a.y).abs > 1
      assert_in_delta a.y + 0.40 * a.speed, b.y
      assert_in_delta a.x + 0.09 * a.drift, b.x
    end
  ensure
    settings.send(:remove_const, :MAPS)
    settings.const_set(:MAPS, original)
  end

  def test_sustained_scrolling_renews_a_bounded_pool_at_map_edges
    tick(1200)
    ids = leaves.sprites.map(&:object_id)
    samples = []
    360.times do
      $game_map.display_x += 8
      draw
      tick
      samples << leaves.sprites.count(&:visible)
    end
    assert_operator samples.sum.to_f / samples.size, :>=, 10
    assert_equal ids, leaves.sprites.map(&:object_id)
    [[0, 0], [130 * 16 - 320, 0], [0, 100 * 16 - 240], [130 * 16 - 320, 100 * 16 - 240]].each do |x, y|
      $game_map.display_x, $game_map.display_y = x * 8, y * 8
      tick(1200)
      assert_equal 24, leaves.particles.size
      assert_operator leaves.sprites.count(&:visible), :>=, 12
    end
  end

  def test_local_random_and_map_scoped_event_override
    srand(3500)
    expected = Random.new(3500).rand
    BombanceAmbiance.override_effects(falling_leaves: false)
    tick
    assert_nil leaves
    BombanceAmbiance.clear_overrides
    tick
    assert leaves
    tick(1000)
    assert_equal expected, rand
    assert_raises(ArgumentError) { BombanceAmbiance.override_effects(falling_leaves: :native) }
  end

  def test_tjn_does_not_stop_leaves_or_add_night_sunlight
    [[:Morning, 9], [:Day, 15], [:Sunset, 20.5], [:Night, 0]].each do |period, hour|
      %i[Morning Day Sunset Night].each { |p| $game_switches[Yuki::Sw.const_get("TJN_#{p}Time")] = p == period }
      $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = (hour * 60).round.divmod(60)
      tick(300)
      assert leaves
      assert_equal 0, manager.fireflies_plan.density if period == :Day
      assert_equal 0, manager.rays_plan.opacity if period == :Night
      assert_operator manager.fireflies_plan.density, :>, 0 if period == :Night
    end
  end
end
