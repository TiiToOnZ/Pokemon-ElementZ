# Export draw commands from the actual page with a simulated seen/caught state.
# render_grid_preview.ps1 rasterizes these commands using project assets/fonts.
require_relative 'support'
require 'json'
require 'fileutils'

$habitat_database = LOCAL_DATABASE
bounds_file = File.join(SCRIPTS, '00015 HabitatList/ui_previews/front_bounds.json')
RPG::Cache.front_bounds = JSON.parse(File.read(bounds_file, encoding: 'bom|UTF-8'))
def text_get(file, id)
  @preview_texts ||= {}
  values = @preview_texts[file] ||= Marshal.load(File.binread(File.join(PROJECT, "Data/Text/Dialogs/#{100000 + file}.fr.dat")))
  values[id]
end

area = LOCAL_DATABASE[:zones].fetch(:zone_5)
state = OpenStruct.new(game_map: OpenStruct.new(map_id: area.maps.first), game_switches: Hash.new(false), game_variables: Hash.new(0))
PFM.game_state = state
$env = OpenStruct.new(get_current_zone_data: area)
$pokedex = PFM::Pokedex.new(state)
$pokedex.national = true
snapshot = UI::Dex::ZoneEncounterEnvironments.build(ElementZ::Habitat::Catalog.new.snapshot)
raise 'Preview needs more than twelve entries' unless snapshot.entries.size > 12
snapshot.entries.each_with_index do |entry, i|
  $pokedex.mark_seen(entry.specie, entry.form, forced: true) unless i % 3 == 0
  $pokedex.mark_captured(entry.specie, entry.form) if i % 4 == 1
end
snapshot = UI::Dex::ZoneEncounterEnvironments.build(ElementZ::Habitat::Catalog.new.snapshot)

def draw_commands(snapshot, group, offset)
  view = UI::Dex::ZoneEncounterPage.new(nil)
  entries = group ? group.entries : snapshot.entries
  view.render(snapshot, group, entries, offset, group ? snapshot.groups.index(group) + 1 : 0)
  return view.stack.sort_by { |element| element.z || 0 }.filter_map do |element|
    next unless element.visible
    if element.bitmap
      {kind: :sprite, asset: element.bitmap.asset, x: element.x - element.ox * element.zoom_x,
       y: element.y - element.oy * element.zoom_y, width: element.bitmap.width * element.zoom_x,
       height: element.bitmap.height * element.zoom_y}
    elsif element.text && !element.text.empty?
      {kind: :text, text: element.text, x: element.x, y: element.y, width: element.width,
       height: element.height, align: element.align, font_id: element.font_id}
    end
  end
end

previews = {
  'ensemble_1' => draw_commands(snapshot, nil, 0),
  'ensemble_2' => draw_commands(snapshot, nil, 12),
  'milieu_fusionne' => draw_commands(snapshot, snapshot.groups.find { |g| g.members.any? { |m| m.status == :shadowed } }, 0)
}
special = ElementZ::Habitat::Snapshot.new(zone_name: 'Contrôle des sprites', zone_key: :preview, groups: [], issues: [])
special.entries = [[:wailord, 0], [:meowstic, 1], [:steelix, 30], [:bulbasaur, 0],
                   [:pikachu, 0], [:rattata, 1], [:vivillon, 12], [:eevee, 0],
                   [:geodude, 0], [:onix, 0], [:zubat, 0], [:magikarp, 0]].map.with_index do |(symbol, form), i|
  ElementZ::Habitat::Entry.new(specie: symbol, form: form, seen: i != 7, caught: i != 7 && i % 3 == 1, habitats: [])
end
previews['formes_et_inconnu'] = draw_commands(special, nil, 0)
environment = UI::Dex::ZoneEncounterEnvironments::View.new(key: :preview, label: 'Préférences horaires',
  status: :mixed, entries: special.entries, issues: [], members: [], periods: {})
special.entries.each_with_index do |entry, index|
  environment.periods[entry.key] = [15, 7, 14, 1, 2, 4, 8, 15, 3, 12, 5, 10][index]
end
special.groups = [environment]
previews['horaires_et_capture'] = draw_commands(special, environment, 0)
area = LOCAL_DATABASE[:zones].values.find { |zone| zone.wild_groups.include?(:group_35) }
$env.get_current_zone_data = area
state.game_map.map_id = 29
cave = UI::Dex::ZoneEncounterEnvironments.build(ElementZ::Habitat::Catalog.new.snapshot)
previews['grotte_fusionnee'] = draw_commands(cave, cave.groups.find { |group| group.key == :group_35 }, 0)
output = File.join(SCRIPTS, '00015 HabitatList/ui_previews')
FileUtils.mkdir_p(output)
File.write(File.join(output, 'draw_commands.json'), JSON.pretty_generate(previews), encoding: 'UTF-8')
puts "Preview: #{snapshot.zone_name}, #{snapshot.entries.size} entries; #{previews.size} frames exported."
