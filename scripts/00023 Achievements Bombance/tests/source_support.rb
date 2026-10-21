# frozen_string_literal: true
# Reconstructed locally: these fixtures were never tracked in the available Git history.
# Native classes/adapters are loaded verbatim; only external world data is adapted.
installed_class('4_Systems_000_General_1_PFM.rb', 'class Pokemon', PFM)
installed_class('4_Systems_200_Storage.rb', 'class Storage', PFM)
class PFM::GameState
  attr_accessor :storage
end
module PFM
  class PokemonBattler
    attr_accessor :original
    def copy_properties_back_to_original; :copied; end
  end
end
module Battle
  module Logic
    class BattleEndHandler
      def process; :processed; end
    end
  end
end
module GamePlay
  def self.make_egg_hatch(pokemon)
    pokemon.step_remaining = 0
    true
  end
end
module TestData
  CREATURES, ZONES, GROUPS = {}, {}, {}
  Dir[File.join(ROOT, '../Data/Studio/pokemon/*.json')].each do |path|
    data = JSON.parse(File.read(path))
    value = OpenStruct.new(db_symbol: data['dbSymbol'].to_sym, forms: data['forms'].map { |f| OpenStruct.new(form: f['form']) })
    CREATURES[value.db_symbol] = CREATURES[data['id']] = value
  end
  Dir[File.join(ROOT, '../Data/Studio/zones/*.json')].each do |path|
    data = JSON.parse(File.read(path))
    ZONES[data['dbSymbol'].to_sym] = OpenStruct.new(db_symbol: data['dbSymbol'].to_sym, name: data['dbSymbol'],
      maps: data['maps'], wild_groups: data['wildGroups'].map(&:to_sym))
  end
  class Condition < OpenStruct
    def reduce_evaluate(previous)
      enabled = type == :enabled_switch ? !!$game_switches[value] : true
      relation_with_previous_condition == :OR ? previous || enabled : previous && enabled
    end
  end
  Dir[File.join(ROOT, '../Data/Studio/groups/*.json')].each do |path|
    data = JSON.parse(File.read(path))
    snake = ->(s) { s&.gsub(/([a-z])([A-Z])/, '\\1_\\2')&.downcase&.to_sym }
    conditions = data['customConditions'].map do |c|
      Condition.new(type: snake.call(c['type']), value: c['value'],
        relation_with_previous_condition: c['relationWithPreviousCondition']&.to_sym)
    end
    GROUPS[data['dbSymbol'].to_sym] = OpenStruct.new(db_symbol: data['dbSymbol'].to_sym,
      system_tag: snake.call(data['systemTag']), terrain_tag: data['terrainTag'], tool: snake.call(data['tool']),
      custom_conditions: conditions, encounters: data['encounters'].map do |e|
        OpenStruct.new(specie: e['specie'].to_sym, form: e['form'], encounter_rate: e['randomEncounterChance'])
      end)
  end
end
load File.join(ROOT, '00015 HabitatList/54100 ZoneEncounterCatalog.rb')
path = File.join(ROOT, '00015 HabitatList/54200 ZoneEncounterPage.rb')
source = File.read(path, encoding: 'UTF-8').split('    # Category bands').first
eval(source + "\n  end\nend\n", TOPLEVEL_BINDING, path)
