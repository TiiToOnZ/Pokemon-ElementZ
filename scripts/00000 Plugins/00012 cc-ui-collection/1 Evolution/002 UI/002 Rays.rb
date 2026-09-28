module UI
  module EvolveCinematic
    # Rays shot out of the evolving Pokemon during the main loop, each one thrown again once it faded out
    #
    # They never stop until the flash hides them, so each one loops on its own clock and this stack
    # updates the ones that started, the way the scrolling lines of the background do.
    class Rays < SpriteStack
      include Cinematic

      # Number of seconds a ray takes to fade out, after which it is thrown again
      RAY_LIFE = 1.6
      # Number of seconds between two rays coming out
      RAY_INTERVAL = 0.2
      # Zoom a ray reaches when it fades out
      RAY_ZOOM = 2.56

      # One of the rays shot out of the Pokemon, which grows as it fades, then starts over
      class Ray
        # Take over a ray sprite
        # @param source [SourceSprite] sprite state pushed in the stack
        def initialize(source)
          @source = source
        end

        # Show the ray at the given point of its life
        # @param value [Float] progression between 0 and 1
        def progression=(value)
          @source.zoom = RAY_ZOOM * value
          @source.opacity = 255 * (1 - value)
          @source.apply
        end
      end

      # Create the rays, none of them running before the main loop starts
      # @param viewport [Viewport]
      def initialize(viewport)
        super(viewport, 0, 0, default_cache: :interface)
        @running = []
        @rays = create_rays
      end

      # Show the rays and start their clocks, one more of them coming out every interval
      def start
        @rays.each_with_index do |(source, animation), index|
          source.visible = true
          @running << animation.start(RAY_INTERVAL * index)
        end
      end

      # Update the clocks that started, each ray looping on its own
      def update
        @running.each(&:update)
      end

      # Hide the rays, once the flash covers the screen, and stop their clocks
      def hide
        @rays.each { |(source, _animation)| source.visible = false }
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

      # Create the rays, each looping on its own once the main loop lets them out
      # @return [Array<Array>] sprite state and looping animation of each ray
      def create_rays
        ya = Yuki::Animation
        angles = Array.new(RAY_COUNT) { |index| (360 / RAY_COUNT) * index + 15 }
        return Array.new(RAY_COUNT) do
          source = source_sprite('ray')
          source.set_origin(0, source.height / 2)
          source.x = POKEMON_X
          source.y = POKEMON_Y
          source.angle = angles.delete_at(rand(angles.size))
          source.opacity = 0
          source.visible = false
          source.apply
          scalar = ya.scalar(RAY_LIFE, Ray.new(source), :progression=, 0, 1)
          next [source, ya.timed_loop_animation(RAY_LIFE, [scalar])]
        end
      end
    end
  end
end
