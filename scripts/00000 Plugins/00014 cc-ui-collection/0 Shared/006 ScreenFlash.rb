module UI
  module Cinematic
    # Veil of one plain color covering the whole screen, which the scenes flash on an impact
    #
    # The engine has no sprite for a plain color, so this one fills a texture of its own and disposes
    # it. It knows nothing of a source space: it always covers the screen the game runs at.
    class ScreenFlash < SpriteStack
      include Cinematic

      # Create the veil, invisible until an animation covers the screen with it
      # @param viewport [Viewport]
      # @param z [Integer] z superiority of the veil
      # @param color [Color] color it is filled with
      def initialize(viewport, z, color = Color.new(255, 255, 255))
        super(viewport, 0, 0)
        @texture = solid_texture(Graphics.width, Graphics.height, color)
        @sprite = add_sprite(0, 0, nil)
        @sprite.bitmap = @texture
        @sprite.z = z
        @sprite.opacity = 0
      end

      # Animation of the veil covering the screen, which is not started
      # @param duration [Float] number of seconds it takes to cover it
      # @return [Yuki::Animation::TimedAnimation]
      def create_cover_animation(duration)
        return Yuki::Animation.scalar(duration, self, :opacity=, 0, 255)
      end

      # Animation of the veil uncovering the screen, which is not started
      # @param duration [Float] number of seconds it takes to uncover it
      # @return [Yuki::Animation::TimedAnimation]
      def create_uncover_animation(duration)
        return Yuki::Animation.scalar(duration, self, :opacity=, 255, 0)
      end

      # Take the veil off the screen right away, with no animation, to put it back to a neutral state
      def clear
        self.opacity = 0
      end

      # Dispose the stack and the texture built for the veil, which comes from no cache
      def dispose
        super
        @texture.dispose unless @texture.disposed?
      end

      private

      # Show the veil more or less, from the bare screen to the color covering it whole
      # @note Private on purpose: the animations of this class drive it, and Yuki::Animation sends it
      # @param value [Numeric] opacity of the veil, between 0 and 255
      def opacity=(value)
        @sprite.opacity = value
      end
    end
  end
end
