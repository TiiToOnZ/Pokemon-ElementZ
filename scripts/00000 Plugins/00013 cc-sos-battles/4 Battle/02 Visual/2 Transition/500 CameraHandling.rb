module Battle
  class Visual3D
    module Transition3D
      module CameraHandling
        # Enemy trainers that joined after the battle opened, brought into the end sequence.
        # @note The transition lists them once as the battle starts, so a newcomer is unknown to it.
        module SOSBattleEnd
          private

          # Function that creates the animation of enemy sprite during the battle end (trainer battles only)
          # @return [Yuki::AnimationMixin]
          def show_enemy_sprite_battle_end
            @enemy_sprites = @scene.visual.enemy_trainer_sprites if battle_info.trainer_battle?

            return super
          end
        end
        prepend SOSBattleEnd
      end
    end
  end
end
