module Battle
  class Visual
    # Show animation of a battler being healed
    # @param target [PFM::PokemonBattler]
    def zv_show_heal_animation(target)
      return if target.effects.has?(:substitute)

      ya = Yuki::Animation
      target_sprite = battler_sprite(target.bank, target.position)
      animator = ZVBattleUI::HealAnimator.new(viewport, @scene, target_sprite)
      anim = animator.create_animation
      anim.play_before(ya.send_command_to(animator, :dispose))

      @animations << anim
      anim.start
      wait_for_animation
    end
  end
end
