module BattleUI
  class TrainerSprite3D
    # Walk of a trainer arriving or leaving while the battle is under way.
    # @note Out of go_in_animation and go_out_animation, empty on purpose: the end sequence places trainers itself, with a camera move.
    module SOSWalk
      # Seconds the walk takes, as the 3D transition times the departure of a trainer
      WALK_DURATION = 0.5

      # Offset a trainer walks to as they leave, taken from that same departure
      WALK_OFFSET = [40, -10]

      # Walk the trainer onto the place they are joining.
      # @note Aimed at the place the engine computes, which is where they belong once everyone is counted.
      def walk_in
        place = sprite_position
        start_walk(one_step_off(place), place, 0, 255)
      end

      # Walk the trainer away from the place they are leaving.
      # @note Started where the sprite stands, not where it belongs: a trainer joining moves the place of the one already there.
      def walk_out
        start_walk([x, y], one_step_off([x, y]), 255, 0)
      end

      private

      # The point one step off a place, where a trainer walks from and to.
      # @param place [Array(Integer, Integer)] place they stand on
      # @return [Array(Integer, Integer)]
      def one_step_off(place)
        return [place.first + WALK_OFFSET.first, place.last + WALK_OFFSET.last]
      end

      # Play the walk, under a key of our own so the engine animations keep theirs.
      # @param from [Array(Integer, Integer)] point the walk starts at
      # @param to [Array(Integer, Integer)] point the walk ends at
      # @param from_opacity [Integer] opacity the walk starts at
      # @param to_opacity [Integer] opacity the walk ends at
      def start_walk(from, to, from_opacity, to_opacity)
        animation = Yuki::Animation

        walk = animation.parallel(
          animation.move(WALK_DURATION, self, from.first, from.last, to.first, to.last),
          animation.scalar(WALK_DURATION, self, :opacity=, from_opacity, to_opacity)
        )
        animation_handler[:sos_walk] = walk
        walk.start
      end
    end
    prepend SOSWalk
  end
end
