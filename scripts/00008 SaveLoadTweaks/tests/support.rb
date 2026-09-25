# Headless harness: load the project's actual native Save/Load implementation.
# No game boot, graphics, real save access or third-party gems are required.
require 'tmpdir'
require 'fileutils'

module Configs
  class << self
    attr_accessor :save_config
    def register(*)
      self.save_config = SaveConfig.new
    end
    def infos
      Struct.new(:game_title, :game_version).new('IsolatedSaveTest', 1)
    end
  end
end
module Studio
  module Text
    def self.load; end
  end
end
module UI
  class SpriteStack; end
end
module Graphics
  def self.sort_z; end
  def self.update; end
end
module PFM
  class << self
    attr_accessor :game_state
  end
  class GameState
    attr_accessor :name, :user_data
    def initialize(name = 'Current player')
      @name = name
      @user_data = { capture_chain: [1, 2], crafting: { recipe: 3 } }
    end
    def load_parameters; end
  end
end
module Kernel
  def ext_text(bank, index)
    "external:#{bank}:#{index}"
  end
  def text_get(bank, index)
    "native:#{bank}:#{index}"
  end
  def log_error(message)
    $test_log << message
  end
end
module GamePlay
  class BaseCleanUpdate
    class FrameBalanced; end
    attr_reader :events
    attr_accessor :answers
    def initialize
      @events = []
      @answers = []
    end
    def display_message(text, start = 1, *choices)
      @events << [:message, text, start, choices]
      choices.empty? ? nil : (@answers.shift || 1)
    end
    def display_message_and_wait(text)
      @events << [:failure, text]
    end
    %i[decision buzzer save cursor].each do |sound|
      define_method("play_#{sound}_se") { @events << [:sound, sound] }
    end
  end
end
class << Dir
  def mkdir!(path)
    FileUtils.mkdir_p(path)
  end
end
PSDK_VERSION = 26_60
require File.expand_path('../../psdk_scripts/4_Systems_106_Save_Load', __dir__)
require File.expand_path('../00000 SaveLoadTweaks', __dir__)

# Observe the native action's delegation without starting a map or new game.
module SceneObserver
  def create_new_game
    @events << [:new_game]
  end
  private
  def load_game
    @events << [:load_game, @all_saves[@index].name]
  end
  def load_sign_data
    super
    @events << [:refresh]
  end
end
GamePlay::Load.prepend(SceneObserver)

class TestTrainer
  attr_accessor :current_version, :game_version
  def update_play_time; end
end
class TestHook
  def initialize(name)
    @name = name
  end
  def begin_save
    $test_hooks << [@name, :begin]
  end
  def end_save
    $test_hooks << [@name, :end]
  end
end

class SaveLoadTest
  class AssertionFailure < StandardError; end
  class << self
    attr_accessor :assertions
  end
  self.assertions = 0

  def assert(condition, message = 'Assertion failed')
    self.class.assertions += 1
    raise AssertionFailure, message unless condition
  end
  def equal(expected, actual)
    assert(expected == actual, "Expected #{expected.inspect}, got #{actual.inspect}")
  end
  def setup
    config = Configs.save_config
    config.maximum_save_count = 0
    config.save_header = 'PKPRT'
    config.save_key = 0
    config.base_filename = 'Pokemon_Party'
    config.can_save_on_any_save = true
    GamePlay::Save.save_index = 1
    PFM.game_state = PFM::GameState.new
    $pokemon_party = PFM.game_state
    $test_log = []
    $test_hooks = []
    $game_temp = Struct.new(:message_proc, :choice_proc, :battle_proc, :message_window_showing).new
    $game_system = Struct.new(:save_count).new(0)
    $trainer = TestTrainer.new
    $game_map = TestHook.new(:map)
    $wild_battle = TestHook.new(:encounters)
  end
  def filename(index = 1)
    index.zero? ? 'Pokemon_Party' : "Pokemon_Party-#{index}"
  end
  def bytes(name = 'Old player')
    Configs.save_config.save_header + Marshal.dump(PFM::GameState.new(name))
  end
  def fixture(index = 1, content = bytes)
    File.binwrite(filename(index), content)
    content
  end
  def scene(type = GamePlay::Save, index = 0)
    instance = type.new
    instance.instance_variable_set(:@index, index)
    instance.instance_variable_set(:@signs, Array.new(5) { Struct.new(:data, :save_index).new })
    $scene = instance
    instance
  end
  def messages(instance)
    instance.events.select { |event| event.first == :message }.map { |event| event[1] }
  end
  def activate(instance, answer = nil)
    instance.answers << answer unless answer.nil?
    instance.__send__(:action_a)
  end
  def with_fault(target, method, fault)
    original = target.method(method)
    target.define_singleton_method(method) { |*args| fault.call(original, *args) }
    yield
  ensure
    target.define_singleton_method(method, original)
  end
  def assert_failure(instance, previous_entries)
    equal(false, instance.saved)
    equal(true, instance.instance_variable_get(:@running))
    assert(!instance.events.include?([:sound, :save]), 'False success sound')
    assert(!messages(instance).include?(ext_text(311_110, 3)), 'False success message')
    assert(!instance.events.include?([:refresh]), 'False card refresh')
    equal(previous_entries, instance.instance_variable_get(:@all_saves))
    equal(1, instance.events.count { |event| event == [:failure, text_get(26, 19)] })
  end
  def assert_success(instance)
    equal(true, instance.saved)
    equal(false, instance.instance_variable_get(:@running))
    assert(instance.events.include?([:sound, :save]))
    assert(messages(instance).include?(ext_text(311_110, 3)))
    assert(instance.events.include?([:refresh]))
    index = instance.instance_variable_get(:@index)
    assert(instance.instance_variable_get(:@all_saves)[index].equal?(PFM.game_state))
    assert(!instance.events.any? { |event| event.first == :failure })
    refresh = instance.events.index([:refresh])
    sound = instance.events.index([:sound, :save])
    message = instance.events.index { |event| event[0..1] == [:message, ext_text(311_110, 3)] }
    assert(refresh < sound && sound < message)
  end
  def assert_hooks
    equal([[:map, :begin], [:encounters, :begin], [:map, :end], [:encounters, :end]], $test_hooks)
  end
  def assert_no_staging_files
    equal([], Dir.glob('.save-load-tweaks-*'))
  end
end
