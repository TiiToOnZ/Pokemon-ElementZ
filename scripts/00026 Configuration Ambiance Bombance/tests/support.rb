# frozen_string_literal: true
# Headless integration with real SDK method bodies and actual project map data.
# No game boot, saves, events, config compilation or project data writes.
require 'json'
require 'ostruct'

ROOT = File.expand_path('../../..', __dir__)
SDK = File.join(ROOT, 'scripts/psdk_scripts')
EXT = File.expand_path('..', __dir__)
ENGINE = File.join(SDK, '4_Systems_003_Map_Engine.rb')

def import_node(target, path, header, kind = :DEFN, within: nil)
  source = File.read(path, encoding: 'UTF-8')
  lines = source.lines
  found = nil
  visit = lambda do |node|
    next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == kind && lines[node.first_lineno - 1].strip == header
      found ||= node
    else
      node.children.each { |child| visit.call(child) }
    end
  end
  root = RubyVM::AbstractSyntaxTree.parse(source)
  if within
    scope = nil
    search = lambda do |node|
      next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
      if lines[node.first_lineno - 1].strip == within && node.type == :CLASS
        scope ||= node
      else
        node.children.each { |child| search.call(child) }
      end
    end
    search.call(root)
    root = scope || raise("Missing scope #{within}")
  end
  visit.call(root)
  raise "Missing #{header}" unless found
  target.module_eval(lines[(found.first_lineno - 1)..(found.last_lineno - 1)].join, path, found.first_lineno)
end

class Record
  def method_missing(name, *args)
    key = name.to_s
    return instance_variable_set("@#{key.chop}", args.first) if key.end_with?('=')
    return instance_variable_get("@#{key}") if instance_variable_defined?("@#{key}")
    super
  end
  def respond_to_missing?(name, *)
    instance_variable_defined?("@#{name}") || super
  end
end
module RPG; end
class Table
  def self._load(data)
    _dimensions, width, height, depth, count = data.unpack('L<5')
    new(width, height, depth, data.byteslice(20, count * 2).unpack('S<*'))
  end
  def initialize(width = 1, height = 1, depth = 1, values = [])
    @width, @height, @depth, @values = width, height, depth, values
  end
  def [](x, y = 0, z = 0); @values[x + @width * (y + @height * z)] || 0; end
  def []=(*args)
    value = args.pop
    x, y, z = args
    @values[x + @width * ((y || 0) + @height * (z || 0))] = value
  end
end
class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r, g, b, a); @red, @green, @blue, @gray = r, g, b, a; end
  def self._load(data); new(*data.unpack('d4')); end
  def set(r, g, b, a); @red, @green, @blue, @gray = r, g, b, a; end
end
class Color < Tone
  alias alpha gray
  alias alpha= gray=
end
def read_data(path)
  Marshal.load(File.binread(File.join(ROOT, path)))
rescue ArgumentError => e
  raise unless e.message =~ /undefined class\/module ([\w:]+)/
  scope = Object
  Regexp.last_match(1).sub(/::$/, '').split('::').each do |name|
    scope = scope.const_defined?(name, false) ? scope.const_get(name, false) : scope.const_set(name, Class.new(Record))
  end
  retry
end

module Yuki
  module Var
    TJN_Hour = 10
    TJN_Min = 11
  end
  module TJN
    DEFAULT_TIME_SET = [22, 19, 11, 7].freeze
    class << self
      attr_writer :time_set
      def current_time_set; @time_set || DEFAULT_TIME_SET; end
    end
  end
  module Sw
    MapLinkerDisabled = 1
    Env_CanFly = 2
    TJN_Enabled = 3
    TJN_MorningTime = 4
    TJN_DayTime = 5
    TJN_SunsetTime = 6
    TJN_NightTime = 7
    WRP_Transition = 8
  end
  module ElapsedTime
    def self.start(*); end
    def self.show(*); end
  end
  module MapLinker
    DELTA_MAKER = 0
    class << self
      attr_reader :map_datas
      def load_map(id)
        @map_datas = [MapData.new(read_data(format('Data/Map%03d.rxdata', id)), id)]
        @map_datas.first.load_position(@map_datas.first.map, :self, 0)
        unless $game_switches[Sw::MapLinkerDisabled]
          link = LINKS.find { |value| value.map_id == id }
          load_map_data_from_link_data(link, @map_datas, @map_datas.first.map) if link
        end
        @map_datas.first.map
      end
      def load_map_data(id); read_data(format('Data/Map%03d.rxdata', id)); end
      def tileset_name; 'fixture'; end
    end
    @map_datas = []
  end
  class MapData
    POSITION_LOADERS = { north: :load_position_north, south: :load_position_south,
                         east: :load_position_east, west: :load_position_west, self: :load_position_self }
    attr_reader :map, :map_id, :offset_x, :offset_y, :x_range, :y_range
    def initialize(map, id); @map, @map_id = map, id; end
  end
