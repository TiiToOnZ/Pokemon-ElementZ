# frozen_string_literal: true
# Real Game.rb/Studio Ruby capture harness. Save read only, forest in RAM.
# No input, event execution, saves or asset changes. Only named PNG/report output.
require 'json'
module ForestGameProbe
  ROOT = File.expand_path('../../../..', __dir__)
  OUTPUT = File.expand_path('captures_leaves_continuity', __dir__) + '/'
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

# All automation below is confined to this test process. Native battle logic,
# attacks, animations, scene teardown and return are executed by Game.rb.
module LeavesProbe
  class << self
    attr_accessor :battle_kind, :before, :returned, :performance
  end
  self.performance = { calls: 0, seconds: 0.0, max_seconds: 0.0 }
  REPORT = []
  def self.leaves
    $scene.spriteset.instance_variable_get(:@ambiance_leaves)
  end
  def self.capture(name)
    bitmap = Graphics.snap_to_bitmap
    File.binwrite(ForestGameProbe::OUTPUT + name + '.png', bitmap.to_png)
    bitmap.dispose
    renderer = $scene.is_a?(Scene_Map) && $scene.spriteset && leaves
    REPORT << { name: name, scene: $scene.class.name, map: $game_map.map_id,
      camera: [$game_map.display_x, $game_map.display_y],
      tick: BombanceAmbiance.manager.leaves_tick,
      visible: renderer && renderer.sprites.count(&:visible),
      particles: renderer && renderer.particles.map(&:to_a),
      sprites: renderer && renderer.sprites.map { |s| [s.x, s.y, s.opacity, s.visible] } }
    STDERR.puts "Captured #{name}"
  end
  def self.start_battle(kind)
    self.battle_kind = kind
    self.before = leaves.particles.map(&:to_a)
    capture("#{kind}_before")
    if kind == :defeat
      $actors.replace([PFM::Pokemon.generate_from_hash(id: :caterpie, level: 2, moves: [:tackle], no_shiny: true)])
      $game_temp.battle_can_lose = false
      $game_variables[Yuki::Var::E_Return_ID] = 23
      $game_variables[Yuki::Var::E_Return_X] = 10
      $game_variables[Yuki::Var::E_Return_Y] = 10
    end
    info = Battle::Logic::BattleInfo.new
    info.add_party(0, *info.player_basic_info)
    enemy = PFM::Pokemon.generate_from_hash(id: :caterpie, level: 2, moves: [:tackle], no_shiny: true)
    enemy = PFM::Pokemon.generate_from_hash(id: :mewtwo, level: 100, moves: [:tackle], no_shiny: true) if kind == :defeat
    if kind == :capture
      $options.catch_rename = false
      $pokedex.mark_captured(enemy.id, enemy.form)
      $bag.add_item(:master_ball, 1)
    end
    if kind == :trainer
      trainer = data_trainer(1)
      info.add_party(1, [enemy], trainer.name, trainer.class_name, trainer.resources, PFM::Bag.new, 0, 0)
    else
      info.add_party(1, [enemy], nil, nil, nil, nil, nil, 0)
    end
    $scene.send(:setup_start_battle, Battle::Scene, info)
    raise 'No battle snapshot' unless BombanceAmbiance.manager.instance_variable_get(:@leaves_battle)
  end
  def self.install
    Interpreter.prepend(Module.new { def update; end })
    if defined?(BombanceAchievements::Notifications)
      BombanceAchievements::Notifications.singleton_class.prepend(Module.new { def update(*); end })
    end
    Battle::Scene::Message.prepend(Module.new do
      def update_wait_input_auto_skip; true; end
    end)
    Battle::Visual.prepend(Module.new do
      def show_player_choice(index)
        return [:flee, nil] if LeavesProbe.battle_kind == :flee
        pokemon = @scene.logic.battler(0, index)
        if LeavesProbe.battle_kind == :capture
          wrapper = PFM::ItemDescriptor.actions(:master_ball)
          return [:action, Battle::Actions::Item.new(@scene, wrapper, pokemon.bag, pokemon)]
        end
        [:action, Battle::Actions::Attack.new(@scene, pokemon.skills_set.first, pokemon, 1, 0)]
      end
    end)
    Battle::Scene.prepend(Module.new do
      def battle_end
        result = @logic.battle_result
        caught = !battle_info.caught_pokemon.nil?
        raise 'Capture failed' if LeavesProbe.battle_kind == :capture && !caught
        super
        LeavesProbe::REPORT << { battle: LeavesProbe.battle_kind, result: result, caught: caught }
        if LeavesProbe.battle_kind == :defeat
          raise 'Defeat did not teleport' unless result == 2 && $game_map.map_id == 23
          raise 'Defeat kept stale snapshot' if BombanceAmbiance.manager.instance_variable_get(:@leaves_battle)
          LeavesProbe.returned = true
        end
      end
    end)
    BombanceAmbiance::FallingLeaves.prepend(Module.new do
      def initialize(viewport, manager)
        super
        if LeavesProbe.battle_kind
          raise 'First map renderer did not restore exact particles' unless particles.map(&:to_a) == LeavesProbe.before
          raise 'No immediately visible leaves' unless sprites.count(&:visible) >= 12
          raise 'Snapshot not consumed' if manager.instance_variable_get(:@leaves_battle)
          LeavesProbe.returned = true
        end
      end
      def update(manager)
        fresh = manager.leaves_tick != tick
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        super
        if fresh
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          perf = LeavesProbe.performance
          perf[:calls] += 1
          perf[:seconds] += elapsed
          perf[:max_seconds] = [perf[:max_seconds], elapsed].max
        end
      end
    end)
  end

  def self.check_ui_and_transfers
    scene = $scene
    transfers = []
    [35, 25, 23, 27, 36, 80, 35].each do |map|
      $game_temp.player_new_map_id = map
      $game_temp.player_new_x = map == 35 ? 35 : 10
      $game_temp.player_new_y = map == 35 ? 67 : 10
      $game_temp.player_new_direction = 0
      scene.send(:transfer_player)
      scene.spriteset.update
      active = leaves
      raise "Leaves on wrong map #{map}" unless !!active == (map == 35)
      camera_y = $game_map.display_y / 8.0 + BombanceAmbiance.manager.state.anchor_y * 16
      raise 'Normal entry resumed battle snapshot' if active && active.particles.any? { |p| p.y >= camera_y }
      transfers << {map: map, pool: active&.sprites&.size, weather: $env.current_weather_db_symbol}
    end
    capture('normal_reentry')
    1200.times { $game_map.update; scene.spriteset.update }
    before = leaves.particles.map(&:to_a)
    ids = leaves.sprites.map(&:object_id)
    scene.send(:setup_message_display, 'Les feuilles poursuivent leur chute...', 1, [])
    message = scene.instance_variable_get(:@message_window)
    raise 'Dialogue below leaves' unless message.viewport.z > scene.spriteset.map_viewport.z
    90.times { scene.send(:message_update); Graphics.update }
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
    raise 'Menu/dialogue altered particles' unless before == leaves.particles.map(&:to_a)
    raise 'Menu/dialogue replaced sprites' unless ids == leaves.sprites.map(&:object_id)
    capture('menu_return')
    REPORT << {transfers: transfers, menu_dialogue_preserved: true}
  end
