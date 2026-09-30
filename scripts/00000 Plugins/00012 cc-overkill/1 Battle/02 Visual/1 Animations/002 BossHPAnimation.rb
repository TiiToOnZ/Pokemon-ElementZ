module Battle
  class Visual
    # A boss runs its own gauge timeline, which show_boss_hp_animation builds without ever going
    # through create_hp_animation_handler, so the overkill leg is appended here instead.
    # @note Declared with its superclass rather than guarded by defined?, the boss plugin loading later.
    class BossHPAnimation < Yuki::Animation::Player
      # Appends the overkill drain once the bars have finished cascading.
      module OverkillBossLeg
        private

        # Build the stack: one leg per bar the path runs through, a boundary crossing in between, then the
        # snap and the beat the engine leaves once a gauge has settled.
        # @param path [PFM::BossHPPath]
        # @return [Array<Yuki::AnimationMixin>]
        def build_stack(path)
          stack = super
          # An excess is only ever armed past the last bar, so reaching here means the boss is down.
          animation = @visual.overkill_bar_animation_for(@target)
          stack << animation if animation

          return stack
        end
      end

      prepend OverkillBossLeg
    end
  end
end
