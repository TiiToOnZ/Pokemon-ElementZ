module UI
  module Cinematic
    # Background the cinematic scenes share: a backdrop, six lines scrolling upward and an overlay,
    # framed by the two black bars that uncover then leave the screen
    #
    # Each scene owns its own images, so it hands the folder they live in. Those images are stretched
    # to the screen from their own size, so replacing one at any size is enough.
    class Background < SpriteStack
      include Cinematic

      # Number of seconds the black bars take to uncover the screen
      BARS_DURATION = 0.4
      # Number of scrolling lines in the background
      LINE_COUNT = 6
      # Number of seconds a line takes to cross the whole screen
      LINE_CYCLE_DURATION = 4.8
      # Offset the bars are fully off the screen at, in source pixels
      BARS_OPEN_OFFSET = SOURCE_SCREEN_HEIGHT / 2
      # z superiority of the backdrop
      BACKDROP_Z = 0
      # z superiority of the scrolling lines
      LINE_Z = 1
      # z superiority of the overlay
      OVERLAY_Z = 5
      # z superiority of the black bars
      BAR_Z = 200

      # One of the lines scrolling through the background, from the bottom of the screen up to its top
      class Line
        # Take over a line sprite
        # @param sprite [Sprite::WithColor] sprite pushed in the stack
        # @param factor [Float] factor converting a source coordinate to a screen coordinate
        def initialize(sprite, factor)
          @sprite = sprite
          @factor = factor
          @fit = Graphics.width / sprite.width.to_f
          @sprite.set_origin(sprite.width / 2, 0)
          @sprite.x = (SOURCE_SCREEN_WIDTH / 2) * factor
          @sprite.zoom_x = @fit
          @sprite.z = LINE_Z
        end

        # Place the line at the given height: the lower it is, the whiter and the taller it gets,
        # and it turns over once past the middle of the screen
        # @param value [Numeric] height in source pixels
        def y=(value)
          depth = (value - SOURCE_SCREEN_HEIGHT / 2.0) / (SOURCE_SCREEN_HEIGHT / 2.0)
          @sprite.set_color([1, 1, 1, value / SOURCE_SCREEN_HEIGHT.to_f])
          @sprite.angle = depth.negative? ? 180 : 0
          @sprite.zoom_y = depth.abs * @fit
          @sprite.y = value * @factor
        end
      end

      # Create the background
      # @param viewport [Viewport]
      # @param image_path [String] prefix of the images of the scene inside the interface cache
      # @param backdrop_name [String, nil] backdrop of the scene, when it is not the one of that prefix
      def initialize(viewport, image_path, backdrop_name = nil)
        super(viewport, 0, 0, default_cache: :interface)
        @image_path = image_path
        @backdrop_name = backdrop_name || "#{image_path}background"
        @factor = scale
        create_backdrop
        create_lines
        create_overlay
        create_bars
      end

      # Update the sprites of the stack and the lines, which never stop scrolling, not even while a
      # message shows
      def update
        super
        @line_animations.each(&:update)
      end

      # Animation of the bars uncovering the screen, from the closed screen the scene opens on
      # @return [Yuki::Animation::TimedAnimation]
      def create_opening_animation
        return Yuki::Animation.scalar(BARS_DURATION, self, :bars_offset=, 0, BARS_OPEN_OFFSET)
      end

      # Animation of the bars closing back to the offset a phase of the scene is framed by
      # @param duration [Float] number of seconds they take to close
      # @param offset [Numeric] offset they close to, in source pixels
      # @return [Yuki::Animation::TimedAnimation]
      def create_closing_animation(duration, offset)
        return Yuki::Animation.scalar(duration, self, :bars_offset=, BARS_OPEN_OFFSET, offset)
      end

      # Animation of the bars leaving the screen for good
      # @param duration [Float] number of seconds they take to leave
      # @param from [Numeric] offset they leave from, in source pixels
      # @return [Yuki::Animation::TimedAnimation]
      def create_leaving_animation(duration, from)
        return Yuki::Animation.scalar(duration, self, :bars_offset=, from, BARS_OPEN_OFFSET)
      end

      # Take the bars off the screen right away, with no animation, to put it back to a neutral state
      def open_bars
        self.bars_offset = BARS_OPEN_OFFSET
      end

      # Dispose the stack and the texture built for the bars, which comes from no cache
      def dispose
        super
        @bar_texture.dispose unless @bar_texture.disposed?
      end

      private

      # Move the bars apart, from the closed screen they start on to the offset they leave it at
      # @note Private on purpose: the animations of this class drive it, and Yuki::Animation sends it
      # @param value [Numeric] distance each bar has moved away, in source pixels
      def bars_offset=(value)
        @bar_top_y = -value
        @bar_bottom_y = BARS_OPEN_OFFSET + value
        apply_bars
      end

      def apply_bars
        @bar_top.y = @bar_top_y * @factor
        @bar_bottom.y = @bar_bottom_y * @factor
      end

      # Stretch a sprite over the whole screen, whatever the size of the image behind it
      # @param sprite [Sprite]
      def fill_screen(sprite)
        sprite.zoom_x = Graphics.width / sprite.width.to_f
        sprite.zoom_y = Graphics.height / sprite.height.to_f
      end

      def create_backdrop
        @backdrop = add_background(@backdrop_name)
        @backdrop.z = BACKDROP_Z
        fill_screen(@backdrop)
      end

      # Create the lines, spread over the height of the screen, each looping on its own
      def create_lines
        @line_animations = Array.new(LINE_COUNT) do |index|
          line = Line.new(add_sprite(0, 0, "#{@image_path}line", type: Sprite::WithColor), @factor)
          next create_line_animation(line, index)
        end
      end

      # Animation of one line: it crosses the screen over and over, starting where its share of the
      # cycle has already elapsed so the six lines spread out
      # @param line [Line]
      # @param index [Integer] index of the line
      # @return [Yuki::Animation::TimedLoopAnimation]
      def create_line_animation(line, index)
        ya = Yuki::Animation
        duration = LINE_CYCLE_DURATION
        animation = ya.timed_loop_animation(duration, [ya.scalar(duration, line, :y=, SOURCE_SCREEN_HEIGHT, 0)])
        return animation.start(-duration * index / LINE_COUNT)
      end

      def create_overlay
        @overlay = add_background("#{@image_path}overlay")
        @overlay.z = OVERLAY_Z
        fill_screen(@overlay)
      end

      def create_bars
        @bar_texture = solid_texture(Graphics.width, Graphics.height / 2, Color.new(0, 0, 0))
        @bar_top = create_bar
        @bar_bottom = create_bar
        self.bars_offset = 0
      end

      # Create one of the two black bars, on the texture both of them share
      # @return [Sprite]
      def create_bar
        bar = add_sprite(0, 0, nil)
        bar.bitmap = @bar_texture
        bar.z = BAR_Z
        return bar
      end
    end
  end
end
