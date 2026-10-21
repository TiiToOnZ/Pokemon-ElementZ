# frozen_string_literal: true
require_relative 'support'

class WeatherGameplayTest < WeatherTest
  def test_A_no_weather
    battle(:none)
    assert_equal 100, chance
  end

  def test_B_C_D_fog_accuracy_values
    battle
    assert_in_delta 0.8, @logic.raw_weather_effect.chance_of_hit_multiplier(@user, @target, @move)
    {100 => 80, 90 => 72, 80 => 64, 70 => 56}.each do |base, expected|
      @move.accuracy = base
      assert_in_delta expected, chance
    end
  end

  def test_E_accuracy_and_evasion_stages
    battle
    @user.acc_stage, @target.eva_stage = 2, 1
    assert_in_delta 100.0, chance # 100 * .8 * 5/3 * 3/4
    @user.acc_stage, @target.eva_stage = -1, -2
    assert_in_delta 100.0, chance # 100 * .8 * 3/4 * 5/3
  end

  def test_F_other_multipliers
    battle
    modifier = Battle::Effects::EffectBase.new(@logic)
    def modifier.chance_of_hit_multiplier(*); 0.5; end
    @user.effects.add(modifier)
    assert_in_delta 40, chance
  end

  def test_G_air_lock_and_cloud_nine
    battle
    enter
    %i[air_lock cloud_nine].each do |ability|
      @target.ability_effect = Battle::Effects::Ability.new(@logic, @target, ability)
      assert @logic.weather_effects_disabled?
      assert_in_delta 100, chance
      assert @logic.raw_weather_effect.fog?
      @scene.visual.update
      refute_nil fog_layer
    end
    @target.ability_effect = Battle::Effects::Ability.new(@logic, @target, :none)
    assert_in_delta 80, chance
  end

  def test_H_native_bypasses
    battle
    [0, -1].each do |accuracy|
      @move.accuracy = accuracy
      assert_equal 100, chance
      assert_equal [@target], @move.send(:proceed_move_accuracy, @user, [@target])
    end
    @move.accuracy = 100
    [@user, @target].each do |battler|
      battler.ability_effect = Battle::Effects::Ability.new(@logic, battler, :no_guard)
      assert_equal 100, chance
      assert @move.send(:bypass_accuracy?, @user, [@target])
      battler.ability_effect = Battle::Effects::Ability.new(@logic, battler, :none)
    end
    lock_on = OpenStruct.new(name: :lock_on, target: @target, dead?: false)
    @user.effects.add(lock_on)
    assert_equal 100, chance
    assert @move.send(:bypass_accuracy?, @user, [@target])
  end

  def test_I_J_native_weather_moves_replace_fog
    {rain_dance: :rain, sunny_day: :sunny, sandstorm: :sandstorm}.each do |move, weather|
      setup
      battle
      enter
      old = fog_layer
      Battle::Move::WeatherMove.new(@logic, 100, move).send(:deal_effect, @user, [])
      assert_equal weather, $env.current_weather_db_symbol
      assert_in_delta 100, chance
      assert_nil fog_layer
      assert old.plane.disposed?
      assert_equal 5, $env.weather_duration
      assert_includes @scene.events, parse_text(18, Battle::Logic::WeatherChangeHandler::WEATHER_SYM_TO_MSG[weather])
    end
  end

  def test_K_defog_native_bug_proven_and_corrected_without_losing_hazards
    battle
    native = Battle::Move::Defog.new(@logic)
    native.method(:deal_effect).super_method.call(@user, [])
    assert_equal [parse_text(18, 96), parse_text(18, 98)], @scene.events.grep(String)
    change(:fog)
    @scene.events.clear
    enter
    old = fog_layer
    @scene.events.clear
    hazard = Class.new(Battle::Effects::EffectBase) do
      def rapid_spin_affected?; true; end
    end.new(@logic)
    screen = Class.new(Battle::Effects::EffectBase) do
      def name; :reflect; end
    end.new(@logic)
    own_screen = screen.dup
    @user.effects.add(hazard)
    @logic.bank_effects[0] << own_screen
    @logic.bank_effects[1] << screen
    native.send(:deal_effect, @user, [])
    assert_equal :none, $env.current_weather_db_symbol
    assert_equal [parse_text(18, 96)], @scene.events.grep(String)
    assert hazard.dead?
    assert screen.dead?
    refute own_screen.dead?
    assert old.plane.disposed?
    assert_in_delta 100, chance
  end

  def test_L_simulated_sos_incoming_battler
    battle
    enter
    ally = TestBattler.new(@logic, 1)
    ally.position = 1
    @logic.battlers << ally
    @logic.execute_switch_events(ally, ally)
    assert_in_delta 80, @move.chance_of_hit(ally, @user)
    assert_equal :fog, $env.current_weather_db_symbol
    assert_equal 1, @scene.events.count(parse_text(18, 91))
  end

  def test_M_real_boss_dispatch_preserves_fog_and_short_circuit
    battle
    boss = Battle::Effects::EffectBase.new(@logic)
    def boss.chance_of_hit_multiplier(*); 0.5; end
    @target.boss_effects << boss
    assert_in_delta 40, chance
    effects = @logic.each_effects(@user, @target).to_a
    assert_equal 1, effects.count { |e| e.is_a?(Battle::Effects::Weather::Fog) }
    assert_equal boss, effects.last
    assert_equal :prevent, @logic.each_effects(@user, @target) { |e| :prevent if e.is_a?(Battle::Effects::Weather::Fog) }
  end

  def test_real_zv_miss_presentation_and_native_fallback
    battle
    @logic.move_accuracy_rng = Object.new
    @logic.move_accuracy_rng.define_singleton_method(:rand) { |*| 85 }
    assert_empty @move.send(:proceed_move_accuracy, @user, [@target])
    assert_includes @scene.events, [:miss, @target]
    assert_includes @scene.events, [:log, parse_text(19, 213)]
    change(:none)
    assert_equal [@target], @move.send(:proceed_move_accuracy, @user, [@target])
    Configs.zv_battle_msg.replace_miss = false
    change(:fog)
    assert_empty @move.send(:proceed_move_accuracy, @user, [@target])
    assert_includes @scene.events, parse_text(19, 213)
  end

  def test_native_duration_expiration
    battle
    enter
    $env.apply_weather(:fog, 1)
    @logic.raw_weather_effect.on_end_turn_event(@logic, @scene, @logic.battlers)
    assert_equal :none, $env.current_weather_db_symbol
    assert_nil fog_layer
    assert_equal 1, @scene.events.count(parse_text(18, 96))
  end
