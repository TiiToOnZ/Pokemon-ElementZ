module Battle
  class Logic
    class DamageHandler
      module ZVHealAnimDamageHandler
        def heal_change(target, hp, *args, animation_id: nil, **kwargs)
          @scene.visual.zv_show_heal_animation(target) unless animation_id || target.position == -1
          super
        end
      end
      prepend ZVHealAnimDamageHandler
    end
  end
end
