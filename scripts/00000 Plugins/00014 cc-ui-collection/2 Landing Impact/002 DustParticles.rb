module UI
  module LandingImpact
    # Cloud of dust a heavy Pokemon raises when it lands, transcribed from EBDustParticle
    #
    # Each particle is randomized once, in its constructor, then the whole cloud is driven by a
    # single progression, on the model of UI::ShinyAnimation.
    class DustParticles
      # Create the cloud of a Pokemon that just landed
      # @param viewport [Viewport]
      # @param sprite [BattleUI::PokemonSprite3D] sprite of the Pokemon raising the dust
      # @param scene [Battle::Scene]
      def initialize(viewport, sprite, scene)
        count = LandingImpact.dust_count(sprite.bitmap.width)
        @particles = Array.new(count) { Particle.new(viewport, sprite, scene) }
        Graphics.sort_z
      end

      # Move the whole cloud to a point of its animation
      # @param progression [Float] between 0 and 1
      def animation_progression=(progression)
        @particles.each { |particle| particle.progression = progression }
      end

      # Dispose every particle of the cloud
      def dispose
        @particles.each(&:dispose)
      end

      # One dust particle, randomized once and then driven by the progression of the cloud
      class Particle < Sprite
        # Create a particle around the feet of a Pokemon
        # @param viewport [Viewport]
        # @param sprite [BattleUI::PokemonSprite3D]
        # @param scene [Battle::Scene]
        def initialize(viewport, sprite, scene)
          super(viewport)
          self.bitmap = RPG::Cache.animation(DUST_IMAGE)
          set_origin(width / 2, height / 2)
          self.opacity = 0
          randomize_around(sprite)
          apply_3d_settings(sprite, scene)
        end

        # Move the particle to a point of the animation
        # @param progression [Float] between 0 and 1
        def progression=(progression)
          self.x = @origin_x + @direction * DUST_DRIFT_PER_STEP * DUST_STEPS * progression
          self.angle = @origin_angle + @direction * DUST_ROTATION_PER_STEP * DUST_STEPS * progression
          self.opacity = opacity_at(progression * DUST_STEPS)
        end

        private

        # Scatter the particle around the feet of a Pokemon, once and for all
        #
        # What never moves afterwards is set on the sprite, what the progression drives is kept aside.
        # @param sprite [BattleUI::PokemonSprite3D]
        def randomize_around(sprite)
          factor = sprite.zoom_x
          half_width = LandingImpact.dust_spread(sprite.bitmap.width) * factor
          half_height = DUST_VERTICAL_SPREAD / 2.0 * factor
          y_offset = rand(-half_height..half_height)
          zoom = DUST_ZOOMS.sample * factor

          @origin_x = sprite.x + rand(-half_width..half_width)
          @origin_angle = rand(360)
          # Each particle flees the side it already stands on, and turns the way it flees
          @direction = @origin_x >= sprite.x ? 1 : -1
          self.y = sprite.y + y_offset
          # A particle above the feet passes behind the Pokemon, one below passes in front of it
          self.z = sprite.z + (y_offset.negative? ? -1 : 1)
          self.zoom_x = zoom
          self.zoom_y = zoom
        end

        # Apply the 3D battle camera settings, which this animation only ever runs under
        # @param sprite [BattleUI::PokemonSprite3D]
        # @param scene [Battle::Scene]
        def apply_3d_settings(sprite, scene)
          self.shader = Shader.create(:fake_3d)
          shader.set_float_uniform('z', sprite.shader_z_position)
          scene.visual.sprites3D << self
        end

        # Get the opacity the particle has on a step, a ramp up, a plateau and a ramp down
        # @param frame [Float]
        # @return [Float]
        def opacity_at(frame)
          return (frame * DUST_OPACITY_STEP).clamp(0, 255) if frame < DUST_FADE_OUT_FRAME

          return ((DUST_STEPS - frame) * DUST_OPACITY_STEP).clamp(0, 255)
        end
      end
    end
  end
end
