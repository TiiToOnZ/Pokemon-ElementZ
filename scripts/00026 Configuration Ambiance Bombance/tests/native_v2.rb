# frozen_string_literal: true
# Native renderer fixture, NOT a running saved game. Actual Route 1 tiles and
# character assets; fixed autotile frame, representative native TJN tones.
require_relative 'support'
require 'benchmark'
require File.join(ENV.fetch('LOCALAPPDATA'), 'Programs/pokemon-studio/resources/psdk-binaries/lib/LiteRGSS')
%i[Sprite Plane Tone Color Image Texture].each { |name| Object.send(:remove_const, name) }
%i[Tone Color Image Rect].each { |name| Object.const_set(name, LiteRGSS.const_get(name)) }
Texture = LiteRGSS::Bitmap
import_node(Object, File.join(SDK, '0_Dependencies.rb'), 'class Sprite < LiteRGSS::ShaderedSprite', :CLASS)
import_node(Object, File.join(SDK, '0_Dependencies.rb'), 'class Plane < Sprite', :CLASS)
class Shader < LiteRGSS::Shader
  def self.create(name)
    raise "Unexpected shader #{name}" unless name == :plane
    new("#version 130\n" + Plane::SHADER)
  end
end
module Graphics
  def self.width; 320; end
  def self.height; 240; end
end
module RPG::Cache
  @textures = {}
  def self.textures; @textures; end
  def self.animation(name)
    @textures[name] ||= Texture.new(File.join(ROOT, 'graphics/animations', name + '.png'))
  end
  def self.fog(name, hue = 0)
    Texture.new(File.join(ROOT, 'graphics/fogs', name + '.png'))
  end
end
class Spriteset_Map
  attr_reader :viewport
  def initialize
    @viewport1 = @viewport = LiteRGSS::Viewport.new($window, 0, 0, 320, 240)
    init_sprites
    update_sprites
  end
end
CAPTURES = File.join(__dir__, 'captures_v2')
Dir.mkdir(CAPTURES) unless Dir.exist?(CAPTURES)
def draw; $scene.spriteset.send(:update_sprites); end
def light; $scene.spriteset.instance_variable_get(:@ambiance_light); end
def tick(count)
  count.times { $game_map.update; draw }
end
def snap(name)
  $scene.spriteset.viewport.sort_z
  $window.sort_z
  2.times { $window.update_no_input }
  bitmap = $window.snap_to_bitmap
  png = bitmap.to_png
  bitmap.dispose
  File.binwrite(File.join(CAPTURES, name + '.png'), png)
  png
end
$checks = 0
def check(condition, message)
  $checks += 1
  raise message unless condition
end
def load_texture(relative)
  texture = Texture.new(File.join(ROOT, 'graphics', relative + '.png'))
  $textures << texture
  texture
end
def make_sprite(viewport, texture, x, y, z, rect = nil, zoom = 1)
  sprite = Sprite.new(viewport)
  sprite.bitmap = texture
  sprite.src_rect.set(*rect) if rect
  sprite.set_position(x, y)
  sprite.zoom = zoom
  sprite.z = z
  $sprites << sprite
  sprite
end

