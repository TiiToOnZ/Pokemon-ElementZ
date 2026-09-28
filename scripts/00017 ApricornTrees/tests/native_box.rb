# frozen_string_literal: true
# Isolated native graphics integration: no game boot, save, compilation or gameplay.
# Run with Studio Ruby and -r <Studio>/lib/LiteRGSS.so. Opens a temporary window.
# Optional APRICORN_UI_PREVIEW_DIR exports diagnostic captures outside game assets.
require 'json'
require 'ostruct'
ROOT = File.expand_path('../..', __dir__)
GAME = File.expand_path('..', ROOT)
NATIVE = File.join(ROOT, 'psdk_scripts')

# Evaluate complete installed class definitions, retaining their real native APIs.
def installed_class(file, header, scope = Object)
  path = File.join(NATIVE, file)
  lines = File.readlines(path)
  found = nil
  visit = lambda do |node|
    return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)
    if node.type == :CLASS && lines[node.first_lineno - 1].strip == header
      found = node
    else
      node.children.each { |child| visit.call(child) }
    end
  end
  visit.call(RubyVM::AbstractSyntaxTree.parse(lines.join))
  raise "Class not found: #{header}" unless found
  scope.module_eval(lines[(found.first_lineno - 1)..(found.last_lineno - 1)].join, path, found.first_lineno)
end

Fonts = LiteRGSS::Fonts
Rect = LiteRGSS::Rect
Text = LiteRGSS::Text
module LiteRGSS::Text::Util
  DEFAULT_OUTLINE_SIZE = nil
  FOY = 2
end
source = File.read(File.join(NATIVE, '0_Dependencies.rb'))
a = source.index('    def multiline_text=(value)')
b = source.index("\n  end\nend", a)
Text.class_eval(source[a...b])
installed_class('0_Dependencies.rb', 'class Sprite < LiteRGSS::ShaderedSprite')
installed_class('0_Dependencies.rb', 'class ShaderedSprite < Sprite')
installed_class('4_Systems_000_General_4_UI_Generics.rb', 'class SpriteSheet < ShaderedSprite')
module Input
  Keyboard = Sf::Keyboard
  Keys = {B: [Keyboard::X]}.freeze
end
module UI; end
%w[SpriteStack GenericBase ItemSprite KeyShortcut].each do |name|
  header = {'SpriteStack' => 'class SpriteStack', 'GenericBase' => 'class GenericBase < SpriteStack',
            'ItemSprite' => 'class ItemSprite < Sprite', 'KeyShortcut' => 'class KeyShortcut < Sprite'}[name]
  installed_class('4_Systems_000_General_4_UI_Generics.rb', header, UI)
end
module Studio; end
installed_class('3_Studio.rb', 'class Item', Studio)
installed_class('3_Studio.rb', 'class BallItem < Item', Studio)

module RPG
  module Cache
    @textures = {}
    class << self
      attr_reader :textures
      %i[interface icon pokedex].each do |kind|
        define_method(kind) do |name|
          folder = kind == :icon ? 'icons' : kind.to_s
          path = File.join(GAME, 'graphics', folder, "#{name}.png")
          @textures[path] ||= LiteRGSS::Bitmap.new(path)
        end
      end
    end
  end
end
ITEMS = {}
Dir[File.join(GAME, 'Data/Studio/items/*.json')].each do |path|
  data = JSON.parse(File.read(path))
  klass = data['klass'] == 'BallItem' ? Studio::BallItem : Studio::Item
  item = klass.allocate
  item.instance_variable_set(:@db_symbol, data['dbSymbol'].to_sym)
  item.instance_variable_set(:@id, data['id'])
  item.instance_variable_set(:@icon, data['icon'])
  ITEMS[item.db_symbol] = item
end
TEXTS = %w[fr en es it].to_h do |lang|
  [lang, [12, 13].to_h { |id| [id, Marshal.load(File.binread(File.join(GAME, "Data/Text/Dialogs/#{100000 + id}.#{lang}.dat")))] }]
end
module Kernel
  def data_item(symbol); ITEMS.fetch(symbol); end
  def text_get(file, id); TEXTS.fetch($options.language).fetch(file).fetch(id); end
end
module Configs
  def self.recipes
    @recipes ||= OpenStruct.new(JSON.parse(File.read(File.join(GAME, 'Data/configs/crafting_config.json')), symbolize_names: true))
  end
end
load File.join(ROOT, '00000 Plugins/00002 Crafting/003_Recipes.rb')
load File.join(ROOT, '00017 ApricornTrees/00000 Config.rb')
module PFM
  def self.game_state; @state ||= OpenStruct.new(apricorns: ApricornTrees::COLORS.to_h { |c| [c, 0] }); end
  module ItemDescriptor
    def self.define_bag_use(*); end
  end
