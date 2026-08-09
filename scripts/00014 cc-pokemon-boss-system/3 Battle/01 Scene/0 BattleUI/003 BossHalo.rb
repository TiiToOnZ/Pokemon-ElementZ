module BattleUI
  class PokemonSprite < ShaderedSprite
    module BossHaloPatch
      # Opacity of the halo sprite
      HALO_OPACITY = 120
      # Duration of a complete halo animation cycle in seconds
      HALO_CYCLE_DURATION = 2.0
      # Number of columns in the halo spritesheet
      HALO_NB_X = 8
      # Number of rows in the halo spritesheet
      HALO_NB_Y = 4
      # Zoom multiplier so the halo envelops the Pokemon sprite
      HALO_ZOOM_FACTOR = 1.0
      # Intensity of the glow/bloom effect on the halo
      HALO_GLOW_INTENSITY = 1.5

      Shader.register(:boss_halo_glow, 'graphics/shaders/boss_halo_glow.frag')
      Shader.register(:boss_halo_glow_3d, 'graphics/shaders/boss_halo_glow.frag', 'graphics/shaders/fake_3d.vert')

      # Create a new PokemonSprite
      # @param viewport [Viewport]
      # @param scene [Battle::Scene]
      def initialize(viewport, scene)
        @boss_halo_sprite = nil
        @boss_halo_animation = nil
        super
      end

      # Set the Pokemon
      # @param pokemon [PFM::PokemonBattler]
      def pokemon=(pokemon)
        dispose_boss_halo
        super
        create_boss_halo if pokemon&.boss? && pokemon.boss_halo
      end

      # Update the sprite
      def update
        super
        @boss_halo_animation&.update
        if @boss_halo_pending_3d
          scene.visual.sprites3D.append(@boss_halo_sprite)
          @boss_halo_pending_3d = false
        end
      end

      # Set the position of the sprite
      # @param x [Numeric]
      # @param y [Numeric]
      # @return [self]
      def set_position(x, y)
        super
        @boss_halo_sprite&.set_position(x, y)
        return self
      end

      # Set the x position of the sprite
      # @param x [Numeric]
      def x=(x)
        super
        @boss_halo_sprite&.x = x
      end

      # Set the y position of the sprite
      # @param y [Numeric]
      def y=(y)
        super
        @boss_halo_sprite&.y = y
      end

      # Set the opacity of the sprite
      # @param opacity [Integer]
      def opacity=(opacity)
        super
        @boss_halo_sprite&.opacity = [opacity, HALO_OPACITY].min
      end

      # Set the visibility of the sprite
      # @param visible [Boolean]
      def visible=(visible)
        super
        @boss_halo_sprite&.visible = visible
      end

      # Set the z position of the sprite
      # @param z [Numeric]
      def z=(z)
        super
        return unless Battle::BATTLE_CAMERA_3D && @boss_halo_sprite

        @boss_halo_sprite.shader.set_float_uniform('z', shader_z_position)
      end

      # Set the zoom of the sprite
      # @param zoom [Float]
      def zoom=(zoom)
        super
        @boss_halo_sprite&.zoom = zoom * HALO_ZOOM_FACTOR
      end

      # Dispose the sprite
      def dispose
        dispose_boss_halo
        super
      end

      private

      # Create the boss halo sprite and start its animation
      def create_boss_halo
        return unless pokemon&.boss_halo

        @boss_halo_sprite = SpriteSheet.new(viewport, HALO_NB_X, HALO_NB_Y)
        bitmap = RPG::Cache.interface("battle/boss/halo_#{pokemon.boss_halo}")
        @boss_halo_sprite.bitmap = bitmap
        @boss_halo_sprite.set_origin(@boss_halo_sprite.width / 2, @boss_halo_sprite.height)
        @boss_halo_sprite.set_position(x, y)
        @boss_halo_sprite.opacity = HALO_OPACITY
        @boss_halo_sprite.zoom = HALO_ZOOM_FACTOR
        @boss_halo_sprite.z = z + 1

        if Battle::BATTLE_CAMERA_3D
          @boss_halo_sprite.shader = Shader.create(:boss_halo_glow_3d)
          @boss_halo_sprite.shader.set_float_uniform('z', shader_z_position)
          @boss_halo_pending_3d = true
        else
          @boss_halo_sprite.shader = Shader.create(:boss_halo_glow)
        end
        @boss_halo_sprite.shader.set_float_uniform('resolution', [bitmap.width.to_f, bitmap.height.to_f])
        @boss_halo_sprite.shader.set_float_uniform('cellSize', [1.0 / HALO_NB_X, 1.0 / HALO_NB_Y])
        @boss_halo_sprite.shader.set_float_uniform('glowIntensity', HALO_GLOW_INTENSITY)

        ya = Yuki::Animation
        cells = (HALO_NB_X * HALO_NB_Y).times.map { |i| [i % HALO_NB_X, i / HALO_NB_X] }
        @boss_halo_animation = ya.timed_loop_animation(
          HALO_CYCLE_DURATION,
          [ya.sprite_sheet_animation(HALO_CYCLE_DURATION, @boss_halo_sprite, cells)]
        )
        @boss_halo_animation.start
      end

      # Dispose the boss halo sprite and stop its animation
      def dispose_boss_halo
        @boss_halo_animation = nil
        @boss_halo_sprite&.dispose
        @boss_halo_sprite = nil
      end
    end

    prepend BossHaloPatch
  end
end
