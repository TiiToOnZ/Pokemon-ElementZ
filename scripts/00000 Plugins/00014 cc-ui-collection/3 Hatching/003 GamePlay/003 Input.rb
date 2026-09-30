module GamePlay
  class HatchCinematic < Hatch
    private

    # Speed the whole sequence up while the player holds A
    # @note Phases and background loops all read the clock of the scene, so its speed factor is enough
    def update_fast_forward
      clock.speed_factor = Input.press?(:A) ? FAST_FORWARD_FACTOR : 1
    end
  end
end
