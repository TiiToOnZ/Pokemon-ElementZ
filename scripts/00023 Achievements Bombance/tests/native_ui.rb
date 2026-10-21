# frozen_string_literal: true
# Isolated native LiteRGSS render, no game boot or real save. Requires Studio Ruby.
# The temporary native window closes on exit. All captures stay in this test folder.
require_relative 'support'
require File.expand_path('../lib/LiteRGSS.so', File.dirname(RbConfig.ruby))

%i[Sprite ShaderedSprite SpriteSheet Shape Text Color Viewport Rect].each { |name| Object.send(:remove_const, name) }
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
      %i[interface icon windowskin].each do |kind|
        define_method(kind) do |name|
          folder = {icon: 'icons', interface: 'interface', windowskin: 'windowskins'}.fetch(kind)
          root = name == 'achievements/trophy' ? ENV.fetch('BOMBANCE_GRAPHICS', File.expand_path('../graphics', ROOT)) : File.expand_path('../graphics', ROOT)
          path = File.join(root, folder, "#{name}.png")
          @textures[path] ||= LiteRGSS::Bitmap.new(path)
        end
      end
    end
  end
end

$native_window = LiteRGSS::DisplayWindow.new('Bombance - test Succès', 320, 240, 1)
class << Viewport
  def create(x = :main, y = 0, width = 320, height = 240, z = 0)
    if x.is_a?(Symbol)
      z, x, y = y, 0, 0
    end
    new($native_window, x, y, width, height).tap { |vp| vp.z = z }
  end
end
boot_viewport = Viewport.create
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
boot_viewport.dispose
$checks = 0
def check(value, message)
  raise message unless value
  $checks += 1
end

def snapshot(viewport, name)
  viewport.sort_z
  $native_window.sort_z
  2.times { $native_window.update_no_input } # flush both native back buffers
  image = $native_window.snap_to_bitmap
  check(image.width == 320 && image.height == 240, 'Capture must be 320x240')
  image.to_png_file(File.join(__dir__, "#{name}.png"))
  image.dispose
  pixels = LiteRGSS::Image.new(File.join(__dir__, "#{name}.png"))
  nonblank = (0...240).step(8).any? do |y|
    (0...320).step(8).any? { |x| c = pixels.get_pixel(x, y); c.red + c.green + c.blue > 20 }
  end
  check(nonblank, "Blank capture: #{name}")
  pixels.dispose
end

def check_panel(panel)
  panel.stack.grep(Text).each do |text|
    check(text.text_width(text.text) <= text.width, "Text overflow: #{text.text}")
    check(text.x >= 0 && text.x + text.width <= 320 && text.y >= 0 && text.y + text.height <= 240,
          "Text outside screen: #{text.text}")
  end
end

def check_scene(scene)
  check_panel(scene.instance_variable_get(:@panel))
  panel = scene.instance_variable_get(:@list_panel)
  return unless panel
  vp = scene.instance_variable_get(:@list_viewport)
  panel.stack.grep(Text).each do |text|
    check(text.text_width(text.text) <= text.width, "Clipped text overflow: #{text.text}")
    check(text.x >= 0 && text.x + text.width <= vp.rect.width && text.y >= 0 && text.y + text.height <= vp.rect.height,
          "Text outside clipped list: #{text.text}")
  end
end

