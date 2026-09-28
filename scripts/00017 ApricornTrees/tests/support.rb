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
        names = Marshal.load(File.binread(File.join(PROJECT, '../Data/Text/Dialogs/100012.fr.dat')))
        descriptions = Marshal.load(File.binread(File.join(PROJECT, '../Data/Text/Dialogs/100013.fr.dat')))
        hash = {}
        Dir[File.join(PROJECT, '../Data/Studio/items/*.json')].each do |path|
          data = JSON.parse(File.read(path))
          klass = data['klass'] == 'BallItem' ? Studio::BallItem : Item
          item = klass.new(data['dbSymbol'].to_sym, data['id'], data['socket'], names[data['id']],
                           descriptions[data['id']], data['icon'], 0)
          hash[item.db_symbol] = hash[item.id] = item
        end
        hash[:__undef__] = Item.new(:__undef__, -1, 0, '', '', '', 0)
        hash
      end
    end
  end
end

module Studio
  class BallItem < TestData::Item; end
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
def native_methods(klass, filename, names, scope: nil)
  path = File.join(NATIVE, filename)
  source = File.read(path)
  base_line = 0
  if scope
    start = source.index("class #{scope} ") || source.index("class #{scope}\n")
    raise "Native class not found: #{scope}" unless start
    base_line = source[0...start].count("\n")
    source = source[start...(source.index("\nclass ", start + 1) || source.size)]
  end
  lines = source.lines
  visit = lambda do |node|
    return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == :DEFN && names.include?(node.children.first)
      klass.class_eval(lines[(node.first_lineno - 1)..(node.last_lineno - 1)].join, path, base_line + node.first_lineno)
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
    Gender = 1
    EV_AccroBike = 17
    EV_Bicycle = 23
    EV_Run = 52
  end
end

module RPG; end
# Actual installed data classes, including EventCommand with NO initializer.
# Do not provide an RMXP-style constructor that PSDK itself does not provide.
dependencies_path = File.join(NATIVE, '0_Dependencies.rb')
dependencies_source = File.read(dependencies_path)
start = dependencies_source.index("  class Event\n")
finish = dependencies_source.index("  # Class representing a RMXP Map\n", start)
RPG.module_eval(dependencies_source[start...finish], dependencies_path, dependencies_source[0...start].count("\n") + 1)

def event_command(code = 0, indent = 0, parameters = [])
  RPG::EventCommand.new.tap do |command|
    command.code, command.indent, command.parameters = code, indent, parameters
  end
end

def event_page(commands, graphic: '', direction: 2, pattern: 0)
  RPG::Event::Page.new.tap do |page|
    page.condition = RPG::Event::Page::Condition.new
    page.graphic = RPG::Event::Page::Graphic.new
    page.graphic.tile_id, page.graphic.character_name, page.graphic.character_hue = 0, graphic, 0
    page.graphic.direction, page.graphic.pattern = direction, pattern
    page.graphic.opacity, page.graphic.blend_type = 255, 0
    page.move_type, page.move_speed, page.move_frequency = 0, 3, 3
    page.walk_anime, page.step_anime = true, false
    page.direction_fix, page.through, page.always_on_top = false, false, false
    page.trigger, page.list = 0, commands
  end
end

class Game_Event
  attr_reader :id, :original_map, :original_id, :event, :direction, :pattern, :character_name, :list
  attr_reader :erased
  attr_accessor :move_frequency
  def initialize(id, color, map: 1, original: id, name: 'Arbre route 1', commands: nil)
    @id, @original_map, @original_id = id, map, original
    commands ||= [event_command(108, 0, ["<apricorn_tree: #{color}>"]), event_command]
    @event = RPG::Event.new
    @event.id, @event.name, @event.pages = id, name, [event_page(commands)]
    @erased = false
    @can_parallel_execute = true
    refresh
  end
  def set_appearance(name, hue = 0); @character_name = name; end
  def update_pattern; @pattern = (@pattern + 1) % 4; end
