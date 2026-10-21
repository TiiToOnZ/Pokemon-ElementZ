# frozen_string_literal: true
# Native Plane/FogFix comparison, on a neutral checkerboard (not a game map
# screenshot). Requires Studio Ruby + LiteRGSS; opens one short-lived window.
require_relative 'support'
require 'digest'
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
  @loaded = []
  def self.loaded; @loaded; end
  def self.fog(name, hue = 0)
    raise 'Unexpected hue in native fixture' unless hue.zero?
    texture = Texture.new(File.join(ROOT, 'graphics/fogs', name + '.png'))
    @loaded << texture
    texture
  end
end
class Spriteset_Map
  attr_reader :viewport
  def initialize
    @viewport1 = @viewport = LiteRGSS::Viewport.new($cloud_window, 0, 0, 320, 240)
    init_sprites
    update_sprites
  end
end

CAPTURES = File.join(__dir__, 'captures')
Dir.mkdir(CAPTURES) unless Dir.exist?(CAPTURES)
$checks = 0
def check(condition, message)
  $checks += 1
  raise message unless condition
end
def draw
  $scene.spriteset.send(:update_sprites)
end
def capture(name)
  $scene.spriteset.viewport.sort_z
  $cloud_window.sort_z
  2.times { $cloud_window.update_no_input }
  bitmap = $cloud_window.snap_to_bitmap
  png = bitmap.to_png
  File.binwrite(File.join(CAPTURES, name + '.png'), png)
  bitmap.dispose
  Digest::SHA256.hexdigest(png)
end

begin
  $cloud_window = LiteRGSS::DisplayWindow.new('Bombance - cloud continuity fixture', 320, 240, 1, 32, 0)
  reset_fixture(27, effects: { diffuse_light: false, rays: false })
  viewport = $scene.spriteset.viewport
  background = Texture.new(320, 240)
  pixels = Image.new(320, 240)
  15.times do |y|
    20.times do |x|
      color = (x + y).even? ? Color.new(146, 174, 120) : Color.new(157, 184, 131)
      pixels.fill_rect(x * 16, y * 16, 16, 16, color)
    end
  end
  pixels.copy_to_bitmap(background)
  pixels.dispose
  ground = Sprite.new(viewport)
  ground.bitmap = background
  ground.z = 0
  plane = $scene.spriteset.fog
  187.times { $game_map.update }
  draw
  NATIVE_FOG.bind($scene.spriteset).call
  original = capture('01_native_same_map')
  draw
  patched = capture('02_continuity_same_map')
  check(original == patched, 'Single-map pixels changed')
  check(plane.zoom_x == 0.5 && plane.opacity == 90 && plane.blend_type == 0, 'FogFix appearance changed')

  [[23, 31, $game_map.height, 'bourg'], [27, 20, -1, 'route'],
   [25, 12, -1, 'cocovin']].each do |target_id, x, y, label|
    $game_player.moveto(x, y)
    draw
    link = Yuki::MapLinker.map_datas.find { |v| v.map_id == target_id }
    next_x, next_y = x + link.offset_x, y + link.offset_y
    # Expected frame at the transfer's next logical tick, without resetting or
    # changing the spatial coordinate system. No production state is changed.
    plane.set_origin(plane.ox - $game_map.fog_sx / 8.0, plane.oy - $game_map.fog_sy / 8.0)
    expected = capture("03_#{label}_expected")
    transfer(target_id, next_x, next_y)
    actual = capture("04_#{label}_continuous")
    check(expected == actual, "Boundary pixel mismatch: #{label}")
    NATIVE_FOG.bind($scene.spriteset).call
    legacy = capture("05_#{label}_legacy_reset")
    check(legacy != actual, "Fixture did not expose the old reset: #{label}")
    draw
    check(plane.equal?($scene.spriteset.fog), 'Second cloud Plane created')
  end

  context_id = BombanceAmbiance.manager.context.object_id
  textures_before = RPG::Cache.loaded.size
  # Bind once for a fair baseline, avoiding benchmark-only per-frame allocations.
  bound = NATIVE_FOG.bind($scene.spriteset)
  1000.times { bound.call }
  native = Benchmark.realtime { 20_000.times { bound.call } }
  adapter = $scene.spriteset.method(:update_fog_sprite_parameters)
  1000.times { adapter.call }
  patched_time = Benchmark.realtime { 20_000.times { adapter.call } }
  GC.start
  native_allocations_before = GC.stat(:total_allocated_objects)
  20_000.times { bound.call }
  native_allocations = GC.stat(:total_allocated_objects) - native_allocations_before
  GC.start
  allocations_before = GC.stat(:total_allocated_objects)
  20_000.times { adapter.call }
  allocations = GC.stat(:total_allocated_objects) - allocations_before
  check(context_id == BombanceAmbiance.manager.context.object_id, 'Context recreated per frame')
  check(textures_before == RPG::Cache.loaded.size, 'Texture allocation during updates')
  check(plane.equal?($scene.spriteset.fog), 'Plane allocation during updates')
  # Exercise native empty-fog / reload / scene disposal with actual GPU resources.
  previous_texture = plane.texture
  transfer(30, 10, 10)
  check(plane.texture.nil?, 'Interior still draws clouds')
  check(previous_texture.disposed?, 'Native replaced texture not released')
  transfer(27, 20, 20)
  check(!plane.texture.disposed?, 'Exterior texture not reloaded')
  $scene.spriteset.dispose
  check(plane.disposed?, 'Native Plane not disposed')
  results = { assertions: $checks, native_parameters_ms: native * 1000 / 20_000,
              patched_parameters_ms: patched_time * 1000 / 20_000,
              extra_ms: (patched_time - native) * 1000 / 20_000,
              native_ruby_allocations_20000_parameter_updates: native_allocations,
              ruby_allocations_20000_parameter_updates: allocations,
              same_map_pixel_identity: true, boundary_pixel_identity: true }
  File.write(File.join(__dir__, 'native_results.json'), JSON.pretty_generate(results) + "\n")
  puts JSON.pretty_generate(results)
  success = true
rescue StandardError => e
  warn "#{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
  success = false
ensure
  $scene&.spriteset&.fog&.dispose unless $scene&.spriteset&.fog&.disposed?
  ground&.dispose
  viewport&.dispose
  background&.dispose
  RPG::Cache.loaded.each { |texture| texture.dispose unless texture.disposed? }
  Plane.texture.dispose if $cloud_window
end
STDOUT.flush
exit!(success ? 0 : 1)