begin
  $textures, $sprites = [], []
  $window = LiteRGSS::DisplayWindow.new('Bombance - diffuse light native fixture', 320, 240, 1, 32, 0)
  reset_fixture(27, effects: { rays: false })
  viewport = $scene.spriteset.viewport
  map = read_data('Data/Map027.rxdata')
  tileset = $data_tilesets[map.tileset_id]
  atlas = load_texture('tilesets/' + tileset.tileset_name)
  autotiles = tileset.autotile_names.map { |name| name.empty? ? nil : load_texture('autotiles/' + name) }
  crop_x, crop_y = 32, 15
  $game_map.display_x, $game_map.display_y = crop_x * 128, crop_y * 128
  3.times do |layer|
    15.times do |y|
      20.times do |x|
        tile = map.data[x + crop_x, y + crop_y, layer]
        next if tile.zero?
        texture = tile >= 384 ? atlas : autotiles[tile / 48 - 1]
        next unless texture
        tx, ty = tile >= 384 ? [(tile - 384) % 8 * 32, (tile - 384) / 8 * 32] : [tile % 48 * 32, 0]
        priority = tileset.priorities[tile]
        z = priority.zero? ? 0 : (y + priority + 1) * 32
        make_sprite(viewport, texture, x * 16, y * 16, z, [tx, ty, 32, 32], 0.5)
      end
    end
  end
  hero = load_texture('characters/player_m_walk')
  follower = load_texture('characters/0025')
  make_sprite(viewport, hero, 146, 112, 175, [0, 0, hero.width / 4, hero.height / 4])
  make_sprite(viewport, follower, 171, 116, 191, [0, 0, follower.width / 4, follower.height / 4])
  # Opaque UI sample in a separate native viewport; only visible in the dedicated
  # before/after protection comparison, never part of the four scenic captures.
  ui = LiteRGSS::Viewport.new($window, 0, 0, 320, 240)
  ui.z = 200
  ui_texture = Texture.new(320, 16)
  $textures << ui_texture
  pixels = Image.new(320, 16)
  pixels.fill_rect(0, 0, 320, 16, Color.new(29, 38, 52))
  pixels.copy_to_bitmap(ui_texture)
  pixels.dispose
  ui_sprite = make_sprite(ui, ui_texture, 0, 224, 0)
  ui_sprite.visible = false

  # Same tone equation as PSDK Shader::TONE_PROCESS, applied by the viewport.
  tone_shader = Shader.new("#version 130\nuniform sampler2D texture; uniform vec4 tone; void main() { vec4 frag = texture2D(texture, gl_TexCoord[0].xy); float luma = dot(frag.rgb, vec3(.299,.587,.114)); frag.rgb = mix(frag.rgb, vec3(luma), tone.w) + tone.rgb; gl_FragColor = frag; }")
  viewport.shader = tone_shader
  periods = { morning: [-75, -75, -10], day: [0, 0, 0], sunset: [-17, -51, -34], night: [-85, -85, -20] }
  original_plane = light.plane
  periods.each do |period, tone|
    %i[Morning Day Sunset Night].each { |name| $game_switches[Yuki::Sw.const_get("TJN_#{name}Time")] = name.to_s.downcase.to_sym == period }
    tone_shader.set_float_uniform('tone', tone.map { |v| v / 255.0 } + [0.0])
    draw
    tick(180)
    check(light.plane.equal?(original_plane), "Layer recreated for #{period}")
    snap(period.to_s)
    light.plane.visible = false
    snap(period.to_s + '_without_light')
    light.plane.visible = true
  end
  $game_switches[Yuki::Sw::TJN_NightTime] = false
  $game_switches[Yuki::Sw::TJN_DayTime] = true
  tone_shader.set_float_uniform('tone', [0.0, 0.0, 0.0, 0.0])
  draw
  tick(180)
  ui_sprite.visible = true
  snap('protection_with_light')
  light.plane.visible = false
  snap('protection_without_light')
  light.plane.visible = true
  ui_sprite.visible = false
  snap('motion_00')
  tick(600)
  snap('motion_10s')
  tick(1200)
  snap('motion_30s')

  # Separate CPU update cost from whole-window rendering (GPU submission/readback
  # is not a GPU-only timing). Seven alternating samples reduce order bias.
  adapter = light.method(:update)
  manager = BombanceAmbiance.manager
  adapter.call(manager)
  allocations_before = GC.stat(:total_allocated_objects)
  update_time = Benchmark.realtime { 20_000.times { adapter.call(manager) } }
  update_allocations = GC.stat(:total_allocated_objects) - allocations_before
  with_light, without_light = [], []
  7.times do |index|
    [index.even?, !index.even?].each do |visible|
      light.plane.visible = visible
      20.times { $window.update_no_input }
      duration = Benchmark.realtime { 200.times { $window.update_no_input } } * 1000 / 200
      (visible ? with_light : without_light) << duration
    end
  end
  light.plane.visible = true
  check(light.plane.equal?(original_plane), 'New Plane during render/update benchmark')
  check(RPG::Cache.textures.size == 1, 'Duplicate light texture')
  light_texture = light.plane.texture
  $env.current_weather_db_symbol = :fog
  draw
  tick(180)
  check(light.nil?, 'Fog retained invisible light Plane')
  check(original_plane.disposed?, 'Fade-to-fog Plane not disposed')
  check(!light_texture.disposed?, 'Cache-owned texture incorrectly disposed')
  $env.current_weather_db_symbol = :none
  draw
  tick(180)
  check(!light.nil?, 'Clear weather did not restore light')
  restored_plane = light.plane
  transfer(23, 20, 20)
  check(light.nil? && restored_plane.disposed?, 'Layer leaked into disabled destination map')
  transfer(27, 20, 20)
  tick(180)
  check(!light.nil?, 'Return to Route 1 did not restore light')
  final_plane = light.plane
  $scene.spriteset.dispose
  check(final_plane.disposed?, 'Scene disposal retained light Plane')
  results = { assertions: $checks, fixture: 'Native LiteRGSS; actual Route 1 tiles, static sample characters, representative default TJN tones; not a running game',
              crop: [crop_x, crop_y, 20, 15], cpu_light_update_ms: update_time * 1000 / 20_000,
              ruby_allocations_20000_light_updates: update_allocations,
              window_with_light_ms_samples: with_light, window_without_light_ms_samples: without_light,
              window_with_light_ms_median: with_light.sort[3], window_without_light_ms_median: without_light.sort[3],
              extra_window_ms_median: with_light.sort[3] - without_light.sort[3],
              light_layers: 1, cached_light_textures: RPG::Cache.textures.size }
  File.write(File.join(__dir__, 'native_v2_results.json'), JSON.pretty_generate(results) + "\n")
  puts JSON.pretty_generate(results)
  success = true
rescue StandardError => e
  warn "#{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
  success = false
ensure
  $scene&.spriteset&.dispose
  $sprites&.each { |sprite| sprite.dispose unless sprite.disposed? }
  $textures&.each { |texture| texture.dispose unless texture.disposed? }
  RPG::Cache.textures.each_value { |texture| texture.dispose unless texture.disposed? }
  ui&.dispose
  viewport&.dispose
  Plane.texture.dispose if $window
end
STDOUT.flush
exit!(success ? 0 : 1)