begin
  harness = AchievementTest.new('native')
  harness.setup
  scene = harness.open_ui
  check_scene(scene)
  snapshot(scene.viewport, 'categories_locked')
  harness.press(scene, :A)
  check_scene(scene)
  snapshot(scene.viewport, 'general_v1')
  5.times { harness.press(scene, :DOWN) }
  check_scene(scene)
  snapshot(scene.viewport, 'general_scrolled')
  harness.press(scene, :A)
  check_scene(scene)
  snapshot(scene.viewport, 'unique_not_obtained')
  unique_texts = [:@panel, :@list_panel].flat_map { |ivar| scene.instance_variable_get(ivar).stack.grep(Text).map(&:text) }
  check(unique_texts.include?('Non obtenu'), 'Unique status missing')
  check(unique_texts.none? { |value| value.include?('1/1') }, 'Artificial unique tier display')
  scene.dispose
  harness.capture(23)
  BombanceAchievements.unlock_category(:researcher)
  scene = harness.open_ui
  snapshot(scene.viewport, 'categories_unlocked')
  harness.press(scene, :DOWN)
  harness.press(scene, :A)
  check_scene(scene)
  snapshot(scene.viewport, 'researcher_23')
  harness.press(scene, :A)
  check_scene(scene)
  snapshot(scene.viewport, 'tiers_23')
  9.times { harness.press(scene, :DOWN) }
  check_scene(scene)
  snapshot(scene.viewport, 'tiers_middle')
  8.times { harness.press(scene, :DOWN) }
  check_scene(scene)
  check(scene.index == 17 && scene.offset == 13, 'Last of eighteen tiers is inaccessible')
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
  notifications.instance_variable_set(:@elapsed, 0.3)
  notifications.update(map)
  panel = notifications.instance_variable_get(:@panel)
  check(!panel.nil?, "Native banner missing: #{$test_log.inspect}")
  check_panel(panel)
  snapshot(notifications.instance_variable_get(:@viewport), 'notification_category')
  notifications.detach
  notifications.update(map)
  notifications.instance_variable_set(:@elapsed, 0.3)
  notifications.update(map)
  panel = notifications.instance_variable_get(:@panel)
  check_panel(panel)
  snapshot(notifications.instance_variable_get(:@viewport), 'notification_tier')
  objects = panel.stack.dup
  notifications.reset
  check(objects.all?(&:disposed?), 'Native banner disposal leaked')

  # More categories than fit: clipped cards leave the independent scrollbar clear.
  categories = BombanceAchievements::CATEGORIES.merge((1..8).to_h do |i|
    ["extra_#{i}".to_sym, {title: "Catégorie #{i}", description: 'Une description très longue ' * 20}]
  end)
  harness.with_constant(:CATEGORIES, categories) do
    scene = harness.open_ui
    5.times { harness.press(scene, :DOWN) }
    check_scene(scene)
    snapshot(scene.viewport, 'categories_scroll')
    scene.dispose
  end

  # Five component lot, including real object icons; navigation and timed pages.
  rewards = [{type: :item, id: :poke_ball, quantity: 5}, {type: :item, id: :potion, quantity: 2},
             {type: :money, amount: 37}, {type: :item, id: :great_ball, quantity: 1},
             {type: :money, amount: 100}]
  many = {category: :general, source: :manual, title: 'Récompenses multiples et titre extrêmement long',
          description: 'Une description très longue pour vérifier les retours et la troncature. ' * 20,
          unit: 'objectif', tiers: [{id: :completed, value: 1, reward: rewards}]}
  harness.with_constant(:DEFINITIONS, BombanceAchievements::DEFINITIONS.merge(many: many)) do
    BombanceAchievements.unlock_achievement(:many)
    notifications.reset
    scene = harness.open_ui
    harness.press(scene, :A)
    6.times { harness.press(scene, :DOWN) }
    harness.press(scene, :A)
    3.times do |page|
      check_scene(scene)
      snapshot(scene.viewport, "rewards_page_#{page + 1}")
      harness.press(scene, :RIGHT)
    end
    scene.dispose
    notifications.show(map, type: :tier, achievement: :many, tier: :completed)
    3.times do |page|
      notifications.instance_variable_set(:@elapsed, 0.5 + page * notifications::PAGE_SECONDS)
      notifications.update(map)
      check($test_log.empty?, "Popup animation error: #{$test_log.inspect}")
      check(notifications.instance_variable_get(:@page) == page, 'Popup page timing')
      check_panel(notifications.instance_variable_get(:@panel))
      snapshot(notifications.instance_variable_get(:@viewport), "popup_page_#{page + 1}")
    end
    notifications.reset
  end

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
    check_scene(scene)
    snapshot(scene.viewport, 'secret_hidden')
    scene.dispose
    BombanceAchievements.unlock_achievement(:secret_test)
    notifications.update(map)
    notifications.instance_variable_set(:@elapsed, 0.3)
    notifications.update(map)
    check_panel(notifications.instance_variable_get(:@panel))
    snapshot(notifications.instance_variable_get(:@viewport), 'notification_unique')
    notifications.reset
    scene = harness.open_ui
    harness.press(scene, :A)
    6.times { harness.press(scene, :DOWN) }
    harness.press(scene, :A)
    check_scene(scene)
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

  # Actual partial lot: first component obtained, second component still owed.
  harness.setup
  game = PFM.game_state
  Configs.settings.max_bag_item_count = 99
  game.bag.add_item(:potion, 98)
  harness.capture(5)
  BombanceAchievements.unlock_category(:researcher)
  scene = harness.open_ui
  harness.press(scene, :DOWN); harness.press(scene, :A); harness.press(scene, :A)
  check_scene(scene)
  snapshot(scene.viewport, 'detail_partial_payment')
  scene.dispose
  notifications.reset

  trophy_path = File.join(ENV.fetch('BOMBANCE_GRAPHICS', File.expand_path('../graphics', ROOT)), 'interface/achievements/trophy.png')
  trophy = LiteRGSS::Image.new(trophy_path)
  check(trophy.width == 22 && trophy.height == 22, 'Trophy dimensions')
  check(trophy.get_pixel(0, 0).alpha == 0 && trophy.get_pixel(10, 5).alpha == 255, 'Transparent trophy background')
  trophy.dispose
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
