# Run with the Pokemon Studio Ruby 3.0.6 executable from the project root:
#   ruby.exe "scripts/00028 Quest Dex Sync/tests/run.rb"
# The harness imports the real PSDK methods under test and supplies only their
# engine/database collaborators, so it does not open the game or touch saves.
PROJECT_ROOT = File.expand_path('../../..', __dir__)
PSDK_SCRIPTS = File.join(PROJECT_ROOT, 'scripts', 'psdk_scripts')
PATCH_DIR = File.expand_path('..', __dir__)

def native_method_source(path, method_name, after_line: 1)
  source = File.read(path, encoding: 'UTF-8')
  visit = lambda do |node|
    next unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == :DEFN && node.children.first == method_name && node.first_lineno >= after_line
      next node
    end
    node.children.each do |child|
      found = visit.call(child)
      return found if found
    end
    nil
  end
  node = visit.call(RubyVM::AbstractSyntaxTree.parse(source))
  raise "Missing native method #{method_name} in #{path}" unless node

  source.lines[(node.first_lineno - 1)..(node.last_lineno - 1)].join
end

def import_native_methods(target, path, methods)
  methods.each do |method_name, after_line|
    target.class_eval(native_method_source(path, method_name, after_line: after_line || 1), path)
  end
end

module Battle
  module Logic
    class BattleEndHandler
      attr_reader :logic

      def initialize(logic)
        @logic = logic
      end
    end
  end
end

battle_source = File.join(PSDK_SCRIPTS, '5_Battle_04_Logic.rb')
import_native_methods(Battle::Logic::BattleEndHandler, battle_source, { handle_quest_update: nil })

module PFM
  class Quests
    AUTO_CHECK_SIGNAL_ON_ALL_OBJECTIVE_VALIDATED = false
    attr_accessor :active_quests, :finished_quests, :failed_quests, :signal
    attr_accessor :database

    def data_quest(quest_id)
      database.fetch(quest_id)
    end

    def finished?(quest_id)
      !@finished_quests.fetch(quest_id, nil).nil?
    end

    def failed?(quest_id)
      !@failed_quests.fetch(quest_id, nil).nil?
    end

    def check_up_signal
      nil
    end

    class Quest
      class << self
        attr_accessor :database
      end

      attr_reader :quest_id

      def data_quest(quest_id)
        self.class.database.fetch(quest_id)
      end

      def objective_catch_pokemon(species_symbol, amount = 1)
        data_get(:pokemon_caught, species_symbol, 0) >= amount
      end

      def objective_beat_pokemon(species_symbol, amount = 1)
        data_get(:pokemon_beaten, species_symbol, 0) >= amount
      end

      def objective_custom_flag(flag)
        data_get(:custom_flags, flag, false)
      end
    end
  end
end

quest_source = File.join(PSDK_SCRIPTS, '4_Systems_800_Quest.rb')
import_native_methods(PFM::Quests, quest_source,
                      { initialize: nil,
                        start: nil,
                        active_quest: nil,
                        show_goal: nil,
                        check_quest: nil,
                        see_pokemon: nil,
                        beat_pokemon: nil })
import_native_methods(PFM::Quests::Quest, quest_source,
                      { initialize: 381,
                        data_get: 381,
                        data_set: 381,
                        objective?: 381,
                        objective_see_pokemon: 381,
                        finished?: 381 })

load File.join(PATCH_DIR, '00001 Capture See Objective.rb')
load File.join(PATCH_DIR, '00002 Retroactive Seen Objective Sync.rb')

module QuestDexSyncTestInstrumentation
  def seen_notification_calls
    @seen_notification_calls || []
  end

  def check_quest_calls
    @check_quest_calls || []
  end

  def see_pokemon(species_symbol)
    (@seen_notification_calls ||= []) << species_symbol
    super
  end

  def check_quest(quest_id)
    (@check_quest_calls ||= []) << quest_id
    super
  end
end
PFM::Quests.prepend(QuestDexSyncTestInstrumentation)

QuestObjective = Struct.new(:objective_method_name, :objective_method_args, :hidden_by_default)
QuestDefinition = Struct.new(:db_symbol, :objectives)

