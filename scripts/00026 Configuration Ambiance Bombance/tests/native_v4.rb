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
    return new("#version 130\n" + Plane::SHADER) if name == :plane
    raise "Unexpected shader #{name}" unless name == :color_shader
    new("#version 130\nuniform sampler2D texture; uniform vec4 color; void main() { vec4 frag = texture2D(texture, gl_TexCoord[0].xy); frag.rgb = mix(frag.rgb, color.rgb, color.a); frag.a *= gl_Color.a; gl_FragColor = frag; }")
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
CAPTURES = File.join(__dir__, 'captures_v4')
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
  $window = LiteRGSS::DisplayWindow.new('Bombance - fireflies native fixture', 320, 240, 1, 32, 0)
  reset_fixture(27, effects: { fireflies: true })
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
  hero_sprite = make_sprite(viewport, hero, 146, 112, 175, [0, 0, hero.width / 4, hero.height / 4])
  follower_sprite = make_sprite(viewport, follower, 171, 116, 191, [0, 0, follower.width / 4, follower.height / 4])
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


  tone_shader = Shader.new("#version 130\nuniform sampler2D texture; uniform vec4 tone; void main() { vec4 frag = texture2D(texture, gl_TexCoord[0].xy); float luma = dot(frag.rgb, vec3(.299,.587,.114)); frag.rgb = mix(frag.rgb, vec3(luma), tone.w) + tone.rgb; gl_FragColor = frag; }")
  viewport.shader = tone_shader
  def flies; $scene.spriteset.instance_variable_get(:@ambiance_fireflies); end
  def fly_sprites; flies ? flies.sprites.values : []; end
  def set_hour(value)
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = (value * 60).round.divmod(60)
    night, evening, day, morning = Yuki::TJN.current_time_set
    period = value >= night || value < morning ? :night : value >= evening ? :sunset : value >= day ? :day : :morning
    %i[Morning Day Sunset Night].each { |name| $game_switches[Yuki::Sw.const_get("TJN_#{name}Time")] = name.to_s.downcase.to_sym == period }
    draw
  end
  def pair(name)
    on = snap(name + '_with_fireflies')
    fly_sprites.each { |sprite| sprite.visible = false }
    off = snap(name + '_without_fireflies')
    draw
    [on, off]
  end
  def fly_state
    fly_sprites.map { |sprite| [sprite.x, sprite.y, sprite.opacity, sprite.object_id] }
  end
  periods = {
    morning: [7.25, [17, -17, -34], 11],
    day: [15, [0, 0, 0], 0],
    sunset: [20.5, [-17, -51, -34], 9],
    night: [1, [-75, -75, -10], 21]
  }
  observations = {}
  pool = nil
  periods.each do |period, (hour, tone, count)|
    set_hour(hour)
    tone_shader.set_float_uniform('tone', tone.map { |v| v / 255.0 } + [0.0])
    tick(241)
    on, off = pair(period.to_s)
    check(period == :day ? on == off : on != off, "Wrong visible fireflies: #{period}")
    check(fly_sprites.count(&:visible) == count, "Wrong density: #{period}")
    pool ||= fly_sprites.dup
    check(pool == fly_sprites, 'Period change recreated sprites')
    observations[period] = {hour: hour, visible: count, density: flies.density,
                            opacity: flies.base_opacity, sprite_count: fly_sprites.size}
  end
  check(flies.texture.width == 7 && flies.texture.height == 7, 'Oversized firefly texture')
  check(fly_sprites.all? { |sprite| sprite.shader.blend_type == 0 }, 'Unexpected blend mode')
  check(fly_sprites.map(&:bitmap).uniq.size == 1, 'Particles do not share texture')

  pair('night_motion_0')
  tick(120)
  pair('night_motion_2s')
  tick(240)
  pair('night_motion_6s')
  states = fly_state
  120.times { draw }
  check(states == fly_state, 'Menu redraw advances fireflies')
  BombanceAmbiance.override_effects(clouds: false)
  draw
  check(states == fly_state, 'Cloud override modulates fireflies')
  BombanceAmbiance.override_effects(clouds: true)
  draw
  check(states == fly_state, 'Cloud return modulates fireflies')
  check(fly_sprites.all? { |sprite| sprite.z > $scene.spriteset.fog.z }, 'Cloud plane covers fireflies')

  ui_sprite.y = (fly_sprites.find(&:visible).y - 5).clamp(0, 224)
  ui_sprite.visible = true
  pair('ui')
  ui.z = 20_000
  pair('dialogue')
  ui.z = 200
  ui_sprite.visible = false
  pair('ui_uncovered')
  ui_band = [0, ui_sprite.y, 320, ui_sprite.y + 16]

  # Verify the native alpha blend numerically against the exact 7x7 mask.
  # Black sits ABOVE the native fog, BELOW the self-lit particles.
  black_texture = Texture.new(320, 240)
  $textures << black_texture
  black_pixels = Image.new(320, 240)
  black_pixels.fill_rect(0, 0, 320, 240, Color.new(0, 0, 0, 255))
  black_pixels.copy_to_bitmap(black_texture)
  black_pixels.dispose
  black = make_sprite(viewport, black_texture, 0, 0, 3099)
  tone_shader.set_float_uniform('tone', [0.0, 0.0, 0.0, 0.0])
  snap('alpha_witness')
  alpha_witness = fly_sprites.select(&:visible).map { |sprite| [sprite.x, sprite.y, sprite.opacity] }
  black.visible = false
  tone_shader.set_float_uniform('tone', [-75 / 255.0, -75 / 255.0, -10 / 255.0, 0.0])

  weather_observations = {}
  {rain: 6, hardrain: 0, fog: 13, strong_winds: 0, none: 21}.each do |weather, count|
    $env.current_weather_db_symbol = weather
    draw; tick(241)
    on, off = pair(weather.to_s)
    check(count.zero? ? on == off : on != off, "Wrong weather rendering: #{weather}")
    check(fly_sprites.count(&:visible) == count, "Wrong weather count: #{weather}")
    check(pool == fly_sprites, 'Weather destroyed particle pool')
    check($game_map.fog_opacity == 90 && $scene.spriteset.fog.opacity == 90, 'Fog changed')
    weather_observations[weather] = {visible: count, density: flies.density, opacity: flies.base_opacity}
  end

  def update_cost(iterations = 20_000)
    manager = BombanceAmbiance.manager
    Benchmark.realtime do
      iterations.times do
        manager.instance_variable_set(:@fireflies_tick, manager.fireflies_tick + 1)
        flies.update(manager)
      end
    end * 1000 / iterations
  end
  cpu_21 = update_cost
  check(pool == fly_sprites, 'Stable updates recreated sprites')
  with, without = [], []
  7.times do |i|
    [i.even?, !i.even?].each do |visible|
      fly_sprites.each { |sprite| sprite.visible = visible }
      20.times { $window.update_no_input }
      elapsed = Benchmark.realtime { 200.times { $window.update_no_input } } * 1000 / 200
      (visible ? with : without) << elapsed
    end
  end
  draw
  $game_map.display_x += 20000
  draw
  check(fly_sprites.none?(&:visible), 'Offscreen particles still visible')
  cpu_offscreen = update_cost
  $game_map.display_x -= 20000
  draw
  check(fly_sprites.count(&:visible) == 21, 'Culled particles did not return')
  settings = BombanceAmbiance::Settings
  original_maps = settings::MAPS
  route = original_maps[27]
  settings.send(:remove_const, :MAPS)
  settings.const_set(:MAPS, original_maps.merge(27 => route.merge(fireflies_zones: route[:fireflies_zones] * 2)))
  BombanceAmbiance.clear_overrides
  draw; tick(241)
  check(fly_sprites.size == 42, 'Six-zone stress case missing particles')
  cpu_42 = update_cost
  settings.send(:remove_const, :MAPS)
  settings.const_set(:MAPS, original_maps)

  derived, base = flies.texture, RPG::Cache.animation('bombance_ambiance/firefly')
  previous_sprites = fly_sprites.dup
  [23, 30, 36, 80, 71].each do |id|
    transfer(id, 10, 10)
    check(flies.nil?, "Particles leaked to map #{id}")
  end
  check(previous_sprites.all?(&:disposed?) && derived.disposed?, 'Owned resources leaked')
  check(!base.disposed?, 'Shared cache disposed')
  transfer(27, 40, 25)
  tick(241)
  check(fly_sprites.size == 21, 'Route 1 return did not restore zones')
  $scene.spriteset.dispose
  results = {
    assertions: $checks,
    fixture: 'Native LiteRGSS, actual Route 1 tiles and default TJN tones; no gameplay/save writes',
    crop: [crop_x, crop_y, 20, 15], periods: observations, weather: weather_observations,
    zones: BombanceAmbiance::Settings::MAPS[27][:fireflies_zones], alpha_witness: alpha_witness,
    ui_band: ui_band, cpu_21_update_ms: cpu_21, cpu_42_update_ms: cpu_42,
    cpu_21_offscreen_ms: cpu_offscreen,
    render_with_ms: with, render_without_ms: without,
    render_with_median_ms: with.sort[3], render_without_median_ms: without.sort[3],
    texture: [7, 7], owned_textures_per_pool: 1, sprites_per_particle: 1
  }
  File.write(File.join(__dir__, 'native_v4_results.json'), JSON.pretty_generate(results) + "\n")
  puts JSON.pretty_generate(results)
  success = true
rescue StandardError => e
  warn "#{e.class}: #{e.message}\n#{e.backtrace.first(12).join("\n")}"
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
