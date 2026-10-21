# frozen_string_literal: true
# Native compositor fixture, not a complete interactive battle. Real Plane,
# shader, WeatherSprite/Animation/wait pipeline and existing project textures.
require_relative 'support'
CAPTURES = File.join(__dir__, 'mist_captures')
Dir.mkdir(CAPTURES) unless Dir.exist?(CAPTURES)

Object.send(:remove_const, :Plane)
Object.send(:remove_const, :Viewport)
%i[Color Tone Image Rect Text Fonts].each { |name| Object.const_set(name, LiteRGSS.const_get(name)) }
Texture = LiteRGSS::Bitmap
installed('0_Dependencies.rb', 'class Sprite < LiteRGSS::ShaderedSprite')
installed('0_Dependencies.rb', 'class Plane < Sprite')
class Shader < LiteRGSS::Shader
  def self.create(name)
    raise "Unexpected shader #{name}" unless name == :plane
    new("#version 130\n" + Plane::SHADER)
  end
end

class Viewport < LiteRGSS::Viewport
  def initialize
    super($native_window, 0, 0, 320, 240)
    self.z = 500
  end
end
module RPG::Cache
  @textures = {}
  class << self
    attr_reader :textures
    def texture(path)
      @textures[path] ||= Texture.new(File.join(ROOT, 'graphics', path + '.png'))
    end
    def animation(name); texture("animations/#{name}"); end
  end
end