end
module GamePlay
  class BaseCleanUpdate
    class FrameBalanced
      def initialize; end
      def create_viewport; @viewport = LiteRGSS::Viewport.new($native_window, 0, 0, 320, 240); end
      def play_cursor_se; end
      def play_cancel_se; end
      def dispose; @viewport.dispose unless @viewport.disposed?; end
    end
  end
end
load File.join(ROOT, '00017 ApricornTrees/00007 ApricornBox.rb')
$options = OpenStruct.new(language: 'fr')
$native_window = LiteRGSS::DisplayWindow.new('ApricornBox - verification native', 320, 240, 2)
config = JSON.parse(File.read(File.join(GAME, 'Data/configs/texts_config.json'))).fetch('fonts')
config.fetch('ttfFiles').each do |font|
  Fonts.load_font(font['id'], File.join(GAME, 'Fonts', "#{font['name']}.ttf"))
  Fonts.set_default_size(font['id'], font['size'])
end
config.fetch('altSizes').each { |size| Fonts.set_default_size(size['id'], size['size']) }
colours = LiteRGSS::Image.new(File.join(GAME, 'graphics/windowskins/_colors.png'))
colours.width.times do |i|
  Fonts.define_outline_color(i, colours.get_pixel(i, 0))
  Fonts.define_fill_color(i, colours.get_pixel(i, 1))
  Fonts.define_shadow_color(i, colours.get_pixel(i, 2))
end
colours.dispose
$checks = 0
def check(condition, message)
  raise message unless condition
  $checks += 1
end

def normal(value); value.split.join(' '); end

def capture(scene, name)
  return unless (dir = ENV['APRICORN_UI_PREVIEW_DIR'])
  viewport = scene.instance_variable_get(:@viewport)
  viewport.sort_z
  bitmap = viewport.snap_to_bitmap
  bitmap.to_png_file(File.join(dir, name))
  bitmap.dispose
end

def check_hand_clearance(scene)
  occupied = {}
  scene.instance_variable_get(:@item_icons).each do |sprite|
    image = LiteRGSS::Image.new(sprite.bitmap.to_png, true)
    image.height.times do |y|
      image.width.times do |x|
        occupied[[sprite.x.to_i + x, sprite.y.to_i + y]] = true if image.get_pixel_alpha(x, y).positive?
      end
    end
    image.dispose
  end
  background = LiteRGSS::Image.new(File.join(GAME, 'graphics/interface/apricorn_box/apr_background.png'))
  (75..146).each do |y|
    (48..271).each do |x|
      pixel = background.get_pixel(x, y)
      occupied[[x, y + 48]] = true if [pixel.red, pixel.green, pixel.blue] == [248, 248, 248]
    end
  end
  background.dispose
  hand = LiteRGSS::Image.new(File.join(GAME, 'graphics/interface/apricorn_box/apr_hand.png'))
  GamePlay::ApricornBox::CENTRES.each do |cx, cy|
    2.times do |frame|
      collisions = []
      22.times do |y|
        20.times do |x|
          next if hand.get_pixel_alpha(x, y + frame * 22).zero?
          collisions << [x, y] if occupied[[cx - 25 + x, cy + 4 + y]]
        end
      end
      check(collisions.empty?, "Hand overlaps icon/badge at #{cx},#{cy}, frame #{frame}: #{collisions}")
    end
  end
  hand.dispose
end

