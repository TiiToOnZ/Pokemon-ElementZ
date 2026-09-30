module BattleUI
  class TrainerSprite
    # Walk of a trainer arriving or leaving while the battle is under way.
    # @note The plain sprite already slides for that, so the arrival is its ordinary entry.
    module SOSWalk
      # Walk the trainer onto the place they are joining.
      def walk_in
        go_in
      end

      # Walk the trainer away from the place they are leaving.
      # @note Same slide as go_out, started where the sprite stands: a trainer joining moves the place of the one already there.
      def walk_out
        target_x = x + (enemy? ? FADE_AWAY_PIXEL_COUNT : -FADE_AWAY_PIXEL_COUNT)
        walk = Yuki::Animation.move_discreet(0.5, self, x, y, target_x, y)
        animation_handler[:sos_walk] = walk
        walk.start
      end
    end
    prepend SOSWalk
  end
end
