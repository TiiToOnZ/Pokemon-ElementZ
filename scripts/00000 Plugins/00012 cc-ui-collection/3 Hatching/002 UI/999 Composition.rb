module UI
  module HatchCinematic
    # Visual orchestrator of the hatching scene
    #
    # It owns every visual element and exposes one animation per phase of the source animation. Each
    # movement is a plain animation with a duration and, where the source hand rolled a curve, one of
    # the distortions of the engine. Nothing is ever started here: the scene is the sequencer, it
    # chains those animations and plays them.
    class Composition < SpriteStack
      include Cinematic

      # z superiority of the egg and of the Pokemon it hatches into
      POKEMON_Z = 50
      # z superiority of the cracks, which have to draw over the egg they open on
      CRACKS_Z = POKEMON_Z + 1
      # z superiority of the white the burst happens under
      # @note Over the creatures and the cracks, under the burst (Burst::EFFECT_Z) and the shiny sparkle
      FLASH_Z = 100
      # z superiority of the shiny sparkle
      SHINY_Z = 300

      # The three series of shakes, each with the swing it reaches in source pixels, the number of
      # swings it makes, the seconds one swing lasts and the rest in seconds that follows it
      SHAKES = [
        { reach: 8, swings: 4, swing_duration: 0.1, rest: 0.6, crack: true, flash: false },
        { reach: -18, swings: 7, swing_duration: 0.15, rest: 0, crack: true, flash: false },
        { reach: -24, swings: 7, swing_duration: 0.15, rest: 0, crack: false, flash: true }
      ]
      # Number of seconds the white takes to cover the screen, at the end of the last shake
      FLASH_IN_DURATION = 0.125

      # Zoom the hatched Pokemon overshoots to before it settles at its size
      REVEAL_OVERSHOOT = 1.15

      # Create the composition
      # @note The creature sprites are not pushed in the stack: the scene owns them, along with its GIF reader
      # @param viewport [Viewport]
      # @param db_symbol [Symbol] species hatching, which may bring a backdrop of its own
      # @param egg_sprite [Sprite::WithColor] sprite of the egg
      # @param pokemon_sprite [Sprite::WithColor] sprite of the Pokemon inside it
      def initialize(viewport, db_symbol, egg_sprite, pokemon_sprite)
        super(viewport, 0, 0, default_cache: :interface)
        @viewport = viewport
        @background = push_sprite(Background.new(viewport, IMAGE_PATH, BACKGROUNDS[db_symbol]))
        @cracks = create_cracks
        @flash = push_sprite(Cinematic::ScreenFlash.new(viewport, FLASH_Z))
        @shiny_sparkle = push_sprite(ShinySparkle.new(viewport, SHINY_Z))
        @screen_shake = Cinematic::ScreenShake.new(viewport)
        take_creatures(egg_sprite, pokemon_sprite)
      end

      # Animation of the black bars uncovering the screen
      # @return [Yuki::Animation::TimedAnimation]
      def create_bars_animation
        return @background.create_opening_animation
      end

      # Animation of the egg bouncing, cracking one step further on each landing
      # @return [Yuki::Animation::TimedAnimation]
      def create_bounce_animation
        ya = Yuki::Animation
        bounces = Array.new(BOUNCE_COUNT) do
          next ya.player(@egg.create_bounce_animation, ya.send_command_to(self, :open_crack),
                         ya.wait(BOUNCE_REST_DURATION))
        end
        return ya.player(*bounces)
      end

      # Animation of the three series of shakes, the last one whiting the screen out
      # @return [Yuki::Animation::TimedAnimation]
      def create_shake_animation
        ya = Yuki::Animation
        steps = SHAKES.flat_map do |shake|
          series = []
          series << ya.send_command_to(self, :open_crack) if shake[:crack]
          series << (shake[:flash] ? create_flashing_shake_animation(shake) : create_swings_animation(shake))
          series << ya.wait(shake[:rest]) unless shake[:rest].zero?
          next series
        end
        return ya.player(*steps)
      end

      # Animation of the egg bursting open on the Pokemon it was holding
      # @return [Yuki::Animation::TimedAnimation]
      def create_burst_animation
        ya = Yuki::Animation
        return ya.player(
          ya.send_command_to(self, :start_burst),
          ya.se_play(BURST_SE),
          ya.parallel(create_burst_progression_animation, @screen_shake.create_animation),
          ya.parallel(@flash.create_uncover_animation(FLASH_OUT_DURATION), create_settle_animation),
          ya.wait(BURST_REST_DURATION)
        )
      end

      # Animation of the shiny sparkle, played over the reveal
      # @note The creature is not revealed to be shiny here, this is the sparkle it gets anywhere else
      # @return [Yuki::Animation::TimedAnimation]
      def create_shiny_animation
        return @shiny_sparkle.create_animation
      end

      # Dispose the stack and the burst it built on the way, which is not in it
      def dispose
        @burst&.dispose
        super
      end

      private

      # Take over the sprites the scene built, laying the cracks on the egg
      # @note They are lowered before the Egg is built, since it remembers where its sprite rests
      # @param egg_sprite [Sprite::WithColor] sprite of the egg
      # @param pokemon_sprite [Sprite::WithColor] sprite of the Pokemon inside it
      def take_creatures(egg_sprite, pokemon_sprite)
        @pokemon_sprite = pokemon_sprite
        @pokemon_sprite.z = POKEMON_Z
        egg_sprite.z = POKEMON_Z
        [egg_sprite, @pokemon_sprite].each { |sprite| sprite.y += BODY_HALF_HEIGHT }
        @egg = Egg.new(egg_sprite, @cracks)
      end

      # Animation of one series of shakes, the egg swinging aside and back over and over
      # @param shake [Hash] one entry of SHAKES
      # @return [Yuki::Animation::TimedAnimation]
      def create_swings_animation(shake)
        return @egg.create_swings_animation(shake[:reach], shake[:swings], shake[:swing_duration])
      end

      # Animation of the last series of shakes, the white covering the screen over the end of it
      # @param shake [Hash] one entry of SHAKES
      # @return [Yuki::Animation::TimedAnimation]
      def create_flashing_shake_animation(shake)
        ya = Yuki::Animation
        wait_duration = shake[:swings] * shake[:swing_duration] - FLASH_IN_DURATION
        white_out = ya.player(ya.wait(wait_duration), @flash.create_cover_animation(FLASH_IN_DURATION))
        return ya.parallel(create_swings_animation(shake), white_out)
      end

      # Animation of the burst, one progression the ring and every sparkle read their state from
      # @return [Yuki::Animation::TimedAnimation]
      def create_burst_progression_animation
        return Yuki::Animation.scalar(BURST_DURATION, self, :burst_progression=, 0, 1)
      end

      # Animation of the hatched Pokemon overshooting its size then settling at it
      # @return [Yuki::Animation::TimedAnimation]
      def create_settle_animation
        return Yuki::Animation.scalar(FLASH_OUT_DURATION, self, :creature_zoom=, REVEAL_OVERSHOOT, 1)
      end

      def burst_progression=(value)
        @burst.animation_progression = value
      end

      def creature_zoom=(value)
        @pokemon_sprite.zoom = value
      end

      # Hand the stage over to the Pokemon, under the white, and throw the burst out
      def start_burst
        @egg.visible = false
        @pokemon_sprite.visible = true
        @pokemon_sprite.set_color([1, 1, 1, 0])
        self.creature_zoom = REVEAL_OVERSHOOT
        @burst = Burst.new(@viewport)
      end

      # Open the egg one crack further
      def open_crack
        @egg.crack
        $game_system.se_play(Configs.sounds.egg_move_se)
      end

      # Create the strip of cracks, laid on the egg once the composition takes it over
      # @return [Sprite]
      def create_cracks
        cracks = add_sprite(0, 0, "#{IMAGE_PATH}cracks")
        cracks.z = CRACKS_Z
        return cracks
      end
    end
  end
end
