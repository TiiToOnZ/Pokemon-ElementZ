# frozen_string_literal: true
# Real Game.rb/Studio Ruby capture harness. Save read only, forest in RAM.
# No input, event execution, saves or asset changes. Only named PNG/report output.
require 'json'
module ForestGameProbe
  ROOT = File.expand_path('../../../..', __dir__)
  OUTPUT = File.expand_path('captures_ambient_overlay', __dir__) + '/'
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

module AmbientProbe
  TIMES = [720, 1140, 1200, 1230, 1380, 240, 420, 540, 660].freeze
  REPORT = []
  class << self
    attr_accessor :returned, :battling
  end
  def self.renderer; $scene.spriteset.instance_variable_get(:@ambiance_overlay); end
  def self.sprite; renderer&.sprites&.[](23); end
  def self.hour(minute)
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = minute.divmod(60)
    Yuki::TJN.force_update_tone
  end
  def self.capture(name)
    bitmap = Graphics.snap_to_bitmap
    File.binwrite(ForestGameProbe::OUTPUT + name + '.png', bitmap.to_png)
    bitmap.dispose
    s = $scene.is_a?(Scene_Map) && $scene.spriteset && sprite
    fog = $scene.is_a?(Scene_Map) && $scene.spriteset && $scene.spriteset.instance_variable_get(:@fog)
    REPORT << {name: name, map: $game_map.map_id, minute: BombanceAmbiance::Configuration.rays_minute,
      camera: [$game_map.display_x, $game_map.display_y],
      overlay: s && [s.x, s.y, s.opacity, s.zoom_x, s.bitmap.width, s.bitmap.height],
      tone: %i[red green blue gray].map { |k| $game_screen.tone.send(k) },
      weather: $env.current_weather_db_symbol,
      fog: fog && [$game_map.fog_name, fog.ox, fog.oy, fog.opacity, fog.instance_variable_get(:@zoom), fog.z]}
    STDERR.puts "Captured #{name}: #{REPORT.last[:overlay]}"
  end
  def self.pair(name)
    s = sprite
    s.visible = false if s
    capture(name + '_before')
    s.visible = true if s
    capture(name + '_after')
  end
  def self.start_battle
    self.battling = true
    capture('battle_before')
    $actors.replace([PFM::Pokemon.generate_from_hash(id: :mewtwo, level: 100,
      moves: [:tackle, :__remove__, :__remove__, :__remove__], no_shiny: true)])
    info = Battle::Logic::BattleInfo.new
    info.add_party(0, *info.player_basic_info)
    enemy = PFM::Pokemon.generate_from_hash(id: :caterpie, level: 2, moves: [:tackle], no_shiny: true)
    info.add_party(1, [enemy], nil, nil, nil, nil, nil, 0)
    $scene.send(:setup_start_battle, Battle::Scene, info)
  end
  def self.finish
    scene = $scene
    initial = sprite
    scene.send(:setup_message_display, 'Bourg-guignon illumine ses fenetres...', 1, [])
    message = scene.instance_variable_get(:@message_window)
    90.times { scene.send(:message_update); Graphics.update }
    raise 'Dialogue below map' unless message.viewport.z > scene.spriteset.map_viewport.z
    capture('dialogue')
    message.terminate_message
    scene.window_message_close(false)
    menu = GamePlay.menu_class.new
    $scene = menu
    menu.send(:main_begin)
    30.times { menu.send(:update_graphics); Graphics.update }
    capture('menu')
    menu.send(:dispose)
    $scene = scene
    scene.spriteset.visible = true
    scene.spriteset.update
    raise 'Menu recreated overlay' unless sprite.equal?(initial)
    capture('menu_return')
    $game_player.moveto(53, 43)
    scene.spriteset.update
    pair('camera_moved')
    $game_player.moveto(20, -1)
    scene.spriteset.update
    old = sprite
    before = [old.x, old.y]
    link = Yuki::MapLinker.map_datas.find { |data| data.map_id == 27 }
    transfer(27, 20 + link.offset_x, -1 + link.offset_y)
    raise 'Linked overlay moved or recreated' unless sprite.equal?(old) && [sprite.x, sprite.y] == before
    capture('linked_route_border')
    [36, 80, 35, 23].each do |map|
      transfer(map, map == 23 ? 50 : 10, map == 23 ? 45 : 10)
      raise "Overlay leak #{map}" if map != 23 && sprite
      REPORT << {transfer: map, overlay: !!sprite, weather: $env.current_weather_db_symbol}
    end
    capture('reentry_night')
    # A fresh save expansion replaces the session manager, never serializes V6.
    previous_manager = BombanceAmbiance.manager
    loaded = GamePlay::Save.load('Saves/Pokemon_Party-1', no_load_parameter: true)
    loaded.expand_global_var
    loaded.load_parameters
    Yuki::MapLinker.reset
    $game_switches[Yuki::Sw::TJN_RealTime] = false
    $game_switches[Yuki::Sw::TJN_NoTime] = true
    $game_switches[Yuki::Sw::TJN_Enabled] = true
    $env.reset_zone
    $game_map.setup(23)
    $game_player.moveto(50, 45)
    hour(1380)
    scene.spriteset.update
    raise 'Session not replaced' if BombanceAmbiance.manager.equal?(previous_manager)
    raise 'Loaded night not immediate' unless sprite.opacity == 128
    capture('loaded_night')
    File.write(ForestGameProbe::OUTPUT + 'results.json', JSON.pretty_generate(REPORT))
    ForestGameProbe.stop('Native overlay scenarios passed')
  end
  def self.transfer(map, x, y)
    $game_temp.player_new_map_id = map
    $game_temp.player_new_x, $game_temp.player_new_y = x, y
    $game_temp.player_new_direction = 0
    $scene.send(:transfer_player)
    $scene.spriteset.update
  end