end

class WeatherEntryTest < WeatherTest
  def test_initial_announcements_are_unique_and_no_fake_change
    %i[fog rain sunny sandstorm hail hardsun hardrain strong_winds].each do |weather|
      setup
      battle(weather)
      enter
      enter
      message = parse_text(18, Battle::Logic::WeatherChangeHandler::WEATHER_SYM_TO_MSG[weather])
      assert_equal 1, @scene.events.count(message), weather.to_s
      assert_equal [:opponents_sent, :player_sent, message, :battle_begin], @scene.events.first(4)
      assert_equal Float::INFINITY, $env.weather_duration
    end
  end

  def test_none_and_snow_placeholder_are_silent
    %i[none snow].each do |weather|
      setup
      battle(weather)
      enter
      assert_empty @scene.events.grep(String)
    end
  end

  def test_fog_then_drizzle_order
    battle
    @target.ability_effect = Battle::Effects::Ability.new(@logic, @target, :drizzle)
    enter
    assert_equal [:opponents_sent, :player_sent, parse_text(18, 91), [:ability, :drizzle],
                  parse_text(18, 88), :battle_begin], @scene.events
    assert_nil fog_layer
    assert_equal :rain, $env.current_weather_db_symbol
    assert_equal 5, $env.weather_duration
  end

  def test_map_battle_map_and_second_event_weather_battle
    [5, nil].each do |forced|
      setup
      $forced_weather = forced
      battle
      assert_equal :fog, @scene.weather_at_logic_creation
      change(:rain)
      $env.bombance_prepare_battle_weather # must not overwrite a battle in progress
      assert_equal :rain, $env.current_weather_db_symbol
      Battle::Logic::BattleEndHandler.new(@logic, @scene).send(:handle_battle_end_weather_reset, [])
      $game_temp.in_battle = false
      assert_equal :fog, $env.current_weather_db_symbol
      assert_equal(forced || 0, $env.instance_variable_get(:@battle_weather))
      second = $scene = Battle::Scene.new(OpenStruct.new(vs_type: 1, trainer_battle?: false, battle_id: 0))
      assert_equal :fog, second.weather_at_logic_creation
      assert_equal Float::INFINITY, $env.weather_duration
      refute $game_switches[39]
    end
  end

  def test_mixweather_is_not_forced_off
    battle
    $game_switches[39] = true
    change(:rain)
    $game_temp.in_battle = false
    assert_equal :rain, $env.current_weather_db_symbol
    assert $game_switches[39]
  end

  def test_initial_presentation_does_not_fire_weather_callbacks
    battle
    observer = Battle::Effects::EffectBase.new(@logic)
    observer.instance_variable_set(:@changes, [])
    def observer.on_post_weather_change(*args); @changes << args; end
    @user.effects.add(observer)
    enter
    assert_empty observer.instance_variable_get(:@changes)
    change(:rain)
    assert_equal 1, observer.instance_variable_get(:@changes).size
  end

  def test_forced_map_weather_survives_battle_without_replacement
    battle
    $forced_weather = 5
    Battle::Logic::BattleEndHandler.new(@logic, @scene).send(:handle_battle_end_weather_reset, [])
    $game_temp.in_battle = false
    assert_equal :fog, $env.current_weather_db_symbol
  end

  def test_blank_native_translation_is_not_shown
    original = TEST_TEXT[18][287]
    TEST_TEXT[18][287] = '  '
    battle(:snow)
    enter
    assert_empty @scene.events.grep(String)
  ensure
    TEST_TEXT[18][287] = original
  end
