module GamePlay
  class EvolveCinematic < Evolve
    private

    # Play an animation, dropping the one that was playing
    # @param animation [Yuki::Animation::TimedAnimation]
    def play(animation)
      @animation = animation
      animation.start
    end

    # Animation uncovering the screen, then handing over to the evolution itself
    # @note A player schedules its whole stack when it starts, so this one is built after the message, not queued behind it
    # @return [Yuki::Animation::TimedAnimation]
    def create_opening_animation
      ya = Yuki::Animation
      return ya.player(
        @composition.create_bars_animation,
        ya.send_command_to(self, :show_evolving_message),
        ya.send_command_to(self, :start_evolution_animation)
      )
    end

    # Animation of the evolution, from the first glow to the last sparkle
    # @return [Yuki::Animation::TimedAnimation]
    def create_evolution_animation
      ya = Yuki::Animation
      return ya.player(
        @composition.create_glow_animation,
        ya.send_command_to(self, :cancellable=, true),
        @composition.create_main_loop_animation,
        ya.send_command_to(self, :cancellable=, false),
        @composition.create_flash_animation,
        create_reveal_animation,
        ya.send_command_to(self, :finish_evolution)
      )
    end

    # Animation of the reveal: the rising sparkles, joined by the shiny one when the creature is shiny
    # @note It was already shiny before evolving, this is not a reveal of shininess
    # @return [Yuki::Animation::TimedAnimation]
    def create_reveal_animation
      sparkles = @composition.create_sparkle_animation
      return sparkles unless @pokemon.shiny?

      return Yuki::Animation.parallel(sparkles, @composition.create_shiny_animation)
    end

    # Animation shown when the player stopped the evolution
    # @return [Yuki::Animation::TimedAnimation]
    def create_cancellation_animation
      ya = Yuki::Animation
      return ya.player(
        @composition.create_flash_animation(cancelled: true),
        ya.send_command_to(self, :finish_cancelled_evolution)
      )
    end

    # Show the evolving message, then get the window out of the way of the animation
    def show_evolving_message
      evolution_first_step
      self.message_visible = false
    end

    # Body of the engine first step, with the message waiting for the player instead of skipping
    def evolution_first_step
      $game_system.bgm_play(Configs.sounds.evolve_bgm)
      $game_system.cry_play(@pokemon.id, form: @pokemon.form)
      @message_window.auto_skip = false
      @message_window.stay_visible = true
      display_message(parse_text(31, 0, ::PFM::Text::PKNICK[0] => @pokemon.given_name))
    end

    def start_evolution_animation
      play(create_evolution_animation)
    end

    # Close the scene on the evolved Pokemon
    def finish_evolution
      self.message_visible = true
      evolution_last_step
      update_message
      @pokemon.evolve(@clone.id, @clone.form)
      restore_audio
      @running = false
      @evolved = true
    end

    # Close the scene on the Pokemon that stopped evolving
    def finish_cancelled_evolution
      self.message_visible = true
      stop_evolution_step
    end

    def release_animation
      super
      @composition.release
    end
  end
end