class NativeVisualTest < WeatherTest
  def sprite(viewport, path, x, y, z)
    value = Sprite.new(viewport)
    value.bitmap = RPG::Cache.texture(path)
    value.set_position(x, y)
    value.z = z
    @drawables << value
    value
  end

  def snapshot(name = nil)
    @scene.visual.viewport.sort_z
    @ui.sort_z
    $native_window.sort_z
    2.times { $native_window.update_no_input } # flush the native double buffer
    bitmap = $native_window.snap_to_bitmap
    bitmap.to_png_file(File.join(CAPTURES, "#{name}.png")) if name
    result = Image.new(bitmap.to_png, true)
    bitmap.dispose
    result
  end

  def rgba(image, x, y)
    c = image.get_pixel(x, y)
    [c.red, c.green, c.blue, c.alpha]
  end

  def test_native_composition_and_lifecycles
    $native_window = LiteRGSS::DisplayWindow.new('Bombance - verification brouillard', 320, 240, 1, 32, 0)
    font = JSON.parse(File.read(File.join(ROOT, 'Data/configs/texts_config.json')))['fonts']['ttfFiles'].first
    Fonts.load_font(0, File.join(ROOT, 'Fonts', font['name'] + '.ttf'))
    Fonts.set_default_size(0, 12)
    Fonts.define_fill_color(0, Color.new(255, 255, 255))
    Fonts.define_outline_color(0, Color.new(0, 0, 0))
    texture_image = Image.new(File.join(ROOT, 'graphics/animations/bombance_weather/mist_wisps.png'))
    texture_image.height.times do |y|
      assert_equal 0, texture_image.get_pixel(0, y).alpha
      assert_equal 0, texture_image.get_pixel(texture_image.width - 1, y).alpha
    end
    texture_image.width.times do |x|
      assert_equal 0, texture_image.get_pixel(x, 0).alpha
      assert_equal 0, texture_image.get_pixel(x, texture_image.height - 1).alpha
    end
    texture_image.dispose
    cases = %w[grass_night marsh_day].product([1, 2, 3])
    cases += %w[marsh_morning marsh_sunset marsh_night].map { |name| [name, 1] }
    cases.each do |background, count|
      setup
      battle
      @drawables = []
      @ui = Viewport.new
      @ui.z = 501
      main = @scene.visual.viewport
      sprite(main, "battlebacks/back_#{background}", 0, 0, -500)
      suffix = {1 => '', 2 => '_double', 3 => '_triple'}.fetch(count)
      enemy_base = sprite(main, "battlebacks/default_bases/enemy_base#{suffix}", 230, 111, 100)
      enemy_base.set_origin(enemy_base.bitmap.width / 2, enemy_base.bitmap.height / 2)
      player_base = sprite(main, "battlebacks/default_bases/player_base#{suffix}", 83, 180, 500)
      player_base.set_origin(player_base.bitmap.width / 2, player_base.bitmap.height / 2)
      enemies = {1 => [[230, 110]], 2 => [[200, 99], [264, 119]], 3 => [[170, 94], [224, 106], [278, 120]]}.fetch(count)
      players = {1 => [[78, 192]], 2 => [[38, 193], [116, 181]], 3 => [[23, 194], [80, 188], [137, 178]]}.fetch(count)
      [enemies, players].each_with_index do |positions, bank|
        positions.each_with_index do |(x, y), index|
          pkm = sprite(main, "pokedex/#{bank.zero? ? 'pokefront/0094' : 'pokeback/0025'}", x, y, bank.zero? ? 101 + index : 501 + index)
          pkm.set_origin(pkm.bitmap.width / 2, pkm.bitmap.height)
          bar = sprite(@ui, "interface/battle/#{bank.zero? ? 'battlebar_en' : 'battlebar_actor'}", bank.zero? ? 2 : 184, (bank.zero? ? 4 : 100) + index * 31, 0)
          label = Text.new(0, @ui, bar.x + 6, bar.y + 2, 125, 16, bank.zero? ? 'Ectoplasma N.25' : 'Pikachu N.25')
          label.z = 2
          @drawables << label
        end
      end
      panel = LiteRGSS::Shape.new(@ui, :rectangle, 320, 40)
      panel.set_position(0, 200)
      panel.color = Color.new(30, 45, 65)
      panel.z = 5
      @drawables << panel
      label = Text.new(0, @ui, 8, 202, 305, 30, 'Attaque     Sac     Equipe     Fuite')
      label.z = 6
      @drawables << label
      positions_before = @drawables.map { |v| [v.x, v.y, v.z] }
      before = snapshot("#{background}_#{count}v#{count}_clear")
      $options.show_animation = true
      enter
      after = snapshot("#{background}_#{count}v#{count}_fog")
      assert fog_layer.plane.is_a?(Plane)
      assert_equal BombanceWeather::FOG_OPACITY, fog_layer.plane.opacity
      assert_equal 2, fog_layer.mist_planes.size
      assert @scene.visual.weather.done?
      assert_equal positions_before, @drawables.map { |v| [v.x, v.y, v.z] }
      changed = 0
      # Compare complete menu pixels: the higher viewport is untouched.
      (200...240).step(2) do |y|
        (0...320).step(2) { |x| assert_equal rgba(before, x, y), rgba(after, x, y) }
      end
      (40...100).step(3) do |y|
        (140...315).step(3) { |x| changed += 1 if rgba(before, x, y) != rgba(after, x, y) }
      end
      assert_operator changed, :>, 100, 'Fog must visibly change background pixels'
      if background == 'marsh_day' && count == 1
        capture_start = Graphics.current_time
        [0, 3, 6, 9].each do |seconds|
          Graphics.time = capture_start + seconds
          @scene.visual.update
          frame = snapshot("motion_#{seconds}s")
          if seconds.positive?
            differences = 0
            (80...190).step(2) do |y|
              (0...320).step(2) { |x| differences += 1 if rgba(after, x, y) != rgba(frame, x, y) }
            end
            assert_operator differences, :>, 100, 'Wisps must visibly move'
          end
          frame.dispose
        end
        planes = fog_layer.mist_planes.dup
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        6000.times do
          Graphics.time += 1.0 / 60
          fog_layer.update
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        puts format("\nFog update: %.4f ms/frame (6000 updates)", elapsed * 1000 / 6000)
        assert_equal planes, fog_layer.mist_planes
        assert_operator elapsed / 6000, :<, 0.005
        [false, true].each do |visible|
          planes.each { |p| p.visible = visible }
          20.times { $native_window.update_no_input }
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          300.times do
            Graphics.time += 1.0 / 60
            @scene.visual.update
            $native_window.update_no_input
          end
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          puts format('Native render, mist %s: %.3f ms/frame (300 frames, uncapped)', visible ? 'ON' : 'OFF', elapsed * 1000 / 300)
        end
        # Both sides of the modulo seam must render identically.
        planes.first.ox = planes.first.bitmap.width - 0.0001
        seam_before = snapshot
        planes.first.ox = 0.0001
        seam_after = snapshot
        (0...240).step(2) do |y|
          (0...320).step(2) { |x| assert_equal rgba(seam_before, x, y), rgba(seam_after, x, y) }
        end
        seam_before.dispose
        seam_after.dispose
      end
      %i[rain sunny none].each do |weather|
        $options.show_animation = false
        old = fog_layer
        change(weather)
        assert old.plane.disposed?
        assert old.mist_planes.all?(&:disposed?)
        assert_nil fog_layer
        restored = snapshot(background == 'marsh_day' && count == 1 && weather == :none ? 'motion_after_clear' : nil)
        # Full native frame identical again: no ghosts, offsets or lost UI.
        240.times do |y|
          (0...320).step(4) { |x| assert_equal rgba(before, x, y), rgba(restored, x, y) }
        end
        restored.dispose
        $env.apply_weather(:fog)
        @scene.visual.update
      end
      last = fog_layer
      @scene.visual.dispose
      assert last.plane.disposed?
      assert last.mist_planes.all?(&:disposed?)
      assert main.disposed?
      refute RPG::Cache.animation('fog').disposed?
      @drawables.each { |v| v.dispose unless v.disposed? }
      @ui.dispose
      before.dispose
      after.dispose
    end
  ensure
    @drawables&.each { |v| v.dispose unless v.disposed? }
    @scene&.visual&.dispose unless @scene&.visual&.viewport&.disposed?
    @ui.dispose if @ui && !@ui.disposed?
    RPG::Cache.textures.each_value { |v| v.dispose unless v.disposed? }
    Plane.texture.dispose if $native_window
    # DisplayWindow#dispose terminates this Studio runtime. Leave the window
    # to process exit, like the other native harnesses, after reporting results.
  end
end

# Match the existing native harnesses: explicit exit after ensure cleanups,
# avoiding LiteRGSS shutdown handlers overriding the test process exit code.
success = Minitest.run(ARGV)
STDOUT.flush
exit!(success ? 0 : 1)
