# frozen_string_literal: true
# Headless integration harness. Loads actual native GameState, Bag, Interpreter
# methods and CraftSystem; substitutes graphics/input only. Never opens saves.
require 'minitest/autorun'
require 'json'
require 'csv'
require 'ostruct'

PROJECT = File.expand_path('../..', __dir__)
NATIVE = File.join(PROJECT, 'psdk_scripts')
SYSTEM = File.expand_path('..', __dir__)
$tester = true
$test_log = []

module Kernel
  def log_error(text)
    $test_log << text
  end

  def data_item(item)
    TestData.items.fetch(item) { TestData.items.fetch(:__undef__) }
  end
end

module TestData
  Item = Struct.new(:db_symbol, :id, :socket, :name, :description, :icon, :position)
  class << self
    def items
      @items ||= begin
        names = CSV.parse(File.read(File.join(PROJECT, '../Data/Text/Dialogs/100012.csv'), encoding: 'bom|utf-8').gsub("\r\n", "\n"))
        hash = {}
        Dir[File.join(PROJECT, '../Data/Studio/items/*.json')].each do |path|
          data = JSON.parse(File.read(path))
          item = Item.new(data['dbSymbol'].to_sym, data['id'], data['socket'], names[data['id'] + 1]&.[](1),
                          "Description de #{data['dbSymbol']}", data['icon'], 0)
          hash[item.db_symbol] = hash[item.id] = item
        end
        hash[:__undef__] = Item.new(:__undef__, -1, 0, '', '', '', 0)
        hash
      end
    end
  end
end

module Configs
  class << self
    def settings
      @settings ||= OpenStruct.new(max_bag_item_count: 999)
    end

    def recipes
      @recipes ||= begin
        raw = JSON.parse(File.read(File.join(PROJECT, '../Data/configs/crafting_config.json')), symbolize_names: true)
        OpenStruct.new(raw)
      end
    end
  end
end

module PFM
  class << self
    attr_accessor :game_state, :bag_class
  end
  module ItemDescriptor
    HANDLERS = {}
    def self.define_bag_use(item, before = false, &block)
      HANDLERS[item] = [before, block]
    end
  end
end
load File.join(NATIVE, '4_Systems_000_General_3_GameState.rb')
bag_file = File.join(NATIVE, '4_Systems_103_Bag.rb')
source = File.read(bag_file)
eval(source[source.index("module PFM\n")...source.index('PFM.bag_class =')], TOPLEVEL_BINDING, bag_file)
PFM.bag_class = PFM::Bag

class QuestRecorder
  attr_reader :acquisitions
  def initialize
    @acquisitions = []
  end
  def add_item(item, amount)
    @acquisitions << [item, amount]
  end
end

# Import real native methods by their Ruby AST boundaries, not rewritten copies.
def native_methods(klass, filename, names)
  path = File.join(NATIVE, filename)
  source = File.read(path)
  lines = source.lines
  visit = lambda do |node|
    return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == :DEFN && names.include?(node.children.first)
      klass.class_eval(lines[(node.first_lineno - 1)..(node.last_lineno - 1)].join, path, node.first_lineno)
    end
    node.children.each { |child| visit.call(child) }
  end
  visit.call(RubyVM::AbstractSyntaxTree.parse(source))
end

# initialize/clear appear on many RMXP classes, so extract only Interpreter_RMXP.
interpreter_source = File.read(File.join(NATIVE, '1_RMXP_Scripts.rb'))
start = interpreter_source.index('class Interpreter_RMXP')
finish = interpreter_source.index('class Game_SelfVariables', start)
eval(interpreter_source[start...finish], TOPLEVEL_BINDING, File.join(NATIVE, '1_RMXP_Scripts.rb'))
class Interpreter < Interpreter_RMXP
  attr_reader :messages
  def message(text, *)
    (@messages ||= []) << text
  end
  def add_item_show_message_got(item, *)
    message("obtained:#{item}")
  end
end
native_methods(Interpreter, '2_PSDK_Event_Interpreter.rb', %i[current_time trigger_event_in timed_event_remaining_time set_self_switch])

module Yuki
  module Sw
    TJN_RealTime = 7
  end
end

module RPG
  class EventCommand
    attr_reader :code, :parameters
    def initialize(code = 0, indent = 0, parameters = [])
      @code, @parameters = code, parameters
    end
  end
end

class Game_Event
  attr_reader :id, :original_map, :original_id, :event, :direction, :pattern, :character_name, :list
  def initialize(id, color, map: 1, original: id, name: 'Arbre route 1', commands: nil)
    @id, @original_map, @original_id = id, map, original
    commands ||= [RPG::EventCommand.new(108, 0, ["<apricorn_tree: #{color}>"]), RPG::EventCommand.new]
    @event = OpenStruct.new(name: name, pages: [OpenStruct.new(list: commands)])
    refresh
  end
  def refresh
    new_page = @event.pages.last
    return if @page == new_page
    @page = new_page
    @list = @page&.list
  end
  def activated?; !@page.nil?; end
  def erased; false; end
  def set_appearance(name); @character_name = name; end
  def update_pattern; @pattern = (@pattern + 1) % 4; end