end

class WeatherVisualTest < WeatherTest
  def test_mist_lifecycle_shared_fade_and_texture
    battle
    enter
    first = fog_layer
    assert_equal 2, first.mist_planes.size
    assert_equal [61, 62], first.mist_planes.map(&:z)
    assert_same first.mist_planes[0].bitmap, first.mist_planes[1].bitmap
    first.opacity = 0
    assert_equal [0, 0], first.mist_planes.map(&:opacity)
    first.opacity = BombanceWeather::FOG_OPACITY / 2.0
    assert_equal [26, 18], first.mist_planes.map(&:opacity)
    first.opacity = BombanceWeather::FOG_OPACITY
    assert_equal [52, 36], first.mist_planes.map(&:opacity)
    change(:none)
    assert first.mist_planes.all?(&:disposed?)
    refute first.mist_planes.first.bitmap.disposed?
    assert_nil fog_layer
    change(:fog)
    refute_same first, fog_layer
    second = fog_layer
    @scene.visual.dispose
    assert second.mist_planes.all?(&:disposed?)
  end

  def test_mist_wrap_wave_and_no_graphics_reallocation
    battle
    enter
    planes = fog_layer.mist_planes.dup
    textures = planes.map(&:bitmap)
    Graphics.time = 2
    @scene.visual.update
    assert_in_delta 12, planes[0].ox
    assert_in_delta 178, planes[1].ox
    assert_operator (planes[0].oy + 8).abs, :<=, 2
    assert_operator (planes[1].oy + 34).abs, :<=, 3
    planes[0].ox = 319
    Graphics.time += 1.0 / 3
    @scene.visual.update
    assert_in_delta 1, planes[0].ox
    600.times { @scene.scene_update_proc }
    assert_equal planes, fog_layer.mist_planes
    assert_equal textures, planes.map(&:bitmap)
    assert @scene.visual.weather.done?
  end

  def test_none_and_next_battle_have_no_residual_mist
    battle(:none)
    enter
    assert_nil fog_layer
    change(:fog)
    old = fog_layer
    @scene.visual.dispose
    assert old.mist_planes.all?(&:disposed?)
    $game_temp.in_battle = false
    battle
    enter
    refute_same old, fog_layer
    assert fog_layer.mist_planes.none?(&:disposed?)
  end

  def test_real_handler_and_wait_finish_with_persistent_layer
    battle
    $options.show_animation = true
    enter
    assert_operator Graphics.current_time, :>=, BombanceWeather::FOG_APPEARANCE_DURATION
    assert_operator Graphics.current_time, :<, 1.0
    assert @scene.visual.weather.done?
    assert_equal BombanceWeather::FOG_OPACITY, fog_layer.plane.opacity
    assert_equal 60, fog_layer.plane.z
    assert_equal 1, @scene.visual.instance_variable_get(:@animatable).size
    refute @scene.visual.locking?
  end

  def test_disabled_animation_keeps_ambience_and_reactivation
    battle
    enter
    assert_equal 0, Graphics.current_time
    first = fog_layer
    %i[rain sunny none].each do |weather|
      change(weather)
      assert first.plane.disposed?
      assert_nil fog_layer
      $env.apply_weather(:fog)
      @scene.visual.update
      first = fog_layer
      refute first.plane.disposed?
    end
    @scene.visual.dispose
    assert first.plane.disposed?
    assert_nil fog_layer
    refute RPG::Cache.animation('fog').disposed?
  end

  def test_no_layer_before_entry_and_frame_rate_independent_scroll
    battle
    @scene.visual.update
    assert_nil fog_layer
    enter
    Graphics.time += 2
    @scene.visual.update
    assert_in_delta 8, fog_layer.plane.ox
  end

  def test_removal_during_finite_animation_and_scene_cleanup
    battle
    @scene.visual.bombance_enable_weather_ambience
    @scene.visual.weather.show_weather_animation(:fog)
    layer = fog_layer
    $env.apply_weather(:none)
    60.times { @scene.scene_update_proc }
    assert layer.plane.disposed?
    assert @scene.visual.weather.done?
    @scene.visual.dispose
    assert @scene.visual.viewport.disposed?
  end
end