end
%w[load_position(map,\ side,\ offset) load_position_north(map,\ offset,\ maker_offset)
   load_position_south(map,\ offset,\ maker_offset) load_position_east(map,\ offset,\ maker_offset)
   load_position_west(map,\ offset,\ maker_offset) load_position_self(map,\ offset,\ maker_offset)].each do |signature|
  import_node(Yuki::MapData, ENGINE, "def #{signature}")
end
# The native linker refers to Tilemap::MapData lexically.
module Yuki::Tilemap; MapData = Yuki::MapData; end
%w[load_map_data_from_link_data(link_data,\ map_datas,\ current_map)
   load_map_data_from_link(link,\ cardinal,\ current_map)].each do |signature|
  import_node(Yuki::MapLinker.singleton_class, ENGINE, "def #{signature}")
end
# module_eval does not restore lexical constant lookup; the original methods use
# Tilemap unqualified. This alias is confined to the fixture process.
Tilemap = Yuki::Tilemap
MapLinker = Yuki::MapLinker
LINKS = Dir[File.join(ROOT, 'Data/Studio/maplinks/*.json')].map do |path|
  raw = JSON.parse(File.read(path))
  OpenStruct.new(map_id: raw['mapId'], **%w[north east south west].to_h do |side|
    ["#{side}_maps".to_sym, raw["#{side}Maps"].map { |v| OpenStruct.new(map_id: v['mapId'], offset: v['offset']) }]
  end)
end

module Pathfinding
  def self.clear; end
  def self.update; end
end
module Graphics
  def self.width; 320; end
  def self.height; 240; end
  def self.frame_reset; end
  def self.sort_z; end
end
module Scheduler
  def self.start(*); end
end
class Game_Event
  def initialize(*); end
  def sym_alias; nil; end
  def update; end
end
class Game_CommonEvent < Game_Event; end
class Game_Map
  PATH_FINDING_ENABLED = false
  NUM_TILE_VIEW_X = 20
  NUM_TILE_VIEW_Y = 15
  attr_accessor :display_x, :display_y, :fog_name, :fog_sx, :fog_sy, :fog_zoom, :fog_opacity,
                :fog_blend_type, :need_refresh
  attr_reader :map_id, :fog_ox, :fog_oy, :fog_hue, :fog_tone, :maplinker_disabled
  def width; @map.width; end
  def height; @map.height; end
  def save_events_offset; end
  def load_systemtags; end
  def load_events; end
  def load_following_events; end
  def refresh; @need_refresh = false; end
end
%w[setup(map_id) update].each { |s| import_node(Game_Map, ENGINE, "def #{s}", within: 'class Game_Map') }
# Several native classes have initialize: scope its extraction to the Game_Map.
Game_Map.class_eval('def initialize; @map_id = 0; @display_x = @display_y = 0; end')
PATH_FINDING_ENABLED = false
class Game_Player
  CENTER_X = 1216
  CENTER_Y = 896
  attr_accessor :x, :y, :direction
  def direction_fix; false; end
  def straighten; end
  def moveto(x, y); @x, @y = x, y; center(x, y); end
end
import_node(Game_Player, ENGINE, 'def center(x, y)')
CENTER_X = Game_Player::CENTER_X
CENTER_Y = Game_Player::CENTER_Y

class FakeTexture
  attr_reader :width, :height
  attr_accessor :sample
  def initialize(width = 512, height = 512); @width, @height = width, height; end
  def to_png; self; end
  def dispose; @disposed = true; end
  def disposed?; !!@disposed; end
