# frozen_string_literal: true

module ApricornTrees
  module TreeEvent
    attr_accessor :apricorn_animating
    attr_reader :apricorn_color

    # Native active page, retained by reference only for the current interaction.
    def apricorn_page
      @page
    end

    def refresh
      super
      @apricorn_color = ApricornTrees.color_from_page(@page)
      return unless apricorn_color && activated? && !erased
      @tile_id = 0
      graphic = TYPES.fetch(apricorn_color)[:graphic]
      set_appearance(graphic) unless @character_name == graphic
      @move_type = 0
      @walk_anime = @step_anime = false
      @direction_fix = true
      @through = false
      @trigger = 0
      @interpreter = nil
      # Runtime-only event list. No RXDATA or RPG::Event page is modified.
      script = RPG::EventCommand.new
      script.code, script.indent, script.parameters = 355, 0, ['apricorn_tree']
      terminal = RPG::EventCommand.new
      terminal.code, terminal.indent, terminal.parameters = 0, 0, []
      @list = [script, terminal]
      ApricornTree.new(self).refresh unless @apricorn_animating
    end

    def apricorn_set_frame(direction, pattern)
      @direction = @original_direction = direction
      @pattern = @original_pattern = pattern
      @prelock_direction = 0
    end

    private

    def update_pattern
      return if apricorn_color
      super
    end
  end
end
Game_Event.prepend(ApricornTrees::TreeEvent)
