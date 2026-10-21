# frozen_string_literal: true
# Isolated harness: real installed PSDK methods, no game boot or save writes.
require 'minitest/autorun'
require 'ostruct'
require 'json'

ROOT = File.expand_path('../../..', __dir__)
SDK = File.join(ROOT, 'scripts/psdk_scripts')
EXTENSION = File.expand_path('..', __dir__)

# Extract AST nodes, preserving source locations and lexical namespaces.
def installed(file, header, scope = Object, kind = :CLASS)
  path = File.join(SDK, file)
  lines = File.readlines(path, encoding: 'UTF-8')
  found = nil
  visit = lambda do |node|
    next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == kind && lines[node.first_lineno - 1].strip == header
      found ||= node
    else
      node.children.each { |child| visit.call(child) }
    end
  end
  visit.call(RubyVM::AbstractSyntaxTree.parse(lines.join))
  raise "Missing native node #{header}" unless found
  names = scope == Object ? [] : scope.name.split('::')
  prefix = names.each_index.map do |i|
    object = Object.const_get(names[0..i].join('::'))
    "#{object.is_a?(Class) ? 'class' : 'module'} #{names[i]};"
  end.join
  source = lines[(found.first_lineno - 1)..(found.last_lineno - 1)].join
  eval(prefix + source + "\n" + ('end;' * names.size), TOPLEVEL_BINDING, path, found.first_lineno)
end

module Kernel
  def log_data(*); end
  def parse_text(bank, id); TEST_TEXT.fetch(bank)[id]; end
  def parse_text_with_pokemon(bank, id, *); parse_text(bank, id); end
  def data_zone(*); OpenStruct.new(forced_weather: $forced_weather); end
  def each_data_type; []; end # Strong Winds initialization, no damage tests here.
end
TEST_TEXT = [18, 19].to_h do |id|
  [id, Marshal.load(File.binread(File.join(ROOT, "Data/Text/Dialogs/#{100000 + id}.fr.dat"))) ]
end
module GameData
  module SystemTags; end
end
module Yuki
  module Sw
    MixWeather = 39
    WT_Rain, WT_Sunset, WT_Sandstorm, WT_Snow, WT_Fog = 56, 57, 58, 59, 60
  end
end
module PFM; end
installed('4_Systems_202_Environment.rb', 'class Environment', PFM)
module Battle
  module Effects; end
  class Logic; end
  class Move; end
  class SceneHarnessBase
    def initialize(*); end
  end
  class Scene < SceneHarnessBase; end
  class Visual; end
