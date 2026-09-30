module BattleUI
  class PokemonSprite3D
    # Walk-in of a creature nobody threw a ball for, which the 3D sprite left out of go_in_animation.
    # rubocop:disable Style/OptionalBooleanParameter
    module SOSBallLessEntry
      # Creates the go_in animation (Exiting the ball)
      # @param start_battle [Boolean] If the animation is done at the start of a battle
      # @return [Yuki::AnimationMixin]
      def go_in_animation(start_battle = false)
        return super unless $game_switches[Yuki::Sw::BT_NO_BALL_ANIMATION] && enemy?

        # Borrowed from the plain sprite: the 3D one answers this with a display nothing could start.
        return PokemonSprite.instance_method(:follower_go_in_animation).bind(self).call
      end
    end
    # rubocop:enable Style/OptionalBooleanParameter
    prepend SOSBallLessEntry
  end
end
