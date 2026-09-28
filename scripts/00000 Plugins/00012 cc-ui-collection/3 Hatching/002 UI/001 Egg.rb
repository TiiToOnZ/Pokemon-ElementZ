module UI
  module HatchCinematic
    # The egg of the scene, the cracks that open on it and the moves it makes
    #
    # The cracks are a strip of square frames drawn on the very canvas of the egg battler, so both
    # sprites take the same origin and the same position and the cracks land where they were
    # authored to. The egg sprite itself belongs to the scene, which disposes it.
    class Egg
      include Cinematic

      # Number of crack stages on the strip, the first one being blank
      STAGE_COUNT = 5

      # Number of seconds the egg takes to stretch up before it hops
      STRETCH_DURATION = 0.075
      # Number of seconds the hop of the egg lasts
      HOP_DURATION = 0.15
      # Number of seconds the egg takes to squash on landing, and as long again to take its shape back
      SQUASH_DURATION = 0.075
      # Zoom the egg stretches to before it hops
      STRETCH_ZOOM = 1.12
      # Zoom the egg squashes to when it lands
      SQUASH_ZOOM = 0.88
      # Height the egg reaches at the top of its hop, in source pixels
      HOP_HEIGHT = -18
      # Height the egg rises by as it takes its shape back, in source pixels
      RECOVER_HEIGHT = -6

      # Take over the egg sprite and the strip of cracks laid on it
      # @param sprite [Sprite::WithColor] egg sprite of the scene
      # @param cracks [Sprite] sprite pushed in the stack, showing one frame of the strip
      def initialize(sprite, cracks)
        @sprite = sprite
        @cracks = cracks
        @base_x = sprite.x
        @base_y = sprite.y
        @frame_width = @cracks.height
        @cracks.set_origin(@frame_width / 2, @cracks.height)
        @x = 0
        @y = 0
        @zoom_y = 1
        @stage = 0
        @visible = true
        refresh_cracks
        apply
      end

      # Set the visibility of the egg and of its cracks
      # @param value [Boolean]
      def visible=(value)
        @visible = value
        @sprite.visible = value
        refresh_cracks
      end

      # Open the egg one crack further, the strip running out once the egg has burst open
      def crack
        @stage += 1
        refresh_cracks
      end

      # Animation of one bounce: the egg stretches, hops, squashes on landing and settles back
      # @return [Yuki::Animation::TimedAnimation]
      def create_bounce_animation
        ya = Yuki::Animation
        return ya.player(
          ya.scalar(STRETCH_DURATION, self, :zoom_y=, 1, STRETCH_ZOOM),
          ya.scalar(HOP_DURATION, self, :y=, 0, HOP_HEIGHT, distortion: :SQUARE010_DISTORTION),
          ya.scalar(SQUASH_DURATION, self, :zoom_y=, STRETCH_ZOOM, SQUASH_ZOOM),
          ya.parallel(
            ya.scalar(SQUASH_DURATION, self, :zoom_y=, SQUASH_ZOOM, 1),
            ya.scalar(SQUASH_DURATION, self, :y=, 0, RECOVER_HEIGHT)
          ),
          ya.scalar(STRETCH_DURATION, self, :y=, RECOVER_HEIGHT, 0)
        )
      end

      # Animation of one series of shakes, the egg swinging aside and back over and over
      # @param reach [Numeric] offset the egg swings to, in source pixels
      # @param swings [Integer] number of swings the series makes
      # @param swing_duration [Float] number of seconds one swing lasts
      # @return [Yuki::Animation::TimedAnimation]
      def create_swings_animation(reach, swings, swing_duration)
        ya = Yuki::Animation
        steps = Array.new(swings) do
          next ya.scalar(swing_duration, self, :x=, 0, reach, distortion: :SQUARE010_DISTORTION)
        end
        return ya.player(*steps)
      end

      private

      # Set the horizontal offset from where the egg rests, in source pixels
      # @param value [Numeric]
      def x=(value)
        @x = value
        apply
      end

      # Set the vertical offset from where the egg rests, in source pixels
      # @param value [Numeric]
      def y=(value)
        @y = value
        apply
      end

      # Set the vertical squash of the egg, where 1 leaves it at its size
      # @param value [Numeric]
      def zoom_y=(value)
        @zoom_y = value
        apply
      end

      # Push the source space state to the screen
      def apply
        factor = scale
        x = @base_x + @x * factor
        y = @base_y + @y * factor
        [@sprite, @cracks].each do |sprite|
          sprite.set_position(x, y)
          sprite.zoom_y = @zoom_y
        end
      end

      def refresh_cracks
        @cracks.visible = @visible && @stage < STAGE_COUNT
        @cracks.src_rect.set(@stage * @frame_width, 0, @frame_width, @cracks.height) if @cracks.visible
      end
    end
  end
end
