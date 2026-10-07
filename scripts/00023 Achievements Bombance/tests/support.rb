# frozen_string_literal: true
# No game boot, real save loading, disk save, or Studio-data modification.
require 'minitest/autorun'
require 'json'
require 'ostruct'

ROOT = File.expand_path('../..', __dir__)
NATIVE = File.join(ROOT, 'psdk_scripts')
SYSTEM = File.expand_path('..', __dir__)

def installed_class(file, header, scope = Object)
  path = File.join(NATIVE, file)
  lines = File.readlines(path, encoding: 'UTF-8')
  found = nil
  visit = lambda do |node|
    return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == :CLASS && lines[node.first_lineno - 1].strip == header
      found = node
    else
      node.children.each { |child| visit.call(child) }
    end
  end
  visit.call(RubyVM::AbstractSyntaxTree.parse(lines.join))
  raise "Class not found: #{header}" unless found
  scope.module_eval(lines[(found.first_lineno - 1)..(found.last_lineno - 1)].join, path, found.first_lineno)
end

module TestData
  ITEMS = {}
  names = Marshal.load(File.binread(File.join(ROOT, '../Data/Text/Dialogs/100012.fr.dat')))
  Dir[File.join(ROOT, '../Data/Studio/items/*.json')].each do |path|
    data = JSON.parse(File.read(path))
    item = OpenStruct.new(db_symbol: data['dbSymbol'].to_sym, socket: data['socket'],
                          id: data['id'], name: names[data['id']], position: data['position'])
    ITEMS[item.db_symbol] = ITEMS[item.id] = item
  end
  QUESTS = {}
  Dir[File.join(ROOT, '../Data/Studio/quests/*.json')].each do |path|
    data = JSON.parse(File.read(path))
    objectives = data['objectives'].map do |o|
      OpenStruct.new(objective_method_name: o['objectiveMethodName'].to_sym,
                     objective_method_args: o['objectiveMethodArgs'], hidden_by_default: o['hiddenByDefault'])
    end
    QUESTS[data['id']] = OpenStruct.new(id: data['id'], db_symbol: data['dbSymbol'].to_sym,
                                       name: data['dbSymbol'], is_primary: data['isPrimary'], objectives: objectives)
  end
end

module Kernel
  def data_item(id); TestData::ITEMS.fetch(id) { OpenStruct.new(db_symbol: :__undef__) }; end
  def data_quest(id); TestData::QUESTS.fetch(id) { OpenStruct.new(db_symbol: :__undef__) }; end
  def log_error(message); ($test_log ||= []) << message; end
  def data_creature(id); TestData::CREATURES.fetch(id) { OpenStruct.new(db_symbol: "species_#{id}".to_sym, forms: []) }; end
  def each_data_creature; TestData::CREATURES.values.uniq; end
  def each_data_zone; TestData::ZONES.values; end
  def data_group(id); TestData::GROUPS[id]; end
  def each_data_dex; [OpenStruct.new(db_symbol: :national)]; end
  def data_dex(*); OpenStruct.new(creatures: []); end
  def text_get(*); 'Menu'; end
  def ext_text(*); 'Retour'; end
end

module PFM
  class << self
    attr_accessor :game_state, :bag_class, :dex_class
  end
  module Text
    TRNAME = ['[TRAINER]']
    def self.define_const(*); end
  end
end
module Yuki
  module Sw
    Pokedex = 100
    Pokedex_Nat = 101
    TJN_MorningTime = 200
    TJN_DayTime = 201
    TJN_SunsetTime = 202
    TJN_NightTime = 203
  end
  module Var
    Pokedex_Catch = 3
    Pokedex_Seen = 2
  end
end
module Configs
  def self.settings; @settings ||= OpenStruct.new(max_bag_item_count: 999); end
end

load File.join(NATIVE, '4_Systems_000_General_3_GameState.rb')
%w[4_Systems_103_Bag.rb 4_Systems_101_Dex.rb 4_Systems_800_Quest.rb].each do |file|
  path = File.join(NATIVE, file)
  source = File.read(path, encoding: 'UTF-8')
  eval(source[0...source.index('module UI')], TOPLEVEL_BINDING, path)
end
PFM.bag_class = PFM::Bag
PFM.dex_class = PFM::Pokedex
class PFM::GameState
  attr_accessor :trainer
end

# Strict disposable primitives; real SpriteStack, Menu and Base lifecycle below.
class Drawable
  attr_accessor :x, :y, :z, :visible, :color, :width, :height, :opacity, :angle, :zoom, :zoom_x, :zoom_y
  attr_reader :viewport
  @@objects = []
  def self.objects; @@objects; end
  def initialize(viewport = nil, *)
    @viewport, @visible, @opacity, @x, @y, @z = viewport, true, 255, 0, 0, 0
    @@objects << self
  end
  def set_position(x, y); @x, @y = x, y; self; end
  def set_origin(*); self; end
  def move(x, y); @x += x; @y += y; self; end
  def dispose
    raise 'Double disposal' if @disposed
    @disposed = true
  end
  def disposed?; !!@disposed; end
end
class Sprite < Drawable
  attr_accessor :bitmap
  def set_bitmap(*); @width = @height = 32; self; end