end

class Game_Player
  STATE_APPEARANCE_SUFFIX = {walking: '_walk'}
  STATE_MOVEMENT_INFO = {walking: [3, 4]}
  attr_reader :state, :pattern, :character_name, :update_callback
  def initialize
    @charset_base = 'player'
    @character_name = 'player_m_walk'
    @state = :walking
  end
  def cycling?; false; end
  def update_move_parameter(state); end
  def update_appearance(pattern = 0)
    @pattern = pattern
    @character_name = "player_m#{STATE_APPEARANCE_SUFFIX[@state]}"
  end
  def set_appearance(name); @character_name = name; end
  def enter_in_walking_state
    @state = :walking
    update_appearance(0)
  end
  def look_to(id); end
end

class Game_Map
  attr_accessor :map_id, :events, :need_refresh
  def initialize
    @map_id, @events = 1, {}
  end
  def update; end
end

module Input
  class << self
    attr_accessor :key
    def trigger?(key); @key == key; end
    alias repeat? trigger?
  end
end

class FakeText
  attr_accessor :text
  alias multiline_text= text=
  def initialize(text); @text = text; end
end
class FakeRect
  attr_reader :values
  def set(*values); @values = values; end
end
class FakeStack
  attr_reader :disposed
  def dispose; @disposed = true; end
end
module UI
  class Window
    attr_accessor :active
    attr_reader :texts, :icons, :cursor_rect, :sprite_stack
    def initialize(*)
      @texts, @icons, @cursor_rect = [], [], FakeRect.new
      @sprite_stack = FakeStack.new
    end
    def add_text(x, y, w, h, text, *args, **opts)
      @texts << (result = FakeText.new(text))
      result
    end
    def push(*args, type:, **opts)
      @icons << (result = type.new)
      result
    end
    def load_cursor; end
    def dispose; @disposed = true; end
    def disposed?; @disposed; end
  end
  class ItemSprite
    attr_accessor :data
  end
  class GenericBase
    def initialize(*); end
    def update_background_animation; end
    def dispose; end
  end
end
module GamePlay
  class BaseCleanUpdate
    class FrameBalanced
      def initialize; @disposables = []; end
      def play_cursor_se; end
      def play_cancel_se; end
      def create_viewport; @viewport = Object.new; end
      def add_disposable(*objects); @disposables.concat(objects); end
      def dispose
        @disposables.each { |object| object.dispose unless object.disposed? }
      end
    end
  end
end

PFM::GameState::ON_INITIALIZE.select! { |key, _| key == :bag }
PFM::GameState::ON_PLAYER_INITIALIZE.select! { |key, _| key == :user_data }
PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.select! { |key, _| %i[user_data bag].include?(key) }
class PFM::GameState
  attr_accessor :quests, :trainer
  def load_parameters; end
  on_player_initialize(:test_context) do
    @trainer = OpenStruct.new(current_version: 6716)
    @quests = QuestRecorder.new
  end
end

crafting_path = File.join(PROJECT, '00000 Plugins/00002 Crafting')
%w[000_PFM.rb 003_Recipes.rb 003_Systems.rb].each { |file| load File.join(crafting_path, file) }
Dir[File.join(SYSTEM, '*.rb')].sort.each { |path| load path }

module ApricornTrees
  class << self
    attr_accessor :test_time, :test_tick
    def now; test_time; end
    def monotonic; test_tick; end
  end
end

class ApricornTest < Minitest::Test
  def setup
    ApricornTrees.cancel_session
    ApricornTrees.test_time = Time.new(2026, 9, 27, 12, 0, 0, '+02:00')
    ApricornTrees.test_tick = 0.0
    ApricornTrees::ACQUISITION_HOOKS.clear
    $game_map = Game_Map.new
    $game_player = Game_Player.new
    $game_temp = OpenStruct.new(player_transferring: false)
    $game_self_switches = Hash.new(false)
    $game_switches = Hash.new(false)
    $options = OpenStruct.new(language: 'fr')
    PFM.game_state = PFM::GameState.new
    Configs.settings.max_bag_item_count = 999
    Input.key = nil
    $test_log.clear
  end

  def tree(color = :red, id: 1, map: 1, original: id)
    event = Game_Event.new(id, color, map: map, original: original)
    $game_map.events[id] = event
    ApricornTrees::ApricornTree.new(event)
  end

  def run_sequence(tree, &on_tick)
    interpreter = Interpreter.new
    interpreter.setup(nil, tree.event.id, proc { apricorn_tree_sequence(tree) })
    fiber = interpreter.instance_variable_get(:@fiber)
    150.times do
      break unless fiber.alive?
      fiber.resume
      ApricornTrees.test_tick += 0.025
      $game_player.send($game_player.update_callback) if $game_player.update_callback
      on_tick&.call
    end
    refute fiber.alive?, 'Harvest sequence must terminate'
    interpreter
  end
end
