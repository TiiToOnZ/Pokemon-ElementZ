module GamePlay
  class EvolveCinematic < Evolve
    private

    # Handle keyboard input each frame
    # @return [Boolean]
    def update_inputs
      update_fast_forward
      return true unless @cancellable && !@forced

      cancel_evolution if Input.trigger?(:B)
      return true
    end

    # Speed the whole sequence up while the player holds A
    # @note Phases and background loops all read the clock of the scene, so its speed factor is enough
    def update_fast_forward
      clock.speed_factor = Input.press?(:A) ? FAST_FORWARD_FACTOR : 1
    end

    # Set whether the player may stop the evolution, which the timeline opens for the main loop only
    # @param value [Boolean]
    attr_writer :cancellable

    def cancel_evolution
      @cancellable = false
      $game_system.bgm_stop
      play(create_cancellation_animation)
    end
  end
end