end
class ShaderedSprite < Sprite; end
class SpriteSheet < Sprite
  def select(*); end
end
class Color
  def initialize(*); end
end
class Shape < Drawable
  attr_accessor :outline_color, :outline_thickness
  def initialize(viewport, type, width, height)
    super(viewport)
    @width, @height = width, height
  end
end
class Text < Drawable
  module Util
    DEFAULT_OUTLINE_SIZE = nil
    FOY = 2
  end
  attr_accessor :text, :fill_color, :draw_shadow
  def initialize(font, viewport, x, y, width, height, value, *)
    super(viewport)
    @x, @y, @width, @height, @text = x, y, width, height, value
  end
  def text_width(value); value.length * 6; end
end
class Viewport < Drawable
  def self.create(*); new; end
  def sort_z; end
end
class Clock; end
module Graphics
  module FPSBalancer
    module Marker; end
  end
end
module Input
  class << self
    attr_accessor :key
    def trigger?(key); @key == key; end
    alias repeat? trigger?
  end
end
module Audio
  def self.se_play(*); end
end
module Scheduler
  @callbacks = {}
  def self.add_proc(event, klass, name, priority, &block); @callbacks[[event, klass]] = block; end
  def self.start(event, klass); @callbacks[[event, klass]]&.call; end
end
class Scene_Map
  attr_accessor :spriteset, :dialogue
  def self.from(scene); scene; end
  def initialize
    @spriteset = OpenStruct.new(disposed?: false)
    def @spriteset.inform_quest(*); end
    Scheduler.start(:on_init, self.class)
  end
  def window_message_close(*); end
  def message_processing?; !!@dialogue; end
  def update_graphics; end
  def dispose; end
  def call_scene(*); end
end
module UI; end
installed_class('4_Systems_000_General_4_UI_Generics.rb', 'class SpriteStack', UI)
load File.join(NATIVE, '4_Systems_000_General_2_GamePlay__Base.rb')
class GamePlay::Base
  def message_initialize(*); end
  def message_soft_lock_prevent; end
  def message_dispose; end
  def play_cursor_se; end
  def play_cancel_se; end
  def play_decision_se; end
  def play_buzzer_se; end
  def call_scene(klass, *); @called_scene = klass; end
end
module GamePlay
  class << self
    attr_accessor :menu_class, :menu_mixin
    def open_quest_ui; @quest_opened = true; end
    attr_reader :quest_opened
  end
end
load File.join(NATIVE, '4_Systems_100_Menu.rb')
module ElementZ
  module QuestJournal
    def self.label(*); 'Journal'; end
  end
end
load File.join(ROOT, '00004 Quest/00020 JournalMenu.rb')
load File.join(ROOT, '00005 Trainer_Card/00002 CarteDresseurInterupteur.rb')
require_relative 'source_support'
Dir[File.join(SYSTEM, '*.rb')].sort.each { |file| load file }

class AchievementTest < Minitest::Test
  BA = BombanceAchievements
  ID = :researcher_collection
  def setup
    $scene = nil
    $test_log = []
    @game = PFM::GameState.allocate
    @game.trainer = OpenStruct.new(current_version: 6716, playing_girl: false, name: 'Test')
    $trainer = @game.trainer
    @game.game_switches = Hash.new(false)
    @game.game_variables = Hash.new(0)
    @game.game_party = OpenStruct.new(gold: 0)
    @game.game_temp = OpenStruct.new(in_battle: false, player_transferring: false, transition_processing: false,
                                   message_window_showing: false, last_menu_index: 0)
    @game.bag = PFM::Bag.new(@game)
    @game.pokedex = PFM::Pokedex.new(@game)
    @game.quests = PFM::Quests.new
    @game.actors = []
    @game.storage = PFM::Storage.allocate
    @game.storage.boxes = [OpenStruct.new(content: [])]
    @game.storage.current_box = 0
    @game.storage.game_state = @game
    @game.pokedex.national = true
    activate(@game)
    $actors = [Object.new]
    $game_system = OpenStruct.new(save_disabled: false)
    Configs.settings.max_bag_item_count = 999
    Input.key = nil
    @owned_start = Drawable.objects.size
  end

  def activate(game)
    # Actual load activation hooks; unrelated world/audio hooks are not run here.
    PFM.game_state = game
    %i[game_switches game_variables game_party game_temp bag pokedex quests bombance_achievements].each do |key|
      game.instance_exec(&PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(key))
    end
  end

  def capture(count)
    count.times { |i| @game.pokedex.mark_captured("species_#{i}".to_sym) }
  end

  def received
    BA::DEFINITIONS[ID][:tiers].select { |tier| BA.rewarded?(ID, tier) }.map { |tier| tier[:value] }
  end

  def press(scene, key)
    Input.key = key
    scene.update_inputs
    Input.key = nil
  end

  def open_ui
    scene = GamePlay::BombanceAchievementsScene.new
    scene.send(:create_graphics)
    scene
  end

  def with_constant(name, value)
    original = BA.const_get(name)
    BA.send(:remove_const, name)
    BA.const_set(name, value)
    yield
  ensure
    BA.send(:remove_const, name)
    BA.const_set(name, original)
  end

  def teardown
    BA::Notifications.reset
  end
end
