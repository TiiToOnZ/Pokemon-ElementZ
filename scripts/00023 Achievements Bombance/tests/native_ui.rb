# frozen_string_literal: true
# Isolated native LiteRGSS render, no game boot or real save. Requires Studio Ruby.
# The temporary native window closes on exit. All captures stay in this test folder.
require_relative 'support'

%i[Sprite ShaderedSprite SpriteSheet Shape Text Color Viewport].each { |name| Object.send(:remove_const, name) }
Fonts = LiteRGSS::Fonts
Rect = LiteRGSS::Rect
Text = LiteRGSS::Text
Color = LiteRGSS::Color
Shape = LiteRGSS::Shape
Viewport = LiteRGSS::Viewport
module LiteRGSS::Text::Util
  DEFAULT_OUTLINE_SIZE = nil
  FOY = 2
end
installed_class('0_Dependencies.rb', 'class Sprite < LiteRGSS::ShaderedSprite')
installed_class('0_Dependencies.rb', 'class ShaderedSprite < Sprite')
installed_class('4_Systems_000_General_4_UI_Generics.rb', 'class SpriteSheet < ShaderedSprite')
module RPG
  module Cache
    @textures = {}
    class << self
      attr_reader :textures
      %i[interface icon].each do |kind|
        define_method(kind) do |name|
          path = File.join(ROOT, '../graphics', kind == :icon ? 'icons' : 'interface', "#{name}.png")
          @textures[path] ||= LiteRGSS::Bitmap.new(path)
        end
      end
    end
  end
end

$native_window = LiteRGSS::DisplayWindow.new('Bombance - test Succès', 320, 240, 2)
class << Viewport
  def create(*)
    new($native_window, 0, 0, 320, 240)
  end
end
fonts = JSON.parse(File.read(File.join(ROOT, '../Data/configs/texts_config.json')))['fonts']
fonts['ttfFiles'].each do |font|
  Fonts.load_font(font['id'], File.join(ROOT, '../Fonts', "#{font['name']}.ttf"))
  Fonts.set_default_size(font['id'], font['size'])
end
fonts['altSizes'].each { |size| Fonts.set_default_size(size['id'], size['size']) }
colors = LiteRGSS::Image.new(File.join(ROOT, '../graphics/windowskins/_colors.png'))
colors.width.times do |i|
  Fonts.define_outline_color(i, colors.get_pixel(i, 0))
  Fonts.define_fill_color(i, colors.get_pixel(i, 1))
  Fonts.define_shadow_color(i, colors.get_pixel(i, 2))
end
colors.dispose
$checks = 0
def check(value, message)
  raise message unless value
  $checks += 1
end

def snapshot(viewport, name)
  viewport.sort_z
  image = viewport.snap_to_bitmap
  image.to_png_file(File.join(__dir__, "#{name}.png"))
  image.dispose
end

def check_panel(panel)
  panel.stack.grep(Text).each do |text|
    check(text.text_width(text.text) <= text.width, "Text overflow: #{text.text}")
    check(text.x >= 0 && text.x + text.width <= 320 && text.y >= 0 && text.y + text.height <= 240,
          "Text outside screen: #{text.text}")
  end
end

