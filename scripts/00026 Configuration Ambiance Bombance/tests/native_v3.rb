# frozen_string_literal: true
# Native renderer fixture, NOT a running saved game. Actual Route 1 tiles and
# character assets; fixed autotile frame, representative native TJN tones.
require_relative 'support'
require_relative 'rays_regression_config'
RaysRegressionConfig.install
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
CAPTURES = File.join(__dir__, 'captures_v3')
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
  $window = LiteRGSS::DisplayWindow.new('Bombance - sun rays native fixture', 320, 240, 1, 32, 0)
  reset_fixture(27, effects: { clouds: false }) # isolate palette / character checks
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
  def rays; $scene.spriteset.instance_variable_get(:@ambiance_rays); end
  def ray_sprites; rays ? rays.sprites.values : []; end
  def set_period(period)
    hour = {morning: 9, day: 15, sunset: 20.5, night: 1}.fetch(period)
    $game_variables[Yuki::Var::TJN_Hour], $game_variables[Yuki::Var::TJN_Min] = (hour * 60).to_i.divmod(60)
    %i[Morning Day Sunset Night].each { |name| $game_switches[Yuki::Sw.const_get("TJN_#{name}Time")] = name.to_s.downcase.to_sym == period }
    draw
  end
  def pair(name)
    with_rays = snap(name + '_with_rays')
    ray_sprites.each { |sprite| sprite.visible = false }
    without_rays = snap(name + '_without_rays')
    draw
    [with_rays, without_rays]
  end
  def render_cost
    with_rays, without_rays = [], []
    7.times do |index|
      [index.even?, !index.even?].each do |visible|
        ray_sprites.each { |sprite| sprite.visible = visible }
        20.times { $window.update_no_input }
        ms = Benchmark.realtime { 200.times { $window.update_no_input } } * 1000 / 200
        (visible ? with_rays : without_rays) << ms
      end
    end
    draw
    { with_rays_ms: with_rays, without_rays_ms: without_rays,
      with_rays_median_ms: with_rays.sort[3], without_rays_median_ms: without_rays.sort[3],
      extra_median_ms: with_rays.sort[3] - without_rays.sort[3] }
  end
  # Default TJN: morning uses dawn tone (index 4), 01:00 uses index 2.
  periods = { morning: [17, -17, -34], day: [0, 0, 0], sunset: [-17, -51, -34], night: [-75, -75, -10] }
  day_sprites = nil
  periods.each do |period, tone|
    set_period(period)
    tone_shader.set_float_uniform('tone', tone.map { |v| v / 255.0 } + [0.0])
    tick(241)
    on, off = pair(period.to_s)
    check(on != off, "Invisible rays: #{period}")
    check(ray_sprites.size == 10, "Wrong pool size: #{period}")
    check(ray_sprites.count(&:visible) == {morning: 5, day: 10, sunset: 6, night: 3}[period], "Wrong density: #{period}")
    if day_sprites
      check(day_sprites == ray_sprites, 'Hour change recreated rays')
    else
      day_sprites = ray_sprites
    end
  end
  hourly = {}
  [11, 15, 18, 1].each do |hour|
    period = hour == 1 ? :night : :day
    set_period(period)
    $game_variables[Yuki::Var::TJN_Hour] = hour
    draw
    tone_shader.set_float_uniform('tone', periods.fetch(period).map { |v| v / 255.0 } + [0.0])
    tick(241)
    pair("hour_#{hour.to_s.rjust(2, '0')}")
    hourly[hour] = { density: rays.density, visible: ray_sprites.count(&:visible), pool: ray_sprites.size }
    check(ray_sprites == day_sprites, 'Hourly capture recreated pool')
  end
  set_period(:day)
  tone_shader.set_float_uniform('tone', [0.0, 0.0, 0.0, 0.0])
  tick(241)
  # The single sprite now lights characters too; upper UI stays untouched.
  hero_sprite.set_position(65, 140)
  follower_sprite.set_position(166, 144)
  ui_sprite.y = 96
  ui_sprite.visible = true
  pair('protection')
  ui.z = 20_000 # native message viewport priority
  pair('dialogue')
  ui.z = 200
  hero_sprite.visible = follower_sprite.visible = false
  ui_sprite.visible = false
  pair('uncovered_ground')
  hero_sprite.visible = follower_sprite.visible = true
  ui_sprite.visible = false
  hero_sprite.set_position(146, 112)
  follower_sprite.set_position(171, 116)
  pair('motion_00')
  tick(600)
  pair('motion_10s')
  tick(1200)
  pair('motion_30s')

  $env.current_weather_db_symbol = :rain
  draw; tick(181)
  on, off = pair('rain')
  check(on != off, 'Attenuated rain light missing')
  $env.current_weather_db_symbol = :fog
  draw; tick(181)
  on, off = pair('fog')
  check(on == off && rays.hidden?, 'Light remains under Fog')
  check(ray_sprites == day_sprites, 'Fog destroyed reusable pool')
  $env.current_weather_db_symbol = :none
  draw; tick(241)
  # Observe the actual native cloud motion (no replacement plane, no edited
  # offsets). Isolate one existing ray only for the comparative captures.
  BombanceAmbiance.clear_overrides
  draw
  cloud_captures = {}
  focused_key = '27:1'
  shadow_seen = false
  hero_sprite.set_position(146, 112)
  6000.times do |step|
    tick(1)
    transmission = rays.instance_variable_get(:@transmissions).fetch(focused_key)
    state = if transmission >= 0.999
              shadow_seen ? 'reappeared' : 'clear'
            elsif transmission <= 0.001
              shadow_seen = true
              'shadow'
            elsif transmission.between?(0.4, 0.6)
              'partial'
            end
    next unless state && !cloud_captures.key?(state)

    rays.sprites.each { |key, sprite| sprite.visible = key == focused_key }
    on = snap('cloud_' + state + '_with_rays')
    rays.sprites.fetch(focused_key).visible = false
    off = snap('cloud_' + state + '_without_rays')
    check(state == 'shadow' ? on == off : on != off, "Wrong cloud visibility: #{state}")
    cloud_captures[state] = { step: step, transmission: transmission,
                              origin: [$scene.spriteset.fog.ox, $scene.spriteset.fog.oy] }
    draw
    if state == 'clear' || (state == 'reappeared' && !cloud_captures.key?('clear'))
      [45, 65, 85].each_with_index do |x, index|
        hero_sprite.set_position(x, 140)
        rays.sprites.each { |key, sprite| sprite.visible = key == focused_key }
        snap("player_crossing_#{index}_with_rays")
        rays.sprites.fetch(focused_key).visible = false
        snap("player_crossing_#{index}_without_rays")
        draw
      end
      hero_sprite.set_position(146, 112)
    end
    break if %w[clear partial shadow reappeared].all? { |name| cloud_captures.key?(name) }
  end
  check(%w[clear partial shadow reappeared].all? { |name| cloud_captures.key?(name) }, 'Incomplete natural cloud cycle')

  # Native shader projection witness: opaque white under ONLY the original
  # cloud plane. Pixel checker validates the real wrap/zoom/origin transform.
  white_texture = Texture.new(320, 240)
  $textures << white_texture
  white_image = Image.new(320, 240)
  white_image.fill_rect(0, 0, 320, 240, Color.new(255, 255, 255, 255))
  white_image.copy_to_bitmap(white_texture)
  white_image.dispose
  white_sprite = make_sprite(viewport, white_texture, 0, 0, 2999)
  snap('cloud_projection')
  fog = $scene.spriteset.fog
  projection = { origin: [fog.ox, fog.oy], zoom: [fog.zoom_x, fog.zoom_y], opacity: fog.opacity }
  white_sprite.visible = false
  original_sprites = ray_sprites
  ray_texture = original_sprites.first.bitmap
  cpu = Benchmark.realtime { 20_000.times { BombanceAmbiance.manager.state.step_rays; rays.update(BombanceAmbiance.manager, $scene.spriteset.fog) } } * 1000 / 20_000
  check(original_sprites == ray_sprites, 'Stable updates recreated rays')
  ten = render_cost
  check(RPG::Cache.textures.size == 2, 'Unexpected light texture count')

  check(ray_sprites.size == 10, 'Expected fixed pool of ten')
  stress_sprites = ray_sprites
  transfer(23, 20, 20)
  check(rays.nil? && stress_sprites.all?(&:disposed?), 'Rays leaked into disabled destination')
  [30, 36, 80].each do |id|
    transfer(id, 10, 10)
    check(rays.nil?, "Rays created on map #{id}")
  end
  transfer(27, 40, 25)
  tick(241)
  check(!rays.nil?, 'Return to Route 1 did not restore rays')
  final_sprites = ray_sprites
  $scene.spriteset.dispose
  check(final_sprites.all?(&:disposed?), 'Scene disposal retained rays')
  check(!ray_texture.disposed?, 'Cache-owned mask incorrectly disposed')
  results = {
    assertions: $checks,
    fixture: 'Native LiteRGSS; actual Route 1 tiles and sample characters; representative default TJN tones, not a running game',
    crop: [crop_x, crop_y, 20, 15], cpu_ten_rays_update_ms: cpu,
    ten_rays_window: ten, hourly: hourly, additional_ray_textures: 1,
    cloud_captures: cloud_captures, cloud_projection: projection
  }
  File.write(File.join(__dir__, 'native_v3_results.json'), JSON.pretty_generate(results) + "\n")
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