scene = nil
begin
  %w[fr en es it].each do |language|
    recipe_widths = []
    $options.language = language
    scene = GamePlay::ApricornBox.new
    scene.send(:create_graphics)
    check_hand_clearance(scene) if language == 'fr'
    graphics = scene.instance_variable_get(:@graphics)
    amount = scene.instance_variable_get(:@quantity)
    puts "#{language}: 99+=#{amount.text_width('99+')}px; +=#{amount.text_width('+')}px; badge=#{scene.instance_variable_get(:@overflow_badge)}"
    check(amount.text_width('99+') > 14, '99+ unexpectedly fits; update badge expectations')
    check(amount.text_width('+') <= 14, 'Overflow marker does not fit')
    ApricornTrees::DISPLAY_ORDER.each_with_index do |color, i|
      PFM.game_state.apricorns[color] = [0, 1, 99, 247, 100, 10**18, 15][i]
      scene.instance_variable_set(:@index, i)
      scene.send(:refresh_selection)
      item = data_item(ApricornTrees::TYPES.fetch(color)[:item])
      recipe = scene.send(:ball_recipes, item.db_symbol).first
      ball = data_item(recipe[:result])
      ingredient_name = scene.instance_variable_get(:@ingredient_name)
      ball_name = scene.instance_variable_get(:@ball_name)
      arrow = scene.instance_variable_get(:@recipe_arrow)
      ingredient_icon = scene.instance_variable_get(:@ingredient_icon)
      recipe_width = scene.instance_variable_get(:@recipe_width)
      recipe_widths << [color, recipe_width]
      check(ingredient_name.text == "#{recipe[:ingredients][item.db_symbol]} #{item.name}", 'Ingredient quantity/name not dynamic')
      check(ball_name.text == "#{recipe[:quantity]} #{ball.name}", 'Output quantity/name not dynamic')
      check(ingredient_icon.bitmap.equal?(RPG::Cache.icon(item.icon)), 'Wrong recipe ingredient icon')
      check(arrow.text == '→', 'Missing recipe arrow')
      check(recipe_width <= 300, "Recipe overflow: #{language} #{color} #{recipe_width}px")
      check(ingredient_icon.x >= 10 && ball_name.x + ball_name.width <= 310, 'Recipe outside panel')
      check([ingredient_name.y, arrow.y, ball_name.y].uniq.size == 1, 'Recipe text baselines differ')
      check(ingredient_icon.y == 37 && scene.instance_variable_get(:@ball_icon).y == 37, 'Icon baselines differ')
      check(ingredient_icon.y + 32 <= 69, 'Recipe canvas overlaps Ball description')
      check([ingredient_name, arrow, ball_name].all? { |text| text.size == 13 }, 'Recipe glyph size changed')
      check(graphics.stack.none? { |object| object.is_a?(Text) && object.text.include?('Fabrication') }, 'Old heading remains')
      [[item.description, :@description_lines, 2], [ball.description, :@ball_description_lines, 3]].each do |description, ivar, count|
        lines = scene.instance_variable_get(ivar)
        check(lines.size == count, 'Line count changed')
        check(normal(lines.map(&:text).join(' ')) == normal(description), "Text lost: #{language} #{color} #{ivar}")
        lines.each { |text| check(text.text_width(text.text) <= 300, 'Description overflow') }
        check(lines.all? { |text| text.size == 13 }, 'Glyph size changed')
        check(lines.each_cons(2).all? { |a, b| b.y - a.y == 13 }, 'Line spacing changed')
      end
      check(amount.text == "×#{PFM.game_state.apricorns[color]}", 'Quantity lost')
      check(amount.text_width(amount.text) <= 150, 'Exact tested quantity does not fit')
      icon = scene.instance_variable_get(:@ball_icon)
      check(icon.bitmap.equal?(RPG::Cache.icon(ball.icon)), 'Wrong native Ball icon')
      apr_icon = scene.instance_variable_get(:@item_icons)[i]
      check(apr_icon.bitmap.equal?(RPG::Cache.icon(item.icon)), 'Wrong native Apricorn icon')
      check(icon.bitmap.width == 32, 'Wrong icon canvas')
      if language == 'fr'
        hand = scene.instance_variable_get(:@hand)
        2.times do |frame|
          hand.sy = frame
          capture(scene, "#{language}_#{color}_frame#{frame}.png")
        end
      end
    end
    puts "#{language} recipe widths (icons and gaps included): #{recipe_widths.inspect}"
    objects = graphics.stack.dup + scene.instance_variable_get(:@return_button).stack.dup
    textures = RPG::Cache.textures.values.dup
    scene.dispose
    check(objects.all?(&:disposed?), 'Native drawable survived disposal')
    check(textures.none?(&:disposed?), 'Shared texture disposed by scene')
    check(scene.instance_variable_get(:@viewport).disposed?, 'Viewport survived disposal')
    scene.dispose
    scene = nil
  end
  12.times do
    scene = GamePlay::ApricornBox.new
    scene.send(:create_graphics)
    graphics = scene.instance_variable_get(:@graphics)
    ids = graphics.stack.map(&:object_id)
    100.times do |i|
      scene.move_selection(%i[RIGHT DOWN LEFT UP][i % 4])
      scene.update_graphics
    end
    check(ids == graphics.stack.map(&:object_id), 'Refresh recreated drawables')
    objects = graphics.stack.dup + scene.instance_variable_get(:@return_button).stack.dup
    scene.dispose
    check(objects.all?(&:disposed?), 'Repeated open/close leaked drawables')
    scene = nil
  end
  puts "Native LiteRGSS: #{$checks} assertions passed; 4 languages, 7 fiches, 16 scene lifecycles."
rescue Exception => error
  warn "#{error.class}: #{error.message}\n#{error.backtrace.first(8).join("\n")}"
  scene&.dispose
  STDOUT.flush
  exit! 1
end
# The OS closes this test-only DisplayWindow on process exit. No game is booted.
RPG::Cache.textures.each_value(&:dispose)
STDOUT.flush
exit! 0
