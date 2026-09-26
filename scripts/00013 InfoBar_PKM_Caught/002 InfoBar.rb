module BattleUI
  class InfoBar < UI::SpriteStack
    # BattleTypes' existing SpritePatch calls this once during create_sprites.
    def create_type_sprite
      @battle_type_sprites = [
        add_sprite(0, 0, NO_INITIAL_IMAGE, type: UI::BattleType1Sprite),
        add_sprite(0, 0, NO_INITIAL_IMAGE, type: UI::BattleType2Sprite)
      ]
      @battle_type_sprites.each do |sprite|
        sprite.visible = false
        sprite.z = @background.z - 1
      end
      # LiteRGSS applies sprite z changes only when their viewport is sorted.
      @viewport.sort_z
    end

    module KnownBattleTypes
      TYPE_GAP = 4

      # Background and type textures must be refreshed before measuring them.
      def data=(pokemon)
        super
        layout_battle_types
        synchronize_battle_type_visibility
      end

      def visible=(value)
        super
        synchronize_battle_type_visibility
      end

      # SpriteStack#z= flattens every child's depth. Keep types behind the
      # native background, text and gauges after a change to the bar's z.
      def z=(value)
        super
        @battle_type_sprites&.each { |sprite| sprite.z = value - 1 }
        @viewport.sort_z
      end

      # SpriteStack#set_position delegates to move (including go_in/go_out).
      def move(delta_x, delta_y)
        super
        synchronize_battle_type_visibility
        return self
      end

      def x=(value)
        super
        synchronize_battle_type_visibility
      end

      # Native idle animations also move the bar through y=.
      def y=(value)
        super
        synchronize_battle_type_visibility
      end

      def dispose
        super
        @battle_type_sprites = nil
      end

      private

      def layout_battle_types
        return unless @battle_type_sprites

        types = @battle_type_sprites.select(&:type_displayable?)
        return if types.empty?

        row_width = types.sum(&:width) + TYPE_GAP * (types.size - 1)
        row_x = @background.x - @background.ox + (@background.width - row_width) / 2
        row_y = @background.y - @background.oy + (enemy? ? @background.height - 2 : -types.map(&:height).max)
        types.each do |sprite|
          sprite.set_position(row_x, row_y)
          row_x += sprite.width + TYPE_GAP
        end
      end

      def synchronize_battle_type_visibility
        return unless @battle_type_sprites

        bar_visible = battle_type_background_on_screen?
        @battle_type_sprites.each do |sprite|
          sprite.visible = bar_visible && sprite.type_displayable?
        end
      end

      # out? changes at the START of go_out, whereas visible can stay true
      # after it ends. Keep the row during motion, hide it at the viewport edge.
      def battle_type_background_on_screen?
        return false unless @pokemon && @background && @background.visible

        left = @background.x - @background.ox
        top = @background.y - @background.oy
        return left < @viewport.ox + @viewport.rect.width &&
               left + @background.width > @viewport.ox &&
               top < @viewport.oy + @viewport.rect.height &&
               top + @background.height > @viewport.oy
      end
    end

    prepend KnownBattleTypes
  end
end
