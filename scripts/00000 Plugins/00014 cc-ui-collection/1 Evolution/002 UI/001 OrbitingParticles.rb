module UI
  module EvolveCinematic
    # Particles drifting away from the evolving Pokemon, each one thrown again once it faded out
    #
    # They never stop until the flash hides them, so each one loops on its own clock and this stack
    # updates the ones that started, the way the scrolling lines of the background do.
    class OrbitingParticles < SpriteStack
      include Cinematic

      # Radius a particle is aimed at, in source pixels
      PARTICLE_RADIUS = 256
      # Number of seconds a particle takes to fade out, after which it is thrown again
      PARTICLE_LIFE = 1.6
      # Share of the way to its target a particle still has left when it fades out
      PARTICLE_REACH_REMAINDER = 0.53

      # One of the particles orbiting the Pokemon, thrown again at a new point once faded out
      class Particle
        include Cinematic

        # Take over a particle sprite
        # @param source [SourceSprite] sprite state pushed in the stack
        def initialize(source)
          @source = source
          @progression = 1
          aim
        end

        # Show the particle at the given point of its life, aiming it again when it starts over
        # @param value [Float] progression between 0 and 1
        def progression=(value)
          aim if value < @progression
          @progression = value
          left = PARTICLE_REACH_REMAINDER**value
          @source.x = @target_x + (POKEMON_X - @target_x) * left
          @source.y = @target_y + (POKEMON_Y - @target_y) * left
          @source.opacity = 255 * (1 - value)
          @source.apply
        end

        private

        # Aim the particle at a random point of the circle it drifts to
        def aim
          offset_x, offset_y = random_circle_offset(PARTICLE_RADIUS)
          @target_x = POKEMON_X + offset_x
          @target_y = POKEMON_Y + offset_y
        end
      end

      # Create the particles, none of them running before the glow lets them out
      # @param viewport [Viewport]
      def initialize(viewport)
        super(viewport, 0, 0, default_cache: :interface)
        @running = []
        @particles = create_particles
      end

      # Show the particles and start their clocks, spread over the cycle they share so they never
      # come out all at once
      def start
        @particles.each_with_index do |(source, animation), index|
          source.visible = true
          @running << animation.start(-PARTICLE_LIFE * index / PARTICLE_COUNT)
        end
      end

      # Update the clocks that started, each particle looping on its own
      def update
        @running.each(&:update)
      end

      # Hide the particles, once the flash covers the screen, and stop their clocks
      def hide
        @particles.each { |(source, _animation)| source.visible = false }
        @running.clear
      end

      private

      # Push a sprite in the stack and take over its source space state
      # @param image_name [String] name of the asset inside the interface cache
      # @return [SourceSprite]
      def source_sprite(image_name)
        sprite = add_sprite(0, 0, "#{IMAGE_PATH}#{image_name}")
        sprite.z = EFFECT_Z
        return SourceSprite.new(sprite)
      end

      # Create the particles, each looping on its own once the glow lets them out
      # @return [Array<Array>] sprite state and looping animation of each particle
      def create_particles
        ya = Yuki::Animation
        return Array.new(PARTICLE_COUNT) do
          source = source_sprite('shine_2')
          source.opacity = 0
          source.apply
          source.visible = false
          scalar = ya.scalar(PARTICLE_LIFE, Particle.new(source), :progression=, 0, 1)
          next [source, ya.timed_loop_animation(PARTICLE_LIFE, [scalar])]
        end
      end
    end
  end
end
