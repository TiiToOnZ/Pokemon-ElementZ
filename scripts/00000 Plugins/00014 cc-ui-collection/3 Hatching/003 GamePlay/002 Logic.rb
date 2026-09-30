module GamePlay
  class HatchCinematic < Hatch
    private

    # Play an animation, dropping the one that was playing
    # @param animation [Yuki::Animation::TimedAnimation]
    def play(animation)
      @animation = animation
      animation.start
    end

    # Animation uncovering the screen, then handing over to the hatching itself
    # @note A player schedules its whole stack when it starts, so this one is built after the message, not queued behind it
    # @return [Yuki::Animation::TimedAnimation]
    def create_opening_animation
      ya = Yuki::Animation
      return ya.player(
        @composition.create_bars_animation,
        ya.send_command_to(self, :show_hatching_message),
        ya.send_command_to(self, :start_hatch_animation)
      )
    end

    # Animation of the hatching, from the first bounce of the egg to the cry of the Pokemon
    # @return [Yuki::Animation::TimedAnimation]
    def create_hatch_animation
      ya = Yuki::Animation
      return ya.player(
        ya.wait(OPENING_WAIT_DURATION),
        @composition.create_bounce_animation,
        @composition.create_shake_animation,
        @composition.create_burst_animation,
        create_reveal_animation,
        ya.send_command_to(self, :finish_hatch)
      )
    end

    # Animation of the reveal: the cry of the Pokemon, joined by the shiny sparkle when it is shiny
    # @note It was already shiny inside the egg, this is not a reveal of shininess
    # @return [Yuki::Animation::TimedAnimation]
    def create_reveal_animation
      ya = Yuki::Animation
      cry = ya.player(ya.send_command_to(self, :play_cry), ya.wait(CRY_DURATION))
      return cry unless @pokemon.shiny?

      return ya.parallel(cry, @composition.create_shiny_animation)
    end

    # Show the opening message of the engine, then get the window out of the way of the animation
    # @note The engine skips it on its own, this one waits for the player, as the evolution scene does
    def show_hatching_message
      @message_window.auto_skip = false
      @message_window.stay_visible = true
      display_message(text_get(36, 37))
      self.message_visible = false
    end

    def start_hatch_animation
      play(create_hatch_animation)
    end

    def play_cry
      $game_system.cry_play(@pokemon.id, form: @pokemon.form)
    end

    # Close the scene on the hatched Pokemon
    # @note Copied from pokemonsdk/scripts/4 Systems/303 Evolve/200 Hatch.rb:79, where it lives in two branches of update_message
    def finish_hatch
      self.message_visible = true
      @message_window.auto_skip = false
      $game_system.temporary_bgm_play(Configs.sounds.evolved_bgm, position: 0)
      PFM::Text.set_pkname(@pokemon, 0)
      display_message(text_get(36, 38))
      show_rename_choice
      Audio.bgm_stop
      $game_system.bgm_restore2
      $pokedex.mark_seen(@pokemon.id, @pokemon.form, forced: true)
      $pokedex.mark_captured(@pokemon.id, @pokemon.form)
      $pokedex.increase_creature_fought(@pokemon.id)
      $pokedex.increase_creature_caught_count(@pokemon.id)
      @pokemon.loyalty = 120
      @running = false
    end
  end
end