end
module UI; end
installed('5_Battle_06_Effects.rb', 'class EffectBase', Battle::Effects)
installed('5_Battle_06_Effects.rb', 'class EffectsHandler', Battle::Effects)
load File.join(SDK, '5_Battle_06_Effects_06_Weather_Effects.rb')
# Native ability base/registry and the two classes exercised here.
ability_path = File.join(SDK, '5_Battle_06_Effects_04_Ability_Effects.rb')
ability_source = File.read(ability_path, encoding: 'UTF-8')
ability_base = ability_source.split('      # Class describing the Boosting Move Type ability effect').first
eval(ability_base + "\nend; end; end", TOPLEVEL_BINDING, ability_path)
%w[AirLock Drizzle].each { |name| installed('5_Battle_06_Effects_04_Ability_Effects.rb', "class #{name} < Ability", Battle::Effects::Ability) }
ability_source.lines.grep(/^      register\(:(air_lock|cloud_nine|drizzle),/).each do |line|
  Battle::Effects::Ability.class_eval(line, ability_path)
end
installed('5_Battle_04_Logic.rb', 'class ChangeHandlerBase', Battle::Logic)
installed('5_Battle_04_Logic.rb', 'class WeatherChangeHandler < ChangeHandlerBase', Battle::Logic)
%w[each_effects(*battlers) raw_weather_effect weather_effect weather_effects_disabled?].each do |header|
  installed('5_Battle_04_Logic.rb', "def #{header}", Battle::Logic, :DEFN)
end
%w[chance_of_hit(user,\ target) bypass_chance_of_hit?(user,\ target) accuracy_mod(user) evasion_mod(target)
   proceed_move_accuracy(user,\ targets) bypass_accuracy?(user,\ targets)].each do |header|
  installed('5_Battle_10_Move.rb', "def #{header}", Battle::Move, :DEFN)
end
installed('5_Battle_10_Move.rb', 'class Defog < Move', Battle::Move)
installed('5_Battle_10_Move.rb', 'class WeatherMove < Move', Battle::Move)
installed('5_Battle_01_Scene.rb', 'def show_enter_event', Battle::Scene, :DEFN)
class Battle::Logic::BattleEndHandler < Battle::Logic::ChangeHandlerBase; end
installed('5_Battle_04_Logic.rb', 'def handle_battle_end_weather_reset(players_creatures)', Battle::Logic::BattleEndHandler, :DEFN)

module Graphics
  class << self
    attr_accessor :time
    def current_time; @time ||= 0.0; end
    def width; 320; end
    def height; 240; end
  end
end
load File.join(SDK, '4_Systems_005_Animation.rb')
installed('5_Battle_02_Visual.rb', 'class WeatherSprite', UI)
%w[show_weather_animation(weather) wait_for_animation create_weather].each do |header|
  installed('5_Battle_02_Visual.rb', "def #{header}", Battle::Visual, :DEFN)
end

class Viewport
  def sort_z; end
  def dispose; @disposed = true; end
  def disposed?; !!@disposed; end
end
class Plane
  attr_accessor :bitmap, :z, :opacity, :ox, :oy, :zoom_x, :zoom_y
  attr_reader :viewport
  def initialize(viewport); @viewport = viewport; @ox = 0; end
  def set_origin(x, y); @ox, @oy = x, y; end
  def dispose
    raise 'Double disposal' if @disposed
    @disposed = true
  end
  def disposed?; !!@disposed; end
end
module RPG
  module Cache
    def self.animation(name)
      raise 'Unexpected asset' unless ['fog', 'bombance_weather/mist_wisps'].include?(name)
      (@textures ||= {})[name] ||= OpenStruct.new(width: 320, height: 240, disposed?: false)
    end
  end
end

class Battle::Logic
  attr_reader :scene, :bank_effects, :battlers
  attr_accessor :move_accuracy_rng
  def initialize(scene)
    @scene = scene
    @battlers = []
    @position_effects = Array.new(2) { Array.new(3) { [] } }
    @bank_effects = Array.new(2) { [] }
    @terrain_effects = []
    @move_accuracy_rng = Random.new(1)
  end
  def all_alive_battlers; @battlers; end
  def load_rng; end
  def load_battlers; end
  def battle_info; @scene.battle_info; end
  def allies_of(pkm); @battlers.select { |b| b != pkm && b.bank == pkm.bank }; end
  def field_terrain_effect; @neutral ||= Battle::Effects::EffectBase.new(self); end
  def weather_change_handler; @handler ||= WeatherChangeHandler.new(self, @scene); end
  def switch_handler; self; end
  def logic; self; end
  def execute_switch_events(who, with); with.ability_effect.on_switch_event(self, who, with); end
end
class Battle::Move
  attr_reader :logic, :scene
  attr_accessor :accuracy, :db_symbol
  def initialize(logic, accuracy = 100, symbol = :tackle)
    @logic, @scene, @accuracy, @db_symbol = logic, logic.scene, accuracy, symbol
  end
  def status?; false; end
  def ohko?; false; end
end
class Battle::Scene
  attr_reader :logic, :visual, :events, :weather_at_logic_creation, :battle_info
  def create_logic
    # Fixture send markers; actual transition/sending is outside this harness.
    @events = [:opponents_sent, :player_sent]
    logic = Battle::Logic.new(self)
    @weather_at_logic_creation = logic.raw_weather_effect.db_symbol
    logic
  end
  def create_visual; Battle::Visual.new(self); end
  def create_ais; []; end
  def create_message_proc; end
  def load_events(*); end
  def display_message_and_wait(message); @events << message; end
  def zv_log_message(message); @events << [:log, message]; end
  def call_event(event); @events << event unless event == :logic_init; end
  def scene_update_proc
    @frames = (@frames || 0) + 1
    raise 'Animation did not terminate' if @frames > 1200
    Graphics.time = Graphics.current_time + 1.0 / 60
    @visual.update
  end
end
installed('5_Battle_01_Scene.rb', 'def initialize(battle_info)', Battle::Scene, :DEFN)
class Battle::Visual
  attr_reader :viewport, :weather, :wait_frames
  def initialize(scene)
    @scene, @viewport = scene, Viewport.new
    @animations, @animatable = [], []
    create_weather
    @scene_update_proc = scene.method(:scene_update_proc)
  end
  def update; @weather.update; end
  def dispose; @viewport.dispose; end
  def lock; @locking = true; end
  def unlock; @locking = false; end
  def locking?; @locking; end
  def scene_update_proc; @scene.scene_update_proc; end
  def show_ability(pkm); @scene.events << [:ability, pkm.ability_effect.db_symbol]; end
  def zv_show_miss_animation(pkm); @scene.events << [:miss, pkm]; end
end
class TestBattler
  attr_accessor :acc_stage, :eva_stage, :bank, :position, :ability_effect, :effects, :boss_effects
  attr_reader :status_effect, :item_effect
  def initialize(logic, bank = 0)
    @bank, @position, @acc_stage, @eva_stage = bank, 0, 0, 0
    @effects = Battle::Effects::EffectsHandler.new
    @boss_effects = []
    @status_effect = @item_effect = Battle::Effects::EffectBase.new(logic)
    @ability_effect = Battle::Effects::Ability.new(logic, self, :none)
  end
  def spd_basis; 100; end
  alias spd spd_basis
  def has_ability?(symbol); ability_effect.db_symbol == symbol; end
  def type_poison?; false; end
  def hold_item?(*); false; end
end
installed('5_Battle_03_PokemonBattler.rb', 'def stat_multiplier_acceva(stage)', TestBattler, :DEFN)
module Configs
  def self.zv_battle_msg; @zv ||= OpenStruct.new(replace_miss: true); end
end
load File.join(ROOT, 'scripts/00000 Plugins/00017 cc-pokemon-boss-system/3 Battle/04 Logic/001 BossEffectDispatch.rb')
load File.join(ROOT, 'scripts/00000 Plugins/00007 ZVBattleMessages/60 Moves/120 Procedure.rb')
load File.join(EXTENSION, '00001 WeatherIntegration.rb')
load File.join(EXTENSION, '00002 FogVisual.rb')

class WeatherTest < Minitest::Test
  def setup
    Graphics.time = 0.0
    Clock.main.reset
    $scene = nil
    $options = OpenStruct.new(show_animation: false)
    $game_temp = OpenStruct.new(in_battle: false)
    $game_switches = Hash.new(false)
    state = OpenStruct.new(game_temp: $game_temp, game_switches: $game_switches,
                           game_map: OpenStruct.new(need_refresh: false))
    $env = PFM::Environment.new(state)
    $forced_weather = nil
    Configs.zv_battle_msg.replace_miss = true
  end

  def battle(weather = :fog)
    $env.apply_weather(weather)
    @scene = $scene = Battle::Scene.new(OpenStruct.new(vs_type: 1, trainer_battle?: false, battle_id: 0))
    @logic = @scene.logic
    @user = TestBattler.new(@logic)
    @target = TestBattler.new(@logic, 1)
    @logic.battlers.push(@user, @target)
    @move = Battle::Move.new(@logic)
    @scene
  end

  def enter; @scene.send(:show_enter_event); end
  def fog_layer; @scene.visual.instance_variable_get(:@bombance_fog_layer); end
  def change(weather); @logic.weather_change_handler.weather_change_with_process(weather, 5); end
  def chance; @move.chance_of_hit(@user, @target); end
end
