module UI
  module EvolveCinematic
    # Visual orchestrator of the evolution scene
    #
    # It owns every visual element and exposes one animation per phase of the source animation. Each
    # movement is a plain animation with a duration, several of them running in parallel where the
    # source moved everything on the same frame. Nothing is ever started here: the scene is the
    # sequencer, it chains those animations and plays them. The sounds welded to a phase are played
    # by the animation of that phase, the scene keeping the beats of its own, the music and the cries.
    class Composition < SpriteStack
      include Cinematic

      # z superiority of both Pokemon sprites
      POKEMON_Z = 50
      # z superiority of the shine shown behind the Pokemon
      BACK_SHINE_Z = 40
      # z superiority of the shines shown in front of the Pokemon
      FRONT_SHINE_Z = 60
      # z superiority of the white veil, which has to cover the black bars as well
      # @note The source whitens the whole viewport, bars included, and a veil only covers what sits
      #   under it, hence a z above Background::BAR_Z rather than just above the effects
      FLASH_Z = 210
      # z superiority of the shiny sparkle, the one thing that plays over the white
      SHINY_Z = 250

      # Number of seconds each half of the initial glow lasts
      GLOW_HALF_DURATION = 0.4
      # Zoom the shine of the glow opens to
      GLOW_SHINE_ZOOM = 1.28
      # Zoom that shine falls back to as it fades away
      GLOW_SHINE_END_ZOOM = 0.96
      # Offset the bars close back to during the glow, in source pixels
      BARS_GLOW_OFFSET = 96

      # Number of seconds the Pokemon takes to turn fully white
      WHITE_DURATION = 0.4
      # Number of half swings the two forms trade their size over, one entry per tier of the loop
      LOOP_SWINGS = [2, 4, 8, 16]
      # Number of seconds one of those half swings lasts, one entry per tier
      LOOP_SWING_DURATIONS = [0.8, 0.4, 0.2, 0.1]
      # Number of seconds the shine behind the Pokemon takes to open
      LOOP_SHINE_OPEN_DURATION = 0.4
      # Zoom that shine opens to
      LOOP_SHINE_ZOOM = 1.28
      # Number of seconds one breath of that shine lasts
      LOOP_SHINE_BREATH_DURATION = 0.4
      # Zoom that shine breathes by
      LOOP_SHINE_BREATH = 0.16
      # Amount of white that shine gathers over the loop
      LOOP_SHINE_WHITE = 120
      # Number of seconds the last shine bursts over, at the end of the loop
      END_SHINE_DURATION = 0.4
      # Zoom the last shine sits at before it bursts
      END_SHINE_START_ZOOM = 0.5
      # Zoom the last shine bursts to, from the half it sits at
      END_SHINE_ZOOM = 2.1
      # Number of seconds the screen takes to white out, at the very end of the loop
      WHITE_OUT_DURATION = 0.2

      # Number of seconds the bars take to leave the screen, over the flash
      BARS_LEAVING_DURATION = 0.3
      # Number of seconds the revealed Pokemon takes to settle at its size
      REVEAL_DURATION = 0.4
      # Zoom the revealed Pokemon overshoots to before it settles
      REVEAL_OVERSHOOT = 1.15

      # One of the three shines, whose properties the animations drive one at a time
      class Shine
        # Take over a shine sprite
        # @param source [SourceSprite] sprite state pushed in the stack
        def initialize(source)
          @source = source
        end

        # @param value [Numeric]
        def zoom=(value)
          @source.zoom = value
          @source.apply
        end

        # @param value [Numeric]
        def opacity=(value)
          @source.opacity = value
          @source.apply
        end

        # @param value [Numeric] amount of white blended over the shine
        def white=(value)
          @source.color_alpha = value
          @source.apply
        end

        # @param value [Boolean]
        def visible=(value)
          @source.visible = value
        end
      end

      # Create the composition
      # @note The Pokemon sprites are not pushed in the stack: the scene owns them, along with their GIF readers
      # @param viewport [Viewport]
      # @param pokemon_sprite [Sprite::WithColor] sprite of the evolving Pokemon
      # @param evolved_sprite [Sprite::WithColor] sprite of the Pokemon it evolves into
      def initialize(viewport, pokemon_sprite, evolved_sprite)
        super(viewport, 0, 0, default_cache: :interface)
        @background = push_sprite(Background.new(viewport, IMAGE_PATH))
        @particles = push_sprite(OrbitingParticles.new(viewport))
        @rays = push_sprite(Rays.new(viewport))
        @risers = push_sprite(RisingSparkles.new(viewport))
        @screen_flash = push_sprite(ScreenFlash.new(viewport, FLASH_Z))
        @shiny_sparkle = push_sprite(ShinySparkle.new(viewport, SHINY_Z))
        @screen_shake = ScreenShake.new(viewport)
        @pokemon_sprite = pokemon_sprite
        @evolved_sprite = evolved_sprite
        @pokemon_zoom = 1
        @clone_zoom = 0
        @pokemon_white = 0
        create_shines
        create_creatures
      end

      # Animation of the black bars uncovering the screen
      # @return [Yuki::Animation::TimedAnimation]
      def create_bars_animation
        return @background.create_opening_animation
      end

      # Animation of the initial glow, the Pokemon whitening under a shine while the bars close back
      # @return [Yuki::Animation::TimedAnimation]
      def create_glow_animation
        ya = Yuki::Animation
        bars = @background.create_closing_animation(GLOW_HALF_DURATION * 2, BARS_GLOW_OFFSET)
        glow = ya.parallel(bars, ya.player(create_glow_in_animation, create_glow_out_animation))
        return ya.player(ya.se_play(GLOW_SE), glow)
      end

      # Animation of the main loop, where both Pokemon trade their zoom
      # @return [Yuki::Animation::TimedAnimation]
      def create_main_loop_animation
        ya = Yuki::Animation
        return ya.player(
          ya.se_play(LOOP_SE),
          ya.send_command_to(@rays, :start),
          ya.parallel(
            create_trade_animation,
            ya.scalar(WHITE_DURATION, self, :pokemon_white=, 0, 255),
            create_loop_shine_animation,
            ya.player(ya.wait(MAIN_LOOP_DURATION - END_SHINE_DURATION), create_end_shine_animation),
            ya.player(ya.wait(MAIN_LOOP_DURATION - WHITE_OUT_DURATION), create_white_out_animation)
          )
        )
      end

      # Animation of the white flash revealing the Pokemon the scene ends on
      # @note The cancelled flash is silent: the scene stopped the music on it, it is not the reveal
      # @param cancelled [Boolean] if the player stopped the evolution
      # @return [Yuki::Animation::TimedAnimation]
      def create_flash_animation(cancelled: false)
        ya = Yuki::Animation
        start = ya.send_command_to(self, :start_flash, cancelled)
        duration = cancelled ? CANCELLED_FLASH_DURATION : FLASH_DURATION
        fade = @screen_flash.create_uncover_animation(duration)
        return ya.player(start, fade) if cancelled

        leaving = @background.create_leaving_animation(BARS_LEAVING_DURATION, BARS_GLOW_OFFSET)
        return ya.player(ya.se_play(FLASH_SE, FLASH_SE_VOLUME), start,
                         ya.parallel(fade, leaving, @screen_shake.create_animation, create_settle_animation))
      end

      # Animation of the shiny sparkle, played over the reveal
      # @note The creature was already shiny before evolving: this is the sparkle it gets anywhere else
      # @return [Yuki::Animation::TimedAnimation]
      def create_shiny_animation
        return @shiny_sparkle.create_animation
      end

      # Animation of the sparkles rising once the evolved Pokemon is shown
      # @return [Yuki::Animation::TimedAnimation]
      def create_sparkle_animation
        ya = Yuki::Animation
        return ya.player(
          ya.se_play(SPARKLE_SE),
          ya.send_command_to(@risers, :create_sparkles),
          ya.scalar(SPARKLE_DURATION, @risers, :animation_progression=, 0, 1)
        )
      end

      # Put the screen back to a neutral state, when the evolution was stopped
      # @note The bars are half closed for the whole loop, which is the only moment the player may stop
      #   the evolution, so they have to be opened back for the message that follows
      def release
        @screen_flash.clear
        @screen_shake.reset
        @background.open_bars
        @pokemon_zoom = 1
        @pokemon_white = 0
        apply_creatures
      end

      private

      # Animation of the first half of the glow, the shine opening as the Pokemon whitens
      # @return [Yuki::Animation::TimedAnimation]
      def create_glow_in_animation
        ya = Yuki::Animation
        return ya.parallel(
          ya.scalar(GLOW_HALF_DURATION, @start_shine, :zoom=, 0, GLOW_SHINE_ZOOM),
          ya.scalar(GLOW_HALF_DURATION, @start_shine, :opacity=, 0, 255),
          ya.scalar(GLOW_HALF_DURATION, self, :pokemon_white=, 0, 255)
        )
      end

      # Animation of the second half of the glow, the shine fading as the particles come out
      # @return [Yuki::Animation::TimedAnimation]
      def create_glow_out_animation
        ya = Yuki::Animation
        return ya.parallel(
          ya.send_command_to(@particles, :start),
          ya.scalar(GLOW_HALF_DURATION, @start_shine, :zoom=, GLOW_SHINE_ZOOM, GLOW_SHINE_END_ZOOM),
          ya.scalar(GLOW_HALF_DURATION, @start_shine, :opacity=, 255, 0),
          ya.scalar(GLOW_HALF_DURATION, self, :pokemon_white=, 255, 0)
        )
      end

      # Animation of both forms trading their size, swinging faster on every tier of the loop
      # @return [Yuki::Animation::TimedAnimation]
      def create_trade_animation
        ya = Yuki::Animation
        swings = LOOP_SWINGS.each_with_index.flat_map do |count, tier|
          next Array.new(count) do |index|
            trade_from = index.even? ? 1 : 0
            next ya.scalar(LOOP_SWING_DURATIONS[tier], self, :trade=, trade_from, 1 - trade_from)
          end
        end
        return ya.player(*swings)
      end

      # Animation of the shine behind the Pokemon, which opens then breathes while it whitens
      # @return [Yuki::Animation::TimedAnimation]
      def create_loop_shine_animation
        ya = Yuki::Animation
        breathing_duration = MAIN_LOOP_DURATION - LOOP_SHINE_OPEN_DURATION
        opening = ya.parallel(
          ya.scalar(LOOP_SHINE_OPEN_DURATION, @loop_shine, :zoom=, 0, LOOP_SHINE_ZOOM),
          ya.scalar(LOOP_SHINE_OPEN_DURATION, @loop_shine, :opacity=, 0, 255)
        )
        breathing = ya.parallel(
          create_breathing_animation(breathing_duration),
          ya.scalar(breathing_duration, @loop_shine, :white=, 0, LOOP_SHINE_WHITE)
        )
        return ya.player(opening, breathing)
      end

      # Animation of that shine breathing in and out until the loop ends
      # @param duration [Float] number of seconds it breathes for
      # @return [Yuki::Animation::TimedAnimation]
      def create_breathing_animation(duration)
        ya = Yuki::Animation
        breaths = Array.new((duration / LOOP_SHINE_BREATH_DURATION).round) do |index|
          reach = index.even? ? LOOP_SHINE_ZOOM + LOOP_SHINE_BREATH : LOOP_SHINE_ZOOM
          from = index.even? ? LOOP_SHINE_ZOOM : LOOP_SHINE_ZOOM + LOOP_SHINE_BREATH
          next ya.scalar(LOOP_SHINE_BREATH_DURATION, @loop_shine, :zoom=, from, reach)
        end
        return ya.player(*breaths)
      end

      # Animation of the last shine bursting over the final moment of the loop
      # @return [Yuki::Animation::TimedAnimation]
      def create_end_shine_animation
        ya = Yuki::Animation
        return ya.parallel(
          ya.scalar(END_SHINE_DURATION, @end_shine, :zoom=, END_SHINE_START_ZOOM, END_SHINE_ZOOM),
          ya.scalar(END_SHINE_DURATION, @end_shine, :opacity=, 0, 255)
        )
      end

      # Animation of the screen whiting out on the last moment of the loop
      # @return [Yuki::Animation::TimedAnimation]
      def create_white_out_animation
        return @screen_flash.create_cover_animation(WHITE_OUT_DURATION)
      end

      # Animation of the revealed Pokemon overshooting its size then settling at it
      # @return [Yuki::Animation::TimedAnimation]
      def create_settle_animation
        return Yuki::Animation.scalar(REVEAL_DURATION, self, :evolved_zoom=, REVEAL_OVERSHOOT, 1)
      end

      # Give the evolving Pokemon that share of its size, the other form taking what is left
      # @param value [Float] between 0 and 1
      def trade=(value)
        @pokemon_zoom = value
        @clone_zoom = 1 - value
        apply_creatures
      end

      def evolved_zoom=(value)
        @clone_zoom = value
        apply_creatures
      end

      def pokemon_white=(value)
        @pokemon_white = value
        apply_creatures
      end

      # Hide everything the flash swallows and show the Pokemon the scene ends on
      # @note The veil is not laid here: the white out ends on it, and the fade puts it back on its first step
      # @param cancelled [Boolean] if the player stopped the evolution
      def start_flash(cancelled)
        @shines.each { |shine| shine.visible = false }
        @particles.hide
        @rays.hide
        @pokemon_sprite.visible = cancelled
        @evolved_sprite.visible = !cancelled
        @pokemon_zoom = 1
        @clone_zoom = 1
        @pokemon_white = 0
        @evolved_sprite.set_color([0, 0, 0, 0])
        apply_creatures
      end

      # Put both Pokemon sprites where the composition animates them, the evolved one hidden in white
      def create_creatures
        @pokemon_sprite.z = POKEMON_Z
        @evolved_sprite.z = POKEMON_Z
        @evolved_sprite.opacity = 255
        @evolved_sprite.set_color([1, 1, 1, 1])
        apply_creatures
      end

      def apply_creatures
        @pokemon_sprite.zoom = @pokemon_zoom
        @evolved_sprite.zoom = @clone_zoom
        @pokemon_sprite.set_color([1, 1, 1, @pokemon_white.clamp(0, 255) / 255.0])
      end

      def create_shines
        @start_shine = build_shine('shine_1', FRONT_SHINE_Z, 0)
        @loop_shine = build_shine('shine_3', BACK_SHINE_Z, 0, Sprite::WithColor)
        @end_shine = build_shine('shine_4', FRONT_SHINE_Z, 0.5)
        @shines = [@start_shine, @loop_shine, @end_shine]
      end

      # Build one of the three shines centered on the Pokemon
      # @param image_name [String] name of the asset inside the interface cache
      # @param z [Integer] z superiority of the shine
      # @param zoom [Float] zoom the shine starts at
      # @param type [Class] class of the sprite, a colored one for the shine that whitens over time
      # @return [Shine]
      def build_shine(image_name, z, zoom, type = Sprite)
        sprite = add_sprite(0, 0, "#{IMAGE_PATH}#{image_name}", type: type)
        sprite.z = z
        source = SourceSprite.new(sprite)
        source.x = POKEMON_X
        source.y = POKEMON_Y
        source.zoom = zoom
        source.opacity = 0
        source.apply
        return Shine.new(source)
      end
    end
  end
end
