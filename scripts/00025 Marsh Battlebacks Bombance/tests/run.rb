# Run: ruby tests/run.rb [project_root]
# Uses the installed PSDK methods and LiteRGSS textures; no game window/save writes.
require 'json'
require 'ostruct'
require 'digest'

PROJECT = File.expand_path(ARGV[0] || '../../..', __dir__)
SCRIPTS = File.join(PROJECT, 'scripts')
SDK = File.join(SCRIPTS, 'psdk_scripts')
Dir.chdir(PROJECT)
$checks = 0
def check(condition, message)
  $checks += 1
  raise message unless condition
end
def log_debug(*); end
def log_error(message); raise message; end

# Extract complete methods from the installed sources, not reimplementations.
def native_method(path, name)
  text = File.read(path, encoding: 'UTF-8')
  visit = lambda do |node|
    next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    next node if node.type == :DEFN && node.children.first == name
    node.children.each do |child|
      found = visit.call(child)
      return found if found
    end
    nil
  end
  node = visit.call(RubyVM::AbstractSyntaxTree.parse(text))
  raise "Missing native method #{name}" unless node
  text.lines[(node.first_lineno - 1)..(node.last_lineno - 1)].join
end
def import_methods(target, path, names, module_functions: false)
  code = names.map { |name| native_method(path, name) }.join("\n")
  code = "module_function\n" + code if module_functions
  target.module_eval(code, path)
end

