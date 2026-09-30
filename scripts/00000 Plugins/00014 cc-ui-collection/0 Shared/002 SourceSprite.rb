module UI
  module Cinematic
    # Source space state of a sprite owned by a SpriteStack
    #
    # The source animations mutate the sprite properties in place (`sprite.zoom_x += 0.04`), which
    # PSDK cannot do since `Sprite#zoom` is write only. Holding the state here lets the animation
    # steps stay verbatim and puts the source to screen conversion in a single place. The sprite
    # itself belongs to the stack that created it, which disposes it.
    class SourceSprite
      include Cinematic

      # @return [Float] horizontal position, in source pixels
      attr_accessor :x
      # @return [Float] vertical position, in source pixels
      attr_accessor :y
      # @return [Float] zoom in source scale, where 1 shows the asset at its authored size
      attr_accessor :zoom
      # @return [Numeric] rotation of the sprite in degree
      attr_accessor :angle
      # @return [Array<Float>] color blended over the sprite, in the normalized form set_color takes
      attr_accessor :color
      # @return [Numeric] opacity of the sprite
      attr_reader :opacity
      # @return [Numeric] amount of the color blended over the sprite, standing for its source alpha
      attr_reader :color_alpha

      # Take the source space state of a sprite
      # @param sprite [Sprite] sprite pushed in the stack
      def initialize(sprite)
        @sprite = sprite
        @colorable = sprite.is_a?(Sprite::WithColor)
        @sprite.set_origin(@sprite.width / 2, @sprite.height / 2)
        @x = 0
        @y = 0
        @zoom = 1
        @angle = 0
        @opacity = 255
        @color = [1, 1, 1]
        @color_alpha = 0
      end

      # Get the height of the asset
      # @return [Integer]
      def height
        return @sprite.height
      end

      # Set the opacity, clamped the way RGSS clamps it so the source respawn tests still hold
      # @param value [Numeric]
      def opacity=(value)
        @opacity = value.clamp(0, 255)
      end

      # Set the amount of the color blended over the sprite
      # @param value [Numeric] between 0 and 255
      def color_alpha=(value)
        @color_alpha = value.clamp(0, 255)
      end

      # Set the visibility of the sprite
      # @param value [Boolean]
      def visible=(value)
        @sprite.visible = value
      end

      # Set the origin of the sprite, in asset pixels
      # @param ox [Numeric]
      # @param oy [Numeric]
      def set_origin(ox, oy)
        @sprite.set_origin(ox, oy)
      end

      # Push the source space state to the screen
      def apply
        factor = scale
        @sprite.set_position(@x * factor, @y * factor)
        @sprite.zoom = @zoom * factor
        @sprite.angle = @angle
        @sprite.opacity = @opacity
        @sprite.set_color([*@color, @color_alpha / 255.0]) if @colorable
      end
    end
  end
end