end
native_methods(Game_Event, '4_Systems_003_Map_Engine.rb',
               %i[refresh refresh_page activated? clear_starting can_parallel_execute? check_event_trigger_auto start erase],
               scope: 'Game_Event')

class Game_Player
  attr_reader :state, :pattern, :character_name, :update_callback
  attr_reader :move_speed, :move_frequency
  attr_accessor :on_acro_bike
  def initialize
    @charset_base = 'player'
    @character_name = 'player_m_walk'
    @state = :walking
    @pattern, @direction, @prelock_direction = 0, 2, 0
    @move_speed, @move_frequency = 3, 4
  end
  def moving?; false; end
  def next_event_follower; nil; end
  def set_appearance(name); @character_name = name; end
  def look_to(id); end
end
File.readlines(File.join(NATIVE, '4_Systems_003_Map_Engine.rb')).each_with_index do |line, i|
  next unless line.match?(/^  (STATE_APPEARANCE_SUFFIX|STATE_MOVEMENT_INFO) =/)
  Game_Player.class_eval(line, File.join(NATIVE, '4_Systems_003_Map_Engine.rb'), i + 1)
end
native_methods(Game_Player, '4_Systems_003_Map_Engine.rb',
               %i[update_move_parameter update_appearance chara_by_state enter_in_walking_state enter_in_running_state
                  enter_in_surfing_state enter_in_cycling_state enter_in_acro_bike_state leave_cycling_state
                  cycling? return_to_previous_state], scope: 'Game_Player')
native_methods(Game_Player, '4_Systems_003_Map_Engine.rb', [:update_pattern_state], scope: 'Game_Character')

class Game_Map
  attr_accessor :map_id, :events, :need_refresh, :event_erased
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
  attr_accessor :text, :x, :y, :width, :height, :sizeid
  attr_reader :dispose_count
  alias multiline_text= text=
  def initialize(text); @text = text; end
  # Headless only. Real font metrics and wrapping are checked by native_box.rb.
  def text_width(value); value.length * 6; end
  def dispose
    @dispose_count = (@dispose_count || 0) + 1
    raise 'double text disposal' if @dispose_count > 1
  end
end
class FakeRect
  attr_reader :values
  def set(*values); @values = values; end
end
class FakeStack
  attr_reader :disposed
  def dispose; @disposed = true; end
end
class FakeSprite
  attr_accessor :data, :visible, :zoom_x, :zoom_y, :sy, :bitmap
  attr_reader :x, :y, :src_rect, :dispose_count
  def initialize(*)
    @src_rect = FakeRect.new
    @visible = true
    @sy = 0
  end
  def set_position(x, y); @x, @y = x, y; self; end
  def dispose
    @dispose_count = (@dispose_count || 0) + 1
    raise 'double sprite disposal' if @dispose_count > 1
  end
end
class SpriteSheet < FakeSprite; end
module UI
  class SpriteStack
    attr_reader :stack
    def initialize(*); @stack = []; end
    def push(x, y, bitmap, *args, type: FakeSprite, rect: nil)
      sprite = type.new(*args).set_position(x, y)
      sprite.bitmap = bitmap
      sprite.src_rect.set(*rect) if rect
      @stack << sprite
      sprite
    end
    def add_text(x, y, width, height, value, *args, sizeid: nil, **options)
      result = FakeText.new(value)
      result.x, result.y, result.width, result.height, result.sizeid = x, y, width, height, sizeid
      @stack << result
      result
    end
    def dispose
      @stack.each(&:dispose)
      @stack.clear
    end
  end
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
  class ItemSprite < FakeSprite; end
  class GenericBase
    class ControlButton < FakeSprite
      attr_accessor :text
    end
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
      break unless interpreter.running?
      fiber.resume
      ApricornTrees.test_tick += 0.025
      $game_player.send($game_player.update_callback) if $game_player.update_callback
      on_tick&.call
    end
    refute interpreter.running?, 'Harvest sequence must terminate'
    interpreter
  end
end
