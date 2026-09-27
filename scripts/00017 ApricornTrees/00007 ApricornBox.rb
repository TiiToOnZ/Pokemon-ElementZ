# frozen_string_literal: true

module GamePlay
  # Consultation only: no action here changes the inventory.
  class ApricornBox < BaseCleanUpdate::FrameBalanced
    attr_reader :index

    def initialize
      super
      @index = 0
    end

    def selected_color
      ApricornTrees::DISPLAY_ORDER[@index]
    end

    def move_selection(delta)
      @index = (@index + delta) % ApricornTrees::DISPLAY_ORDER.size
      play_cursor_se
      refresh_selection
    end

    def update_inputs
      if Input.trigger?(:B)
        play_cancel_se
        @running = false
      elsif Input.repeat?(:LEFT) || Input.repeat?(:UP)
        move_selection(-1)
      elsif Input.repeat?(:RIGHT) || Input.repeat?(:DOWN)
        move_selection(1)
      end
      true
    end

    def update_graphics
      @base_ui.update_background_animation
      true
    end

    def dispose
      @base_ui&.dispose
      [@heading, @collection, @detail].compact.each { |window| window.sprite_stack.dispose }
      super
    end

    private

    def create_graphics
      create_viewport
      @base_ui = UI::GenericBase.new(@viewport, [nil, nil, nil, ApricornTrees.text(:close)])
      @heading = UI::Window.new(@viewport, 4, 2, 312, 30)
      @heading.add_text(8, 4, 288, 18, ApricornTrees.text(:title), 1, color: 10)
      @collection = UI::Window.new(@viewport, 4, 35, 312, 67)
      @collection.load_cursor
      @collection.active = true
      @quantities = ApricornTrees::DISPLAY_ORDER.map.with_index do |color, i|
        icon = @collection.push(8 + i * 42, 2, nil, type: UI::ItemSprite)
        icon.data = ApricornTrees::TYPES.fetch(color)[:item]
        @collection.add_text(3 + i * 42, 35, 42, 18, "×#{PFM.game_state.apricorns[color]}", 1, color: 10)
      end
      @detail = UI::Window.new(@viewport, 4, 105, 312, 106)
      @icon = @detail.push(8, 4, nil, type: UI::ItemSprite)
      @name = @detail.add_text(48, 4, 244, 18, '', 0, color: 10)
      @quantity = @detail.add_text(48, 22, 244, 16, '', 0, color: 9)
      @description = @detail.add_text(8, 41, 288, 32, '', 0, color: 10)
      @detail.add_text(8, 78, 151, 16, ApricornTrees.text(:makes), 0, color: 9)
      @ball_icon = @detail.push(164, 68, nil, type: UI::ItemSprite)
      @ball_name = @detail.add_text(200, 78, 98, 16, '', 0, color: 10)
      add_disposable(@heading, @collection, @detail)
      refresh_selection
    end

    def refresh_selection
      data = ApricornTrees::TYPES.fetch(selected_color)
      @collection.cursor_rect.set(5 + @index * 42, 0, 38, 54)
      @icon.data = data[:item]
      @name.text = data_item(data[:item]).name
      @quantity.text = format(ApricornTrees.text(:quantity), PFM.game_state.apricorns[selected_color])
      @description.multiline_text = data_item(data[:item]).description
      @ball_icon.data = data[:ball]
      @ball_name.text = data_item(data[:ball]).name
    end
  end
end

PFM::ItemDescriptor.define_bag_use(:apricorn_box, true) do |_item, scene|
  scene.call_scene(GamePlay::ApricornBox)
  # Consultation has no consumption and needs no extra "used item" message.
  next :unused
end
