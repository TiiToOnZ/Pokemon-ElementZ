# frozen_string_literal: true
# Real Game.rb/Studio Ruby capture harness. Save read only, forest in RAM.
# No input, event execution, saves or asset changes. Only named PNG/report output.
require 'json'
module ForestGameProbe
  ROOT = File.expand_path('../../../..', __dir__)
  OUTPUT = File.expand_path('captures_enchanted', __dir__) + '/'
  Dir.mkdir(OUTPUT) unless Dir.exist?(OUTPUT)
  MEMORY = {}
  def self.stop(message, status = 0)
    STDERR.puts(message)
    STDERR.flush
    Process.exit!(status)
  end
  def self.allowed?(path)
    File.expand_path(path).tr('\\', '/').start_with?(OUTPUT.tr('\\', '/'))
  end
  def self.check(path, mode)
    writing = mode.is_a?(Integer) ? (mode & (File::WRONLY | File::RDWR | File::CREAT | File::TRUNC | File::APPEND)) != 0 : mode.to_s.match?(/[wa+]/)
    stop("BLOCKED WRITE: #{path}; exception=#{$!.inspect}; #{$!&.backtrace&.first(12)&.join(' | ')}", 77) if writing && !allowed?(path)
  end
end
guard = Module.new do
  def open(path, *args, **kw, &block)
    ForestGameProbe.check(path, args[0] || kw[:mode]); super
  end
  def new(path, *args, **kw, &block)
    ForestGameProbe.check(path, args[0] || kw[:mode]); super
  end
  def write(path, *args)
    ForestGameProbe.check(path, 'w'); super
  end
  def binwrite(path, bytes, *args)
    if File.expand_path(path) == File.expand_path('Data/Studio/psdk.dat')
      ForestGameProbe::MEMORY[File.expand_path(path)] = bytes
      return bytes.bytesize
    end
    ForestGameProbe.check(path, 'w'); super
  end
  def binread(path, *args)
    ForestGameProbe::MEMORY.fetch(File.expand_path(path)) { super }
  end
  def exist?(path)
    ForestGameProbe::MEMORY.key?(File.expand_path(path)) || super
  end
end
%i[delete unlink rename truncate chmod chown utime symlink link].each do |method|
  guard.define_method(method) { |*args| ForestGameProbe.stop("BLOCKED #{method}: #{args.first}", 77) }
end
File.singleton_class.prepend(guard)
module Kernel
  alias forest_probe_puts puts
  def puts(*args)
    forest_probe_puts(*args) unless args.first.to_s.start_with?('Loading E:/')
  end
end

STAGES = [
  ['01_original_fog', 15, :original, 35, 67, 300],
  ['02_retained_canopy', 15, :original, 35, 67, 300],
  ['03_canopy_rays', 15, :rays, 35, 67, 300],
  ['04_canopy_leaves', 15, :leaves, 35, 67, 1500],
  ['05_canopy_fireflies', 0, :flies, 35, 67, 300],
  ['06_all_day', 15, :all, 35, 67, 1500],
  ['07_all_sunset', 20.5, :all, 35, 67, 300],
  ['08_all_night', 0, :all, 35, 67, 300],
  ['09_motion_00', 15, :all, 35, 67, 300],
  ['10_motion_15', 15, :all, 35, 67, 15],
  ['11_motion_30', 15, :all, 35, 67, 15],
  ['12_motion_45', 15, :all, 35, 67, 15],
  ['13_motion_60', 15, :all, 35, 67, 15],
  ['14_camera_moved', 15, :all, 40, 67, 120],
  ['15_eastern_meadow', 15, :all, 81, 55, 300],
  ['16_eastern_night', 0, :all, 81, 55, 300],
  ['17_dialogue', 0, :all, 35, 67, 300]
].freeze

def apply_forest_stage(stage)
  _, hour, mode, x, y, = stage
  $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = (hour * 60).round.divmod(60)
  BombanceAmbiance.override_effects(35, rays: [:rays, :all].include?(mode),
    fireflies: [:flies, :all].include?(mode), falling_leaves: [:leaves, :all].include?(mode))
  $game_player.moveto(x, y)
  Yuki::TJN.force_update_tone
  if stage[0] == '17_dialogue'
    $scene.send(:setup_message_display, 'Les feuilles dansent entre les arbres...', 1, [])
  end
end

def verify_forest_ui_and_transfers
  scene = $scene
  manager = BombanceAmbiance.manager
  leaves = scene.spriteset.instance_variable_get(:@ambiance_leaves)
  ids, tick = leaves.sprites.map(&:object_id), manager.leaves_tick
  message = scene.instance_variable_get(:@message_window)
  raise 'Dialogue below map' unless message.viewport.z > scene.spriteset.map_viewport.z
  message.terminate_message
  scene.window_message_close(false)
  menu = GamePlay.menu_class.new
  $scene = menu
  menu.send(:main_begin)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.6
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    menu.send(:update_graphics)
    Graphics.update
  end
  bitmap = Graphics.snap_to_bitmap
  File.binwrite(ForestGameProbe::OUTPUT + '18_native_menu.png', bitmap.to_png)
  bitmap.dispose
  raise 'Menu advanced leaves' unless manager.leaves_tick == tick
  raise 'Menu replaced leaves' unless leaves.sprites.map(&:object_id) == ids
  menu.send(:dispose)
  $scene = scene
  scene.spriteset.visible = true
  scene.spriteset.update
  bitmap = Graphics.snap_to_bitmap
  File.binwrite(ForestGameProbe::OUTPUT + '19_menu_return.png', bitmap.to_png)
  bitmap.dispose
  transfers = []
  [25, 23, 27, 36, 80, 35].each do |map|
    $game_temp.player_new_map_id = map
    $game_temp.player_new_x = map == 35 ? 35 : 10
    $game_temp.player_new_y = map == 35 ? 67 : 10
    $game_temp.player_new_direction = 0
    scene.send(:transfer_player)
    scene.spriteset.update
    active = scene.spriteset.instance_variable_get(:@ambiance_leaves)
    raise "Leaves leaked to map #{map}" unless (!!active) == (map == 35)
    transfers << {map: map, leaves: active&.sprites&.size, weather: $env.current_weather_db_symbol}
  end
  {native_menu: menu.class.to_s, dialogue_above_map: true, menu_tick_unchanged: true, transfers: transfers}