class FakePokedex
  attr_accessor :seen_species
  attr_reader :queries

  def initialize(seen_species = [])
    @seen_species = seen_species
    @queries = []
  end

  def creature_seen?(*args)
    @queries << args
    seen_species.include?(args.first)
  end
end

class FakeBattler
  attr_reader :db_symbol, :last_sent_turn

  def initialize(db_symbol, from_party:, last_sent_turn: 0, alive: true)
    @db_symbol = db_symbol
    @from_party = from_party
    @last_sent_turn = last_sent_turn
    @alive = alive
  end

  def from_party?
    @from_party
  end

  def alive?
    @alive
  end
end

FakeBattleInfo = Struct.new(:caught_pokemon)

class FakeBattleLogic
  attr_reader :battle_info
  attr_accessor :battle_result

  def initialize(battlers, caught_pokemon = nil, battle_result: 0)
    @battlers = battlers
    @battle_info = FakeBattleInfo.new(caught_pokemon)
    @battle_result = battle_result
  end

  def all_battlers(&block)
    return @battlers.each(&block) if block

    @battlers.each
  end
end

class QuestDexSyncTest
  def setup
    @database = {}
    PFM::Quests::Quest.database = @database
    @quests = PFM::Quests.new
    @quests.database = @database
    $quests = @quests
    $pokedex = FakePokedex.new
  end

  def assert_equal(expected, actual, message = nil)
    $assertion_count += 1
    return if expected == actual

    raise(message || "Expected #{expected.inspect}, got #{actual.inspect}")
  end

  def assert_empty(actual, message = nil)
    assert_equal([], actual, message)
  end

  def objective(method_name, *args, hidden: false)
    QuestObjective.new(method_name, args, hidden)
  end

  def add_quest(quest_id, *objectives)
    @database[quest_id] = QuestDefinition.new("quest_#{quest_id}".to_sym, objectives)
  end

  def activate(quest_id, seen_species: [])
    $pokedex = FakePokedex.new(seen_species)
    @quests.start(quest_id)
    @quests.active_quest(quest_id)
  end

  def run_battle_end(battlers, caught_pokemon = nil, battle_result: 0)
    logic = FakeBattleLogic.new(battlers, caught_pokemon, battle_result: battle_result)
    Battle::Logic::BattleEndHandler.new(logic).handle_quest_update([])
  end

  def test_party_capture_notifies_see_once_and_keeps_other_battler_updates
    add_quest(1,
              objective(:objective_see_pokemon, :pikachu),
              objective(:objective_beat_pokemon, :rattata, 1))
    quest = activate(1)
    caught = FakeBattler.new(:pikachu, from_party: true)
    defeated = FakeBattler.new(:rattata, from_party: false, alive: false)

    run_battle_end([caught, defeated], caught)

    assert_equal [:rattata, :pikachu], @quests.seen_notification_calls
    assert_equal true, quest.objective_see_pokemon(:pikachu)
    assert_equal 1, quest.data_get(:pokemon_beaten, :rattata, 0)
    assert_equal [1, 1], @quests.check_quest_calls
  end

  def test_storage_capture_uses_native_notification_without_a_duplicate
    add_quest(2, objective(:objective_see_pokemon, :pikachu))
    quest = activate(2)
    caught = FakeBattler.new(:pikachu, from_party: false)

    run_battle_end([caught], caught)

    assert_equal [:pikachu], @quests.seen_notification_calls
    assert_equal true, quest.objective_see_pokemon(:pikachu)
    assert_equal [2], @quests.signal[:finish]
  end

  def test_captured_pokemon_is_not_lost_when_native_loop_would_skip_its_turn
    add_quest(3, objective(:objective_see_pokemon, :pikachu))
    quest = activate(3)
    caught = FakeBattler.new(:pikachu, from_party: false, last_sent_turn: -1)

    run_battle_end([caught], caught)

    assert_equal [:pikachu], @quests.seen_notification_calls
    assert_equal true, quest.objective_see_pokemon(:pikachu)
  end

  def test_retroactive_activation_updates_only_seen_species_objectives
    add_quest(4,
              objective(:objective_see_pokemon, :rattata, 5),
              objective(:objective_see_pokemon, :pikachu),
              objective(:objective_catch_pokemon, :eevee, 2),
              objective(:objective_beat_pokemon, :pidgey, 3),
              objective(:objective_custom_flag, :custom_goal))

    quest = activate(4, seen_species: %i[rattata pidgey])

    assert_equal true, quest.objective_see_pokemon(:rattata)
    assert_equal false, quest.objective_see_pokemon(:pikachu)
    assert_equal 0, quest.data_get(:pokemon_caught, :eevee, 0)
    assert_equal 0, quest.data_get(:pokemon_beaten, :pidgey, 0)
    assert_equal false, quest.objective_custom_flag(:custom_goal)
    assert_equal [], @quests.signal[:finish]
    assert_equal [[:rattata], [:pikachu]], $pokedex.queries
    assert_equal [4], @quests.check_quest_calls
  end

  def test_unseen_species_stays_unvalidated_until_the_normal_encounter_notification
    add_quest(5, objective(:objective_see_pokemon, :pikachu))
    quest = activate(5)

    assert_equal false, quest.objective_see_pokemon(:pikachu)
    assert_empty @quests.check_quest_calls

    @quests.see_pokemon(:pikachu)

    assert_equal true, quest.objective_see_pokemon(:pikachu)
    assert_equal [5], @quests.signal[:finish]
  end

  def test_visible_existing_progress_is_preserved_and_hidden_goals_sync_when_shown
    add_quest(6,
              objective(:objective_see_pokemon, :rattata),
              objective(:objective_see_pokemon, :pikachu),
              objective(:objective_see_pokemon, :eevee, hidden: true),
              objective(:objective_catch_pokemon, :eevee, 4),
              objective(:objective_beat_pokemon, :pidgey, 3))
    quest = activate(6)
    quest.data_set(:pokemon_seen, :rattata, true)
    quest.data_set(:pokemon_seen, :pikachu, false)
    quest.data_set(:pokemon_caught, :eevee, 2)
    quest.data_set(:pokemon_beaten, :pidgey, 1)
    $pokedex.seen_species = %i[pikachu eevee]

    @quests.show_goal(6, 0)

    assert_equal true, quest.objective_see_pokemon(:rattata)
    assert_equal true, quest.objective_see_pokemon(:pikachu)
    assert_equal false, quest.objective_see_pokemon(:eevee)
    assert_equal 2, quest.data_get(:pokemon_caught, :eevee, 0)
    assert_equal 1, quest.data_get(:pokemon_beaten, :pidgey, 0)

    @quests.show_goal(6, 2)

    assert_equal true, quest.objective_see_pokemon(:eevee)
    assert_equal 2, quest.data_get(:pokemon_caught, :eevee, 0)
    assert_equal 1, quest.data_get(:pokemon_beaten, :pidgey, 0)
    assert_equal [6, 6], @quests.check_quest_calls
  end

  def test_repeated_validation_keeps_one_finish_signal_and_serializable_progress
    add_quest(7, objective(:objective_see_pokemon, :rattata))
    quest = activate(7, seen_species: [:rattata])

    @quests.show_goal(7, 0)
    @quests.show_goal(7, 0)
    restored_quests = Marshal.load(Marshal.dump(@quests))
    restored_quests.database = @database
    restored = restored_quests.active_quest(7)

    assert_equal [7], @quests.signal[:finish]
    assert_equal true, restored.objective_see_pokemon(:rattata)
    assert_equal [7], restored_quests.signal[:finish]
    assert_equal [:@data, :@quest_id], restored.instance_variables.sort_by(&:to_s)
  end
end

$assertion_count = 0
test_methods = QuestDexSyncTest.instance_methods(false).grep(/^test_/).sort
failures = []
test_methods.each do |method_name|
  test = QuestDexSyncTest.new
  begin
    test.setup
    test.public_send(method_name)
    puts "PASS #{method_name}"
  rescue StandardError => error
    failures << [method_name, error]
    warn "FAIL #{method_name}: #{error.class}: #{error.message}"
    warn error.backtrace.join("\n")
  end
end

abort("#{failures.length}/#{test_methods.length} tests failed") unless failures.empty?
puts "PASS #{test_methods.length} tests, #{$assertion_count} assertions"
