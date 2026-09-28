# frozen_string_literal: true

module GamePlay
  # Read-only collection. The scene owns drawables, never cached textures.
  class ApricornBox < BaseCleanUpdate::FrameBalanced
    BACKGROUND = 'apricorn_box/apr_background'
    HAND = 'apricorn_box/apr_hand'
    CENTRES = [[78, 143], [128, 143], [178, 143], [228, 143],
               [103, 178], [153, 178], [203, 178]].map(&:freeze).freeze
    NEIGHBOURS = {
      LEFT: [0, 0, 1, 2, 4, 4, 5], RIGHT: [1, 2, 3, 3, 5, 6, 6],
      UP: [0, 1, 2, 3, 0, 1, 3], DOWN: [4, 5, 5, 6, 4, 5, 6]
    }.transform_values(&:freeze).freeze
    HAND_FRAME_DURATION = 0.225
    # UI-only vocabulary; all object text comes from Studio::Item.
    LABELS = {
      fr: {missing: 'Aucune recette de Ball.', ambiguous: 'Plusieurs recettes de Balls.', close: 'Retour'},
      en: {missing: 'No Ball recipe.', ambiguous: 'Multiple Ball recipes.', close: 'Back'},
      es: {missing: 'No hay receta de Ball.', ambiguous: 'Varias recetas de Balls.', close: 'Volver'},
      it: {missing: 'Nessuna ricetta di Ball.', ambiguous: 'Più ricette di Ball.', close: 'Indietro'}
    }.transform_values(&:freeze).freeze

    attr_reader :index

    def initialize
      super
      @index = 0
    end

    def selected_color
      ApricornTrees::DISPLAY_ORDER[@index]
    end

    def move_selection(direction)
      next_index = NEIGHBOURS.fetch(direction)[@index]
      return if next_index == @index
      @index = next_index
      play_cursor_se
      refresh_selection
    end

    def update_inputs
      if Input.trigger?(:B)
        play_cancel_se
        @running = false
      elsif (direction = NEIGHBOURS.keys.find { |key| Input.repeat?(key) })
        move_selection(direction)
      end
      true
    end

    def update_graphics
      @hand.sy = ((ApricornTrees.monotonic - @hand_started_at) / HAND_FRAME_DURATION).floor % 2
      true
    end

    def dispose
      return if @graphics_disposed
      @graphics_disposed = true
      @return_button&.dispose
      @graphics&.dispose
      super
    end

    private

    def label(key)
      (LABELS[$options&.language&.to_sym] || LABELS[:en]).fetch(key)
    end

    def create_graphics
      create_viewport
      @graphics = UI::SpriteStack.new(@viewport)
      create_background
      create_collection
      create_details
      @hand = @graphics.push(0, 0, HAND, 1, 2, type: SpriteSheet)
      @hand_started_at = ApricornTrees.monotonic
      @return_button = UI::GenericBase::ControlButton.new(@viewport, 3, :B)
      @return_button.text = label(:close)
      refresh_selection
    end

    def create_background
      @graphics.push(0, 0, BACKGROUND)
      # The 48px offset also preserves the phase of the blue stripe pattern.
      @graphics.push(48, 112, BACKGROUND, rect: [48, 64, 224, 112])
      # Nine pieces from the original 236x58 frame. Corners stay at 1:1;
      # only a one-pixel flat strip/centre is extended, never outline thickness.
      columns = [[42, 7, 4, 7], [49, 1, 11, 298], [271, 7, 309, 7]]
      rows = [[3, 7, 0, 7], [10, 1, 7, 98], [54, 7, 105, 7]]
      rows.each do |sy, sh, y, height|
        columns.each do |sx, sw, x, width|
          sprite = @graphics.push(x, y, BACKGROUND, rect: [sx, sy, sw, sh])
          sprite.zoom_x = width / sw
          sprite.zoom_y = height / sh
        end
      end
    end

    def text(x, y, width, value = '', align = 0, color: 0)
      @graphics.add_text(x, y, width, 13, value, align, color: color, sizeid: 3)
    end

    def create_collection
      @item_icons = []
      @quantities = ApricornTrees::DISPLAY_ORDER.map.with_index do |color, i|
        cx, cy = CENTRES[i]
        icon = @graphics.push(cx - 15, cy - 15, nil, type: UI::ItemSprite)
        icon.data = ApricornTrees::TYPES.fetch(color)[:item]
        @item_icons << icon
        # Painted circles are 18x18; reserve their central 14 pixels.
        text(cx + 14, cy - 1, 14, '', 1)
      end
      @overflow_badge = @quantities.first.text_width('99+') <= 14 ? '99+' : '+'
      text(114, 202, 92, data_item(:apricorn_box).name, 1, color: 9)
    end

    def create_details
      @name = text(10, 4, 150)
      @quantity = text(160, 4, 150, '', 2)
      @description_lines = Array.new(2) { |i| text(10, 17 + i * 13, 300) }
      @ingredient_icon = @graphics.push(0, 37, nil, type: UI::ItemSprite)
      @ingredient_name = text(0, 45, 300)
      @recipe_arrow = text(0, 45, 16)
      @ball_icon = @graphics.push(0, 37, nil, type: UI::ItemSprite)
      @ball_name = text(0, 45, 300)
      @ball_description_lines = Array.new(3) { |i| text(10, 69 + i * 13, 300) }
    end

    def refresh_selection
      ApricornTrees::DISPLAY_ORDER.each_with_index do |color, i|
        amount = PFM.game_state.apricorns[color]
        @quantities[i].text = amount <= 99 ? amount.to_s : @overflow_badge
      end
      item_symbol = ApricornTrees::TYPES.fetch(selected_color)[:item]
      item = data_item(item_symbol)
      cx, cy = CENTRES[@index]
      @hand.set_position(cx - 1, cy - 25)
      @name.text = item.name
      @quantity.text = "×#{PFM.game_state.apricorns[selected_color]}"
      set_description(@description_lines, item.description)
      refresh_recipe(item_symbol)
    end

    # Never query availability/unlocks: Recipes.data is configuration only.
    def ball_recipes(item_symbol)
      CraftSystem::Recipes.data.values.select do |recipe|
        ingredients = recipe[:ingredients]
        next false unless ingredients.is_a?(Hash) && ingredients.key?(item_symbol)
        amount = ingredients[item_symbol]
        next false unless amount.is_a?(Integer) && amount.positive?
        next false unless recipe[:quantity].is_a?(Integer) && recipe[:quantity].positive?
        result = recipe[:result]
        next false unless result.is_a?(Symbol) || result.is_a?(Integer)
        data_item(result).is_a?(Studio::BallItem)
      end
    end

    def refresh_recipe(item_symbol)
      recipes = ball_recipes(item_symbol)
      @ball_icon.visible = recipes.size == 1
      @ingredient_icon.visible = recipes.size == 1
      unless recipes.size == 1
        @ingredient_name.text = @recipe_arrow.text = ''
        @ball_name.x = 10
        @ball_name.width = 300
        @ball_name.text = label(recipes.empty? ? :missing : :ambiguous)
        set_description(@ball_description_lines, '')
        return
      end
      recipe = recipes.first
      item = data_item(item_symbol)
      ball = data_item(recipe[:result])
      @ingredient_icon.data = item_symbol
      @ingredient_name.text = "#{recipe[:ingredients].fetch(item_symbol)} #{item.name}"
      @recipe_arrow.text = '→'
      @ball_icon.data = recipe[:result]
      @ball_name.text = "#{recipe[:quantity]} #{ball.name}"
      position_recipe
      set_description(@ball_description_lines, ball.description)
    end

    def position_recipe
      left_width = @ingredient_name.text_width(@ingredient_name.text)
      arrow_width = @recipe_arrow.text_width(@recipe_arrow.text)
      right_width = @ball_name.text_width(@ball_name.text)
      # Two native 32px canvases and 8px on each side of the arrow.
      @recipe_width = 64 + left_width + arrow_width + right_width + 16
      x = 10 + [0, (300 - @recipe_width) / 2].max
      @ingredient_icon.set_position(x, 37)
      @ingredient_name.x = x + 32
      @ingredient_name.width = left_width
      @recipe_arrow.x = @ingredient_name.x + left_width + 8
      @recipe_arrow.width = arrow_width
      @ball_icon.set_position(@recipe_arrow.x + arrow_width + 8, 37)
      @ball_name.x = @ball_icon.x + 32
      @ball_name.width = right_width
    end

    def set_description(texts, description)
      # Use native wrapping, but position separate lines at the approved 13px step.
      texts.first.multiline_text = description
      lines = texts.first.text.split("\n")
      texts.each_with_index { |line, i| line.text = lines[i].to_s.rstrip }
    end
  end
end

PFM::ItemDescriptor.define_bag_use(:apricorn_box, true) do |_item, scene|
  scene.call_scene(GamePlay::ApricornBox)
  next :unused
end