end

frames = map_frames = stage = logic = stage_started = 0
armed = false
reports = []
performance = {calls: 0, seconds: 0.0, max_seconds: 0.0}
TracePoint.new(:call, :raise) do |tp|
  if tp.event == :raise && tp.path.include?('00026 Configuration Ambiance Bombance') && !tp.path.include?('/tests/')
    ForestGameProbe.stop("#{tp.raised_exception.class}: #{tp.raised_exception.message} at #{tp.path}:#{tp.lineno}", 1)
  elsif tp.event == :call && tp.method_id == :display_game_exception
    ForestGameProbe.stop("GAME EXCEPTION: #{$!}", 1)
  elsif tp.event == :call && tp.method_id == :update && defined?(BombanceAmbiance::MapLifecycle) &&
        tp.defined_class == BombanceAmbiance::MapLifecycle && tp.self.equal?($game_map)
    logic += 1
  elsif tp.event == :call && tp.method_id == :update && Object.const_defined?(:Graphics) && tp.self.equal?(Graphics)
    frames += 1
    ForestGameProbe.stop('Game probe timeout', 1) if frames > 150000
    if !armed && frames > 120 && $scene.is_a?(Scene_Title)
      armed = true
      Interpreter.prepend(Module.new { def update; end }) # Harness only: no events.
      if defined?(BombanceAchievements::Notifications)
        BombanceAchievements::Notifications.singleton_class.prepend(Module.new { def update(*); end })
      end
      BombanceAmbiance::FallingLeaves.prepend(Module.new do
        define_method(:update) do |manager|
          fresh = manager.leaves_tick != tick
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          super(manager)
          if fresh
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
            performance[:calls] += 1
            performance[:seconds] += elapsed
            performance[:max_seconds] = [performance[:max_seconds], elapsed].max
          end
        end
      end)
      state = GamePlay::Save.load('Saves/Pokemon_Party-1', no_load_parameter: true)
      raise 'Save unavailable' unless state
      state.expand_global_var
      state.load_parameters
      Yuki::MapLinker.reset
      $game_switches[Yuki::Sw::TJN_RealTime] = false
      $game_switches[Yuki::Sw::TJN_NoTime] = true
      $game_switches[Yuki::Sw::TJN_Enabled] = true
      $env.reset_zone
      $game_map.setup(35)
      $game_player.refresh
      apply_forest_stage(STAGES[0])
      $scene.instance_variable_set(:@running, false)
      $scene = Scene_Map.new
      stage_started = logic
    elsif armed && $scene.is_a?(Scene_Map) && $scene.spriteset
      map_frames = logic - stage_started
      next unless map_frames >= STAGES[stage][5]
      manager = BombanceAmbiance.manager
      renderer = $scene.spriteset.instance_variable_get(:@ambiance_leaves)
      rays = $scene.spriteset.instance_variable_get(:@ambiance_rays)
      flies = $scene.spriteset.instance_variable_get(:@ambiance_fireflies)
      bitmap = Graphics.snap_to_bitmap
      File.binwrite(ForestGameProbe::OUTPUT + STAGES[stage][0] + '.png', bitmap.to_png)
      bitmap.dispose
      reports << {capture: STAGES[stage][0], map: $game_map.map_id, logical_steps: map_frames,
        hour: STAGES[stage][1], period: manager.context.period, weather: manager.context.weather,
        fog: [$game_map.fog_name, $game_map.fog_zoom, $game_map.fog_opacity, $game_map.fog_sx, $game_map.fog_sy],
        leaves: renderer&.sprites&.count(&:visible), pool: renderer&.sprites&.size,
        rays: rays&.sprites&.values&.count { |s| s.visible && s.opacity.positive? },
        fireflies: flies&.sprites&.values&.count(&:visible),
        camera: [$game_map.display_x, $game_map.display_y],
        tone: %i[red green blue gray].map { |key| $game_screen.tone.send(key) },
        leaves_positions: renderer&.sprites&.map { |s| [s.x, s.y, s.opacity] }}
      STDERR.puts "Captured #{STAGES[stage][0]} (leaves #{reports.last[:leaves] || 0})"
      if (stage += 1) == STAGES.size
        integration = verify_forest_ui_and_transfers
        performance[:average_ms] = performance[:seconds] * 1000 / [performance[:calls], 1].max
        File.write(ForestGameProbe::OUTPUT + 'results.json', JSON.pretty_generate(captures: reports, performance: performance, integration: integration))
        ForestGameProbe.stop(JSON.generate(performance))
      end
      apply_forest_stage(STAGES[stage])
      stage_started = logic
      map_frames = 0
    end
  end
end.enable
load './Game.rb'