end
Texture = FakeTexture
class Image
  attr_reader :width, :height, :reads
  def initialize(texture, *)
    @texture, @width, @height, @reads = texture, texture.width, texture.height, []
  end
  def get_pixel(x, y)
    @reads << [x, y]
    @texture.sample ? @texture.sample.call(x, y) : Color.new(255, 255, 255, 0)
  end
  def set_pixel(*); end
  def copy_to_bitmap(*); end
  def dispose; raise 'Double image dispose' if @disposed; @disposed = true; end
  def disposed?; !!@disposed; end
end
module RPG::Cache
  def self.fog(*); FakeTexture.new; end
  def self.animation(name)
    (@animations ||= {})[name] ||= name.end_with?('/firefly') ? FakeTexture.new(7, 7) : FakeTexture.new
  end
end
class Plane
  attr_accessor :zoom, :opacity, :blend_type, :tone, :z, :texture, :color, :visible
  alias bitmap texture
  alias bitmap= texture=
  attr_reader :ox, :oy
  def initialize(*)
    @ox = @oy = 0
    @visible = true
    @color = Color.new(255, 255, 255, 0)
  end
  def zoom_x; @zoom; end
  def zoom_y; @zoom; end
  def set_origin(x, y); @ox, @oy = x, y; end
  def dispose; raise 'Double dispose' if @disposed; @disposed = true; end
  def disposed?; !!@disposed; end
end
class Sprite < Plane
  attr_accessor :zoom_x, :zoom_y, :x, :y, :angle, :visible
  def set_position(x, y); @x, @y = x, y; end
  def shader; @shader ||= OpenStruct.new(blend_type: 0); end
  class WithColor < self; end
end
class FixtureViewport
  def sort_z; end
end
class Spriteset_Map
  attr_reader :fog
  def initialize
    @viewport1 = FixtureViewport.new
    init_sprites
    update_sprites
  end
  def init_sprites; end
  def update_sprites; end
  def dispose_sprites; end
  def reload(*); update_sprites; end
  def dispose(from_warp = false); dispose_sprites unless from_warp; nil; end
end
import_node(Spriteset_Map, ENGINE, 'module FogPlugin', :MODULE)
Spriteset_Map.prepend(Spriteset_Map::FogPlugin)
load File.join(ROOT, 'scripts/00000 Plugins/00004 FogFix/00001 FogPlugin.rb')
NATIVE_FOG = Spriteset_Map::FogPlugin.instance_method(:update_fog_sprite_parameters)
class Scene_Map
  attr_reader :spriteset
  def initialize; @spriteset = Spriteset_Map.new; end
  def transfer_player_specific_transition; end
  def transfer_player_end(*); end
end
%w[transfer_player_begin transfer_player].each { |s| import_node(Scene_Map, ENGINE, "def #{s}") }
module PFM
  class GameState
    ON_EXPAND_GLOBAL_VARIABLES = {}
    def self.on_expand_global_variables(name, &block); ON_EXPAND_GLOBAL_VARIABLES[name] = block; end
  end
end

Dir[File.join(EXT, '[0-9]*.rb')].sort.each { |path| load path }

def reset_fixture(id = 27, effects: nil)
  $game_variables = Hash.new(0)
  $game_variables[Yuki::Var::TJN_Hour] = 15
  Yuki::TJN.time_set = nil
  $game_switches = Hash.new(false)
  $game_switches[Yuki::Sw::TJN_Enabled] = true
  $game_switches[Yuki::Sw::TJN_DayTime] = true
  $data_tilesets = read_data('Data/Tilesets_tiled.rxdata')
  $data_common_events = [nil]
  $game_temp = OpenStruct.new(transition_processing: false, player_new_direction: 0)
  $env = OpenStruct.new(current_zone: 20, current_weather_db_symbol: :none, update_zone: false,
                       get_current_zone_data: OpenStruct.new(is_warp_disallowed: false), get_event_delete_state: false)
  def $env.get_event_delete_state(*); false; end
  $game_map = Game_Map.new
  $game_player = Game_Player.new
  PFM::GameState::ON_EXPAND_GLOBAL_VARIABLES.fetch(:bombance_ambiance_session).call
  $game_map.setup(id)
  $game_player.moveto(20, 20)
  # Keep old suites isolated from V4, unless requested explicitly.
  BombanceAmbiance.override_effects(id, **{ fireflies: false }.merge(effects || {}))
  $scene = Scene_Map.new
end

def transfer(id, x, y)
  $game_temp.player_new_map_id = id
  $game_temp.player_new_x = x
  $game_temp.player_new_y = y
  $scene.transfer_player
end