end

stages = [['entry', 1, 35, 67], ['stationary_00', 1200, 35, 67],
          ['motion_15', 15, 35, 67], ['motion_30', 15, 35, 67], ['motion_45', 15, 35, 67],
          ['camera_right', 1, 40, 67], ['camera_left', 1, 35, 67],
          ['camera_up', 1, 35, 62], ['camera_down', 1, 35, 67],
          ['camera_diagonal', 1, 40, 72], ['camera_return', 1, 35, 67],
          ['settled', 600, 35, 67]]
frames = logic = started = index = 0
armed = false
battles = [:wild, :trainer, :flee, :capture, :defeat]
captured_battle = nil
TracePoint.new(:call, :raise) do |tp|
  if tp.event == :raise && tp.path.include?('00026 Configuration Ambiance Bombance') &&
     !tp.raised_exception.is_a?(Errno::ENOENT)
    ForestGameProbe.stop("#{tp.raised_exception.full_message}", 1)
  elsif tp.event == :call && tp.method_id == :display_game_exception
    ForestGameProbe.stop("GAME EXCEPTION: #{$!}; #{$!&.backtrace&.first(12)}", 1)
  elsif tp.event == :call && tp.method_id == :update && defined?(BombanceAmbiance::MapLifecycle) &&
        tp.defined_class == BombanceAmbiance::MapLifecycle && tp.self.equal?($game_map)
    logic += 1
  elsif tp.event == :call && tp.method_id == :update && Object.const_defined?(:Graphics) && tp.self.equal?(Graphics)
    frames += 1
    ForestGameProbe.stop('Timeout', 1) if frames > 60000
    if !armed && frames > 120 && $scene.is_a?(Scene_Title)
      armed = true
      LeavesProbe.install
      state = GamePlay::Save.load('Saves/Pokemon_Party-1', no_load_parameter: true)
      state.expand_global_var
      state.load_parameters
      Yuki::MapLinker.reset
      $game_switches[Yuki::Sw::TJN_RealTime] = false
      $game_switches[Yuki::Sw::TJN_NoTime] = true
      $game_switches[Yuki::Sw::TJN_Enabled] = true
      $game_switches[Yuki::Sw::BT_NoExp] = true
      $game_variables[Yuki::Var::TJN_Hour] = 15
      $game_variables[Yuki::Var::TJN_Min] = 0
      $env.reset_zone
      $game_map.setup(35)
      $actors.replace([PFM::Pokemon.generate_from_hash(id: :mewtwo, level: 100, moves: [:tackle], no_shiny: true)])
      $game_player.refresh
      $game_player.moveto(35, 67)
      Yuki::TJN.force_update_tone
      $scene.instance_variable_set(:@running, false)
      $scene = Scene_Map.new
      started = logic
    elsif armed && $scene.is_a?(Battle::Scene)
      if $scene.message_window && captured_battle != LeavesProbe.battle_kind
        LeavesProbe.capture("#{LeavesProbe.battle_kind}_battle")
        captured_battle = LeavesProbe.battle_kind
      end
    elsif armed && $scene.is_a?(Scene_Map) && $scene.spriteset
      if LeavesProbe.returned
        LeavesProbe.capture("#{LeavesProbe.battle_kind}_first_return")
        LeavesProbe.returned = false
        LeavesProbe.battle_kind = nil
        if battles.empty?
          LeavesProbe.check_ui_and_transfers
          perf = LeavesProbe.performance
          perf[:average_ms] = perf[:seconds] * 1000 / perf[:calls]
          File.write(ForestGameProbe::OUTPUT + 'results.json', JSON.pretty_generate(captures: LeavesProbe::REPORT, performance: perf))
          ForestGameProbe.stop(JSON.generate(perf))
        end
        LeavesProbe.start_battle(battles.shift)
      elsif index < stages.size && logic - started >= stages[index][1]
        LeavesProbe.capture(stages[index][0])
        index += 1
        if index == stages.size
          LeavesProbe.start_battle(battles.shift)
        else
          $game_player.moveto(*stages[index].last(2))
          started = logic
        end
      end
    end
  end
end.enable
load './Game.rb'

