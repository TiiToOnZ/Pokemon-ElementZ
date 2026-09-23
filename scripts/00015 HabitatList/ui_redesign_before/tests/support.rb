# Headless integration harness: use the local PSDK models, presenter, Dex scene,
# Studio database and source APIs. Only native graphics, audio, input and the
# Pokemon display object are substituted; this is not an in-game rendering test.
require 'ostruct'
require 'minitest/autorun'

SCRIPTS = File.expand_path('../..', __dir__)
PROJECT = File.dirname(SCRIPTS)
ENGINE = File.join(SCRIPTS, 'psdk_scripts')

def load_prefix(filename, delimiter)
  source = File.read(File.join(ENGINE, filename), encoding: 'UTF-8')
  eval(source.split(delimiter, 2).first, TOPLEVEL_BINDING, filename)
end

module Graphics
  def self.on_start; end
  def self.sort_z; end
end
module Configs
  def self.language
    OpenStruct.new(choosable_language_code: ['fr'])
  end
end
module Yuki
  module Sw
    Pokedex = 1
    Pokedex_Nat = 2
  end
  module Var
    Pokedex_Seen = 1
    Pokedex_Catch = 2
  end
end
module PFM
  class << self
    attr_accessor :game_state, :dex_class
  end
  class GameState
    def self.on_player_initialize(*); end
    def self.on_expand_global_variables(*); end
    def self.on_deserialize(*); end
  end
  class Pokemon
    FORM_GENERATION = {}
    attr_accessor :form, :gender
    attr_reader :id, :db_symbol
    def initialize(symbol, _level)
      self.id = symbol
      @form = 0
    end
    def id=(symbol)
      @db_symbol = data_creature(symbol).db_symbol
      @id = data_creature(symbol).id
    end
    def self.generate_from_hash(id:, form:, **_opts)
      new(id, 1).tap { |pokemon| pokemon.form = form }
    end
  end
end

load_prefix('3_Studio.rb', "module Configs\n")

# The real data accessors are used against a replaceable database in each test.
def __game_data
  $habitat_database
end
def text_get(file, id)
  ($habitat_text_reads ||= []) << [file, id]
  "text#{file}:#{id}"
end
def ext_text(file, id)
  "text#{file}:#{id}"
end
def log_error(message)
  ($habitat_errors ||= []) << message
end

class HeadlessDrawable
  attr_accessor :visible, :text, :multiline_text, :bitmap, :nb_x, :y, :x, :bold, :data
  def initialize(*)
    @visible = true
  end
  def set_position(x, y)
    @x, @y = x, y
    self
  end
  def set_bitmap(*); self; end
end
class Sprite < HeadlessDrawable; end
class SpriteSheet < HeadlessDrawable; end
class Viewport
  def self.create(*)
    new
  end
end
class Color
  def self._load(_data)
    new
  end
end
module UI
  class SpriteStack
    NO_INITIAL_IMAGE = nil
    def initialize(*); end
    def add_text(*args, **_kwargs)
      HeadlessDrawable.new.tap { |text| text.text = args[4] }
    end
    def add_sprite(*_args, **_kwargs)
      HeadlessDrawable.new
    end
  end
  class GenericBase
    DEFAULT_KEYS = %i[A X Y B]
    attr_reader :ctrl
    def initialize(*)
      @ctrl = []
    end
    def update_background_animation; end
  end
end
module GamePlay
  class << self
    attr_accessor :dex_class, :dex_info_class
  end
  class BaseCleanUpdate
    attr_reader :called_scene
    def initialize; end
    def play_decision_se; end
    def play_cancel_se; end
    def play_buzzer_se; end
    def call_scene(scene)
      @called_scene = scene.new
    end
    def automatic_input_update(mapping)
      mapping.each do |key, method|
        next unless Input.trigger?(key)
        send(method)
        return false
      end
      true
    end
    def update_mouse_ctrl_buttons(*)
      true
    end
    class FrameBalanced < self; end
  end
end
module Mouse
  class << self
    attr_accessor :wheel
  end
end
module Input
  class << self
    attr_accessor :key
    def trigger?(key)
      @key == key
    end
    alias repeat? trigger?
  end
end
module RPG
  module Cache
    class << self
      attr_accessor :fail_icon, :icon_reads
      def b_icon_exist?(_filename)
        !fail_icon
      end
      def b_icon(filename)
        self.icon_reads ||= []
        icon_reads << filename
        OpenStruct.new(width: 64, height: 32)
      end
    end
  end
end

load File.join(ENGINE, '4_Systems_101_Dex.rb')
load File.join(ENGINE, '4_Systems_999_Wild.rb')
# Use the actual icon filename resolver, rather than a copy of its semantics.
pokemon_source = File.read(File.join(ENGINE, '4_Systems_000_General_1_PFM.rb'), encoding: 'UTF-8')
icon_source = pokemon_source[/^      def icon_filename\(.*?^      end/m]
PFM::Pokemon.singleton_class.class_eval(icon_source)
pokemon_source.scan(/^    FORM_GENERATION\[:(\w+)\]/).flatten.each { |name| PFM::Pokemon::FORM_GENERATION[name.to_sym] = true }
PFM::Pokemon::FORM_GENERATION[:sawsbuck] = true

load File.join(SCRIPTS, '00015 HabitatList/54100 ZoneEncounterCatalog.rb')
load File.join(SCRIPTS, '00015 HabitatList/54200 ZoneEncounterPage.rb')
load File.join(SCRIPTS, '00015 HabitatList/54300 DexZoneExtension.rb')

LOCAL_DATABASE = Marshal.load(File.binread(File.join(PROJECT, 'Data/Studio/psdk.dat')))

def studio_object(klass, attributes)
  klass.allocate.tap do |object|
    attributes.each { |key, value| object.instance_variable_set("@#{key}", value) }
  end
end