end

frames = logic = started = index = 0
armed = false
TracePoint.new(:call, :raise) do |tp|
  if tp.event == :raise && tp.path.include?('00026 Configuration Ambiance Bombance') && !tp.raised_exception.is_a?(Errno::ENOENT)
    ForestGameProbe.stop(tp.raised_exception.full_message, 1)
  elsif tp.event == :call && tp.method_id == :display_game_exception
    ForestGameProbe.stop("GAME EXCEPTION: #{$!}; #{$!&.backtrace&.first(12)}", 1)
  elsif tp.event == :call && tp.method_id == :update && defined?(BombanceAmbiance::MapLifecycle) &&
        tp.defined_class == BombanceAmbiance::MapLifecycle && tp.self.equal?($game_map)
    logic += 1
  elsif tp.event == :call && tp.method_id == :update && Object.const_defined?(:Graphics) && tp.self.equal?(Graphics)
    frames += 1
    ForestGameProbe.stop('Timeout', 1) if frames > 40000
    if !armed && frames > 120 && $scene.is_a?(Scene_Title)
      armed = true
      Interpreter.prepend(Module.new { def update; end })
      BombanceAchievements::Notifications.singleton_class.prepend(Module.new { def update(*); end }) if defined?(BombanceAchievements::Notifications)
      Battle::Scene::Message.prepend(Module.new { def update_wait_input_auto_skip; true; end })
      Battle::Visual.prepend(Module.new do
        def show_player_choice(index)
          pkmn = @scene.logic.battler(0, index)
          [:action, Battle::Actions::Attack.new(@scene, pkmn.skills_set.first, pkmn, 1, 0)]
        end
      end)
      Battle::Scene.prepend(Module.new do
        def return_to_last_scene
          super
          AmbientProbe.returned = true
        end
      end)
      state = GamePlay::Save.load('Saves/Pokemon_Party-1', no_load_parameter: true)
      state.expand_global_var
      state.load_parameters
      Yuki::MapLinker.reset
      $game_switches[Yuki::Sw::TJN_RealTime] = false
      $game_switches[Yuki::Sw::TJN_NoTime] = true
      $game_switches[Yuki::Sw::TJN_Enabled] = true
      $game_switches[Yuki::Sw::BT_NoExp] = true
      $env.reset_zone
      $game_map.setup(23)
      $game_player.refresh
      $game_player.moveto(50, 45)
      AmbientProbe.hour(AmbientProbe::TIMES[0])
      $scene.instance_variable_set(:@running, false)
      $scene = Scene_Map.new
      started = logic
    elsif armed && $scene.is_a?(Scene_Map) && $scene.spriteset
      if AmbientProbe.returned
        raise 'Battle return not immediately lit' unless AmbientProbe.sprite.opacity == 128
        AmbientProbe.capture('battle_first_return')
        AmbientProbe.finish
      elsif !AmbientProbe.battling && logic - started >= 241
        if index < AmbientProbe::TIMES.size
          AmbientProbe.pair(format('%02d_%02dh%02d', index, *AmbientProbe::TIMES[index].divmod(60)))
          index += 1
          if index < AmbientProbe::TIMES.size
            AmbientProbe.hour(AmbientProbe::TIMES[index])
          else
            AmbientProbe.hour(1380)
            $env.apply_weather(:rain)
          end
          started = logic
        else
          AmbientProbe.pair('rain_clouds')
          $env.apply_weather(:none)
          AmbientProbe.start_battle
        end
      end
    end
  end
end.enable
load './Game.rb'

