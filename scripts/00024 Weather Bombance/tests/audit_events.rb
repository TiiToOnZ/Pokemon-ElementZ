# frozen_string_literal: true
# Read-only project audit. Does not load saves or execute any event scripts.
require 'json'
ROOT = File.expand_path('../../..', __dir__)
class AuditObject
  def self._load(*); new; end
  def method_missing(name, *); instance_variable_get("@#{name}"); end
end
def read_data(path)
  loop do
    begin
      return Marshal.load(File.binread(path))
    rescue ArgumentError => error
      raise unless error.message =~ /undefined class\/module (.+)/
      names = Regexp.last_match(1).sub(/::$/, '').split('::')
      scope = Object
      names.each do |name|
        scope = scope.const_defined?(name, false) ? scope.const_get(name, false) : scope.const_set(name, Class.new(AuditObject))
      end
    end
  end
end
report = {switch_writes: [], switch_conditions: [], script_references: [], common_weather_events: [], maps_scanned: 0}
scan = lambda do |list, location|
  list.each_with_index do |command, index|
    args = command.parameters
    if command.code == 121 && [39, 138].any? { |id| (args[0]..args[1]).cover?(id) }
      report[:switch_writes] << [location, index, args]
    elsif command.code == 111 && args[0] == 0 && [39, 138].include?(args[1])
      report[:switch_conditions] << [location, index, args]
    elsif [355, 655].include?(command.code) && args.join.match?(/MixWeather|\b138\b|\b39\b/)
      report[:script_references] << [location, index, args]
    end
  end
end
Dir[File.join(ROOT, 'Data/Map[0-9]*.rxdata')].sort.each do |path|
  map = read_data(path)
  report[:maps_scanned] += 1
  map.events.each do |id, event|
    event.pages.each_with_index do |page, page_id|
      location = "#{File.basename(path)} event #{id} page #{page_id + 1}"
      scan.call(page.list, location)
      condition = page.condition
      [1, 2].each do |n|
        if condition.send("switch#{n}_valid") && [39, 138].include?(condition.send("switch#{n}_id"))
          report[:switch_conditions] << [location, 'page', condition.send("switch#{n}_id")]
        end
      end
    end
  end
end
commons = read_data(File.join(ROOT, 'Data/CommonEvents.rxdata'))
commons.compact.each do |event|
  scan.call(event.list, "CommonEvent #{event.id}")
  if [60, 61].include?(event.id)
    report[:common_weather_events] << {id: event.id, name: event.name, trigger: event.trigger,
                                     switch_id: event.switch_id,
                                     commands: event.list.map { |c| [c.code, c.indent, c.parameters] }}
  end
end
system = read_data(File.join(ROOT, 'Data/System.rxdata'))
report[:switch_names] = [39, 138].to_h { |id| [id, system.switches[id]] }
report[:zones] = Dir[File.join(ROOT, 'Data/Studio/zones/*.json')].filter_map do |path|
  zone = JSON.parse(File.read(path))
  zone.slice('id', 'maps', 'forcedWeather') if [31, 32, 38, 39].include?(zone['id'])
end
puts JSON.pretty_generate(report)
