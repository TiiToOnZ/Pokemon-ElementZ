module UI
  module HatchCinematic
    # The ring and the sparkles the egg throws when it bursts open
    #
    # They are built at the moment of the burst, since the sparkles are aimed at a point drawn at
    # random, and they draw over the white the burst happens under. One progression drives the whole
    # thing, each sprite reading its state from it, on the model of UI::LandingImpact::DustParticles.
    class Burst < SpriteStack
      include Cinematic

      # z superiority of the ring and of the sparkles
      EFFECT_Z = 250
      # Smallest radius a sparkle is aimed at, in source pixels
      MIN_RADIUS = 96
      # Range of radius a sparkle picks over the smallest one, in source pixels
      RADIUS_RANGE = 64
      # Height a sparkle is aimed above the circle it picked its point on, in source pixels
      RISE = 32
      # Share of the way to its target a sparkle still has left when the burst ends
      REACH_REMAINDER = 0.037
      # Share of the burst the ring and the sparkles take to come out
      OUT_START = 0.25
      # Share of the burst a sprite takes to reach full opacity
      FADE_IN_END = 0.125
      # Share of the burst the ring lives for
      RING_LIFE = 0.375
      # Share of its life the ring takes to fade in, and takes again to fade out
      RING_FADE = 1 / 3.0
      # Share of the burst the sparkles start fading out at
      SPARKLE_FADE_OUT_START = 0.75
      # Zoom the ring gains over its life
      RING_GROWTH = 12
      # Zoom a sparkle loses while it fades away
      SPARKLE_SHRINK = 0.48
      # Number of steps of zoom a sparkle may be born short of its authored size
      SPARKLE_ZOOM_STEPS = 20
      # Zoom one of those steps stands for
      SPARKLE_ZOOM_STEP = 0.01
      # Height a sparkle sinks by while it fades away, in source pixels
      SPARKLE_DRIFT = 96
      # Color the ring is tinted with when it comes out
      RING_COLOR = [32 / 255.0, 92 / 255.0, 42 / 255.0]
      # Color the sparkles are tinted with when they come out
      SPARKLE_COLOR = [232 / 255.0, 92 / 255.0, 42 / 255.0]

      # One of the sparkles, which flies to the point it was aimed at, then sinks as it fades away
      class Sparkle
        # Aim a sparkle at a point of the circle it picked
        # @param source [SourceSprite] sprite state pushed in the stack
        # @param target_x [Numeric] where it flies to, in source pixels
        # @param target_y [Numeric] where it flies to, in source pixels
        def initialize(source, target_x, target_y)
          @source = source
          @start_x = source.x
          @start_y = source.y
          @target_x = target_x
          @target_y = target_y
          @zoom = source.zoom
        end

        # Show the sparkle at the given point of the burst
        # @param value [Float] progression between 0 and 1
        def progression=(value)
          sinking = ((value - OUT_START) / (1 - OUT_START)).clamp(0, 1)
          left = REACH_REMAINDER**value
          target_y = @target_y + SPARKLE_DRIFT * sinking
          @source.x = target_x_at(left)
          @source.y = target_y + (@start_y - target_y) * left
          @source.zoom = @zoom - SPARKLE_SHRINK * sinking
          @source.opacity = 255 * (value / FADE_IN_END).clamp(0, 1) * fade_out_at(value)
          @source.color_alpha = 255 * (1 - (value / OUT_START).clamp(0, 1))
          @source.apply
        end

        private

        def target_x_at(left)
          return @target_x + (@start_x - @target_x) * left
        end

        # Get the share of its opacity a sparkle keeps, which it only starts losing near the end
        # @param value [Float] progression between 0 and 1
        # @return [Float]
        def fade_out_at(value)
          return 1 if value <= SPARKLE_FADE_OUT_START

          return 1 - (value - SPARKLE_FADE_OUT_START) / (1 - SPARKLE_FADE_OUT_START)
        end
      end

      # Create the ring and the sparkles, all at the middle of the screen, where the egg burst open
      # @param viewport [Viewport]
      def initialize(viewport)
        super(viewport, 0, 0, default_cache: :interface)
        create_ring
        create_sparkles
        self.animation_progression = 0
        # Sprites born after the scene was sorted go on top of the pile until the viewport sorts again
        @viewport.sort_z
      end

      # Show the burst at the given point of its life
      # @param value [Float] progression between 0 and 1
      def animation_progression=(value)
        @sparkles.each { |sparkle| sparkle.progression = value }
        place_ring(value)
      end

      private

      # Show the ring, which grows and fades out well before the sparkles do
      # @param value [Float] progression between 0 and 1
      def place_ring(value)
        life = (value / RING_LIFE).clamp(0, 1)
        @ring.zoom = 1 + RING_GROWTH * life
        @ring.opacity = 255 * ring_opacity_at(life)
        @ring.color_alpha = 255 * (1 - (value / OUT_START).clamp(0, 1))
        @ring.apply
      end

      # Get the share of its opacity the ring shows, a ramp up, a plateau and a ramp down
      # @param life [Float] progression through the life of the ring, between 0 and 1
      # @return [Float]
      def ring_opacity_at(life)
        return life / RING_FADE if life < RING_FADE
        return 1 if life < 1 - RING_FADE

        return (1 - life) / RING_FADE
      end

      def create_ring
        @ring = source_sprite('ring')
        @ring.color = RING_COLOR
      end

      # Create the sparkles, each aimed at a point of its own circle, a bit above it
      def create_sparkles
        @sparkles = Array.new(SPARKLE_COUNT) do
          source = source_sprite('sparkle')
          source.color = SPARKLE_COLOR
          source.zoom = 1 - rand(SPARKLE_ZOOM_STEPS) * SPARKLE_ZOOM_STEP
          radius = MIN_RADIUS + rand(RADIUS_RANGE)
          offset_x, offset_y = random_circle_offset(radius)
          next Sparkle.new(source, POKEMON_X + offset_x, POKEMON_Y + offset_y - RISE)
        end
      end

      # Push a sprite in the stack, where the egg burst open, and take over its source space state
      # @param image_name [String] name of the asset inside the interface cache
      # @return [SourceSprite]
      def source_sprite(image_name)
        sprite = add_sprite(0, 0, "#{IMAGE_PATH}#{image_name}", type: Sprite::WithColor)
        sprite.z = EFFECT_Z
        source = SourceSprite.new(sprite)
        source.x = POKEMON_X
        source.y = POKEMON_Y
        source.opacity = 0
        return source
      end
    end
  end
end
