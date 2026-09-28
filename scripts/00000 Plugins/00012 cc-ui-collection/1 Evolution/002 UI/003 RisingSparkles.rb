module UI
  module EvolveCinematic
    # Sparkles rising over the screen once the evolution is done
    #
    # They belong to a phase of the sequence instead of running forever, so they are born when that
    # phase starts and the composition drives them all by one progression.
    class RisingSparkles < SpriteStack
      include Cinematic

      # z superiority of the sparkles
      SPARKLE_Z = 10
      # Opacity a sparkle would peak at, per unit of the speed it flares up at
      SPARKLE_PEAK_PER_SPEED = 64
      # Opacity a sparkle shrinks to nothing past
      SPARKLE_SHRINK_OPACITY = 128
      # Height a sparkle rises by over the phase, before its own speed divides it, in source pixels
      SPARKLE_RISE = 64
      # Assets a sparkle is picked from, by their number in the shine series
      SPARKLE_SHINES = [5, 2]
      # Distance a sparkle is born above the bottom of the screen at the lowest, in source pixels
      SPARKLE_BOTTOM_MARGIN = 64
      # Zooms a sparkle is picked from
      SPARKLE_ZOOMS = [0.2, 0.4, 0.5, 0.6, 0.8, 1.0]
      # Range the speed a sparkle flares up at is picked from
      SPARKLE_SPEEDS = 2..6

      # One of the sparkles rising over the screen once the evolution is done
      class Riser
        # Take over a sparkle sprite
        # @param source [SourceSprite] sprite state pushed in the stack
        # @param speed [Integer] how fast it flares up, and how little it rises
        def initialize(source, speed)
          @source = source
          @speed = speed
          @zoom = source.zoom
          @start_y = source.y
        end

        # Show the sparkle at the given point of the phase
        # @note The source shrinks a sparkle a little further on every step it shines past the
        #   threshold and never grows it back, so the shrinking latches instead of following the fade
        # @param value [Float] progression between 0 and 1
        def progression=(value)
          opacity = SPARKLE_PEAK_PER_SPEED * @speed * (1 - (value * 2 - 1).abs)
          @shrunk ||= opacity > SPARKLE_SHRINK_OPACITY
          @source.opacity = opacity
          @source.y = @start_y - SPARKLE_RISE * value / @speed
          @source.zoom = @shrunk ? 0 : @zoom
          @source.apply
        end
      end

      # Create the stack the sparkles are born in, once the phase they belong to starts
      # @param viewport [Viewport]
      def initialize(viewport)
        super(viewport, 0, 0, default_cache: :interface)
        @risers = []
      end

      # Create the sparkles rising over the screen
      def create_sparkles
        @risers = Array.new(SPARKLE_COUNT) do
          source = source_sprite("shine_#{SPARKLE_SHINES.sample}")
          source.x = rand(SOURCE_SCREEN_WIDTH + 1)
          source.y = SOURCE_SCREEN_HEIGHT / 2 + rand(SOURCE_SCREEN_HEIGHT / 2 - SPARKLE_BOTTOM_MARGIN)
          source.zoom = SPARKLE_ZOOMS.sample
          source.opacity = 0
          source.apply
          next Riser.new(source, rand(SPARKLE_SPEEDS))
        end
        # Sprites born after the scene was sorted go on top of the pile until the viewport sorts again
        @viewport.sort_z
      end

      # Show the rising sparkles at the given point of their phase
      # @param value [Float] progression between 0 and 1
      def animation_progression=(value)
        @risers.each { |riser| riser.progression = value }
      end

      private

      # Push a sprite in the stack and take over its source space state
      # @param image_name [String] name of the asset inside the interface cache
      # @return [SourceSprite]
      def source_sprite(image_name)
        sprite = add_sprite(0, 0, "#{IMAGE_PATH}#{image_name}")
        sprite.z = SPARKLE_Z
        return SourceSprite.new(sprite)
      end
    end
  end
end