begin
  harness = AchievementTest.new('native')
  harness.setup
  scene = harness.open_ui
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'categories_locked')
  harness.press(scene, :A)
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'general_v1')
  5.times { harness.press(scene, :DOWN) }
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'general_scrolled')
  harness.press(scene, :A)
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'unique_not_obtained')
  unique_texts = scene.instance_variable_get(:@panel).stack.grep(Text).map(&:text)
  check(unique_texts.include?('Non obtenu'), 'Unique status missing')
  check(unique_texts.none? { |value| value.include?('1/1') }, 'Artificial unique tier display')
  scene.dispose
  harness.capture(23)
  BombanceAchievements.unlock_category(:researcher)
  scene = harness.open_ui
  snapshot(scene.viewport, 'categories_unlocked')
  harness.press(scene, :DOWN)
  harness.press(scene, :A)
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'researcher_23')
  harness.press(scene, :A)
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'tiers_23')
  9.times { harness.press(scene, :DOWN) }
  check_panel(scene.instance_variable_get(:@panel))
  snapshot(scene.viewport, 'tiers_scrolled')
  objects = scene.instance_variable_get(:@panel).stack.dup
  viewport = scene.viewport
  scene.dispose
  scene.dispose
  check(objects.all?(&:disposed?) && viewport.disposed?, 'Native scene disposal leaked')
  12.times do
    scene = harness.open_ui
    8.times { harness.press(scene, :DOWN) }
    objects = scene.instance_variable_get(:@panel).stack.dup
    viewport = scene.viewport
    scene.dispose
    check(objects.all?(&:disposed?) && viewport.disposed?, 'Repeated native scene disposal leaked')
  end
  $scene = map = Scene_Map.new
  notifications = BombanceAchievements::Notifications
  notifications.update(map)
  panel = notifications.instance_variable_get(:@panel)
  check(!panel.nil?, "Native banner missing: #{$test_log.inspect}")
  check_panel(panel)
  snapshot(notifications.instance_variable_get(:@viewport), 'notification_category')
  notifications.detach
  notifications.update(map)
  panel = notifications.instance_variable_get(:@panel)
  check_panel(panel)
  snapshot(notifications.instance_variable_get(:@viewport), 'notification_tier')
  objects = panel.stack.dup
  notifications.reset
  check(objects.all?(&:disposed?), 'Native banner disposal leaked')

  # A unique event and a hidden manual achievement use the same native panels.
  secret = {category: :general, kind: :unique, source: :manual,
            title: 'Secret de test', description: 'Description révélée.',
            secret: true, hidden_description: true, hidden_reward: true,
            tiers: [{id: :completed, value: 1, reward: {type: :money, amount: 100}}]}
  harness.with_constant(:DEFINITIONS, BombanceAchievements::DEFINITIONS.merge(secret_test: secret)) do
    scene = harness.open_ui
    harness.press(scene, :A)
    6.times { harness.press(scene, :DOWN) }
    harness.press(scene, :A)
    check_panel(scene.instance_variable_get(:@panel))
    snapshot(scene.viewport, 'secret_hidden')
    scene.dispose
    BombanceAchievements.unlock_achievement(:secret_test)
    notifications.update(map)
    check_panel(notifications.instance_variable_get(:@panel))
    snapshot(notifications.instance_variable_get(:@viewport), 'notification_unique')
    notifications.reset
    scene = harness.open_ui
    harness.press(scene, :A)
    6.times { harness.press(scene, :DOWN) }
    harness.press(scene, :A)
    check_panel(scene.instance_variable_get(:@panel))
    snapshot(scene.viewport, 'unique_obtained')
    scene.dispose
  end

  # Native menu buttons, including the ninth entry, with actual icon textures.
  PFM.game_state.game_switches[100] = true
  PFM.game_state.game_switches[110] = true
  PFM.game_state.bag.add_item(:journal)
  menu = GamePlay::Menu.new
  menu.send(:create_viewport)
  menu.send(:create_buttons)
  buttons = menu.instance_variable_get(:@buttons)
  check(buttons.size == 9, 'Expected nine menu entries')
  check(buttons.all? { |button| button.y >= 0 && button.y + 24 <= 240 }, 'Menu overflow')
  check(buttons[3].send(:text) == 'Quêtes' && buttons[4].send(:text) == 'Succès', 'Menu labels/order')
  snapshot(menu.viewport, 'main_menu')
  buttons.each(&:dispose)
  menu.dispose
  check($test_log.empty?, "Unexpected errors: #{$test_log.inspect}")
  puts "Native LiteRGSS: #{$checks} checks passed; captures in #{__dir__}."
  RPG::Cache.textures.each_value(&:dispose)
  STDOUT.flush
  exit! 0
rescue Exception => error
  warn "#{error.class}: #{error.message}\n#{error.backtrace.first(8).join("\n")}"
  STDOUT.flush
  exit! 1
end