module GameData; module SystemTags; end; end
engine = File.join(SDK, '4_Systems_003_Map_Engine.rb')
import_methods(GameData::SystemTags, engine, [:gen], module_functions: true)
GameData::SystemTags.module_eval(File.readlines(engine).grep(/^    \w+ = gen /).join)
module Yuki; module Sw; end; end
dependencies = File.join(SDK, '0_Dependencies.rb')
switch_names = %w[TJN_Enabled Env_CanFly TJN_MorningTime TJN_DayTime TJN_SunsetTime TJN_NightTime]
Yuki::Sw.module_eval(File.readlines(dependencies).select { |line| switch_names.any? { |key| line.match?(/^\s*#{key} =/) } }.join)
module PFM
  class Environment
    include GameData::SystemTags
  end
end
import_methods(PFM::Environment, File.join(SDK, '4_Systems_202_Environment.rb'),
               %i[grass? tall_grass? very_tall_grass? cave? mount? sand? pond? sea? under_water? ice? snow? get_zone_type])
module Battle
  BATTLE_CAMERA_3D = false
  module Logic; class BattleInfo; end; end
  class Visual; end
  class Visual3D < Visual; end
  module BattleBases; end
end
logic = File.join(SDK, '5_Battle_04_Logic.rb')
Battle::Logic::BattleInfo.class_eval(File.readlines(logic).grep(/^      (BACKGROUND_NAMES|TIMED_BACKGROUND_SUFFIXES) =/).join)
import_methods(Battle::Logic::BattleInfo, logic, %i[find_background_name_to_display background_name_suggestions background_name_suggestions_for timed_background_names system_tag_background_name trainer_background_name])
Battle::Logic::BattleInfo.send(:private, :system_tag_background_name)
ORIGINAL_FAMILY = Battle::Logic::BattleInfo.instance_method(:system_tag_background_name)
ORIGINAL_RESOLVER = Battle::Logic::BattleInfo.instance_method(:find_background_name_to_display)
TIME_RESOLVER = Battle::Logic::BattleInfo.instance_method(:timed_background_names)

# Load real Texture and Cache code. Virtual archives are unnecessary for these disk assets.
binary_root = File.join(ENV.fetch('LOCALAPPDATA'), 'Programs/pokemon-studio/resources/psdk-binaries')
require File.join(binary_root, 'lib/LiteRGSS')
texture_source = File.read(dependencies)[/class Texture < LiteRGSS::Bitmap.*?(?=^# Class that stores)/m]
eval(texture_source, TOPLEVEL_BINDING, dependencies)
module RPG
  module Cache
    Common_filename = 'Graphics/%s/%s'
    Common_filename_format = 'Graphics/%s/%s.png'
    BattleBacks_Path = 'battlebacks'
    Notification_title = 'Failed to load graphic'
    GIF_EXTENSION = '.gif'
  end
end
import_methods(RPG::Cache, dependencies, %i[test_file_existence load_image load_image_from_file_data battleback_exist? battleback], module_functions: true)
RPG::Cache.instance_variable_set(:@battleback_cache, {})

# Native BBBB selectors + the actual Bombance single/double/triple resolver.
bbbb = File.join(SCRIPTS, '00000 Plugins/00010 bbbb/9999 BBBB.rb')
import_methods(Battle::BattleBases, bbbb, %i[side_key base_asset default_base_filename config], module_functions: true)
Battle::BattleBases.instance_variable_set(:@config, JSON.parse(File.read('Data/configs/plugins/battle_bases_config.json'), symbolize_names: true))
load File.join(SCRIPTS, '00020 Battle Bases Bombance/001 BattleBasesExtension.rb')
load File.expand_path('../001 MarshBattlebacks.rb', __dir__)

player = Struct.new(:system_tag).new(GameData::SystemTags::TGrass)
$game_switches = Hash.new(false)
$game_switches[10] = $game_switches[20] = true
state = Struct.new(:game_player, :game_switches).new(player, $game_switches)
$env = PFM::Environment.allocate
$env.instance_variable_set(:@game_state, state)
$game_map = Struct.new(:map_id).new(35)
info = Battle::Logic::BattleInfo.allocate
info.instance_variable_set(:@background_name, '')
info.instance_variable_set(:@battlers, [[], []])
resolve = -> { info.find_background_name_to_display { |name| RPG::Cache.battleback_exist?(name) } }
maps = [35, 36, 78, 80]
periods = { morning: 13, day: 11, sunset: 14, night: 12 }
periods.each do |period, switch|
  [11, 12, 13, 14].each { |id| $game_switches[id] = id == switch }
  texture = RPG::Cache.battleback("back_marsh_#{period}")
  check(texture.is_a?(Texture) && texture.width > 32 && texture.height > 32, "Marsh PNG load #{period}")
  maps.each do |map|
    $game_map.map_id = map
    check(resolve.call == "back_marsh_#{period}", "#{map}/Grass/#{period}")
    check(player.system_tag == GameData::SystemTags::TGrass, 'tag mutated')
    [1, 2, 3].each do |capacity|
      controller = BombanceBattleBases::Controller.allocate
      controller.instance_variable_set(:@asset_cache, {})
      controller.instance_variable_set(:@resource_path, nil)
      controller.instance_variable_set(:@background_name, resolve.call)
      [0, 1].each do |bank|
        side = bank.zero? ? 'player' : 'enemy'
        suffix = { 1 => '', 2 => '_double', 3 => '_triple' }.fetch(capacity)
        check(controller.send(:resolve_asset, bank, capacity) == "default_bases/#{side}_base#{suffix}", "BBBB #{map}/#{period}/#{capacity}/#{bank}")
      end
    end
  end
  $game_map.map_id = 27 # Route 1: Data/Studio/maps/map027.json -> 029 Route_1.
  check(resolve.call == "back_tall_grass_#{period}", "Route 1 Grass unchanged #{period}")
  [1, 34, 37, 77, 79, 81].each do |map|
    $game_map.map_id = map
    check(info.send(:system_tag_background_name) == ORIGINAL_FAMILY.bind(info).call, "Other map #{map}")
  end
  maps.each do |map|
    $game_map.map_id = map
    [0, *GameData::SystemTags.constants.reject { |name| name == :TGrass }.map { |name| GameData::SystemTags.const_get(name) }].uniq.each do |tag|
      player.system_tag = tag
      check(info.send(:system_tag_background_name) == ORIGINAL_FAMILY.bind(info).call, "Other tag #{tag} on #{map}")
    end
    player.system_tag = GameData::SystemTags::TGrass
  end
  Battle.send(:remove_const, :BATTLE_CAMERA_3D)
  Battle.const_set(:BATTLE_CAMERA_3D, true)
  maps.each do |map|
    $game_map.map_id = map
    check(info.send(:system_tag_background_name) == ORIGINAL_FAMILY.bind(info).call, "3D #{map}/#{period}")
    check(resolve.call == "back_tall_grass_#{period}", "3D name #{map}/#{period}")
  end
  Battle.send(:remove_const, :BATTLE_CAMERA_3D)
  Battle.const_set(:BATTLE_CAMERA_3D, false)
  puts "PASS #{period}: four maps, Route 1, other maps/tags, BBBB 1/2/3 and 3D"
end
$game_map.map_id = 35
info.instance_variable_set(:@background_name, 'back_grass')
check(resolve.call == 'back_grass_night', 'Explicit native override priority lost')
info.instance_variable_set(:@background_name, '')
[10, 20].each do |gate|
  $game_switches[gate] = false
  check(info.send(:system_tag_background_name) == ORIGINAL_FAMILY.bind(info).call, 'Inactive time must preserve native family')
  $game_switches[gate] = true
end
check(Battle::Logic::BattleInfo.instance_method(:timed_background_names) == TIME_RESOLVER, 'Native time resolver replaced')
check(Battle::Logic::BattleInfo.instance_method(:find_background_name_to_display) == ORIGINAL_RESOLVER, 'Native resolution replaced')
check(Battle::Logic::BattleInfo.private_method_defined?(:system_tag_background_name), 'Patch visibility')
puts "PASS: #{$checks} assertions. Headless integration; visual rendering still requires an in-game check."
