module UI
  # Coordinate space of the scenes transcribed from an outside animation
  #
  # Those animations are written in a space of their own, 512x384. This module holds that space and
  # its conversion to the screen the game runs at, a project setting rather than a given, so the
  # scenes hold together at any resolution.
  #
  # @note Including this module into an enclosing module does not expose its constants to the classes
  #   nested in it, since a constant lookup only walks the ancestors of the innermost one. Every class
  #   reaching for something here includes it itself.
  module Cinematic
    # Width of the space the coordinates are written in
    SOURCE_SCREEN_WIDTH = 512
    # Height of the space the coordinates are written in
    SOURCE_SCREEN_HEIGHT = 384
    # Horizontal position of the Pokemon, in source pixels
    POKEMON_X = SOURCE_SCREEN_WIDTH / 2
    # Vertical position of the Pokemon, in source pixels
    POKEMON_Y = SOURCE_SCREEN_HEIGHT / 2
    # Factor a sequence runs at while the player holds the fast forward key
    # @note Not a coordinate: it waits for a scene module the cinematic scenes would share
    FAST_FORWARD_FACTOR = 3

    module_function

    # Get the factor converting a source coordinate to a screen coordinate
    # @return [Float]
    def scale
      return Graphics.width / SOURCE_SCREEN_WIDTH.to_f
    end

    # Build a texture filled with one plain color, which comes from no cache, so its caller disposes it
    # @param width [Integer] width of the texture, in screen pixels
    # @param height [Integer] height of the texture, in screen pixels
    # @param color [Color] color it is filled with
    # @return [Texture]
    def solid_texture(width, height, color)
      texture = Texture.new(width, height)
      image = Image.new(width, height)
      image.fill_rect(0, 0, width, height, color)
      image.copy_to_bitmap(texture)
      image.dispose
      return texture
    end

    # Get a random point of the circle of the given radius, relative to its center
    # @note The source helper offsets both coordinates by the radius and every call site subtracts it back
    # @param radius [Integer]
    # @return [Array<Float>]
    def random_circle_offset(radius)
      angle = rand(360) * Math::PI / 180
      return radius * Math.cos(angle), radius * Math.sin(angle)
    end
  end
end
