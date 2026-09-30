module BattleUI
  # Landing impact of a Pokemon sent out, graded by its weight
  module LandingImpact3D
    # Index, in the player the engine returns, of the landing beat, the one already playing the cry and the camera shake
    IMPACT_ANIMATION_INDEX = 5

    # Update the sprite
    def update
      super
      @dust_animation&.update
    end

    # Intensity of the skake effect when the Pokemon hits the ground
    # @return [Integer]
    def camera_shake_effect
      tier = UI::LandingImpact.tier_of(pokemon)
      return super unless tier

      return UI::LandingImpact.shake_amplitude(tier)
    end

    # Create the fall and the white animation after using a Pokeball
    # @param start_battle [Boolean] If the animation is done at the start of a battle
    # @return [Yuki::AnimationMixin]
    def poke_out_animation(start_battle = false) # rubocop:disable Style/OptionalBooleanParameter
      animation = super
      tier = UI::LandingImpact.tier_of(pokemon)
      return animation unless tier

      return animation.parallel_add(impact_animation(tier), IMPACT_ANIMATION_INDEX)
    end

    # Raise the cloud of dust of a Pokemon that just landed
    # @note Built on the landing beat, not with the animation, so the particles take the position and the zoom it lands with
    def dust_animation
      ya = Yuki::Animation
      dust = UI::LandingImpact::DustParticles.new(viewport, self, @scene)
      duration = UI::LandingImpact.step_duration(UI::LandingImpact::DUST_STEPS)

      @dust_animation = ya.player(
        ya.scalar(duration, dust, :animation_progression=, 0, 1),
        ya.send_command_to(dust, :dispose)
      ).start
    end

    private

    # Create the sound and, on the heavy tier, the dust of a Pokemon landing
    # @param tier [Symbol]
    # @return [Yuki::AnimationMixin]
    def impact_animation(tier)
      ya = Yuki::Animation
      sound = ya.send_command_to(UI::LandingImpact, :play_landing_se, tier)
      return sound unless UI::LandingImpact.dust?(tier)

      return ya.parallel(sound, ya.send_command_to(self, :dust_animation))
    end
  end

  PokemonSprite3D.prepend(LandingImpact3D)
end

CCUICollection::Settings.landing_impact = true
