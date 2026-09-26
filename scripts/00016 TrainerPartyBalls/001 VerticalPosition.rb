module BattleUI
  class TrainerPartyBalls < UI::SpriteStack
    module VerticalPosition
      ENEMY_Y_OFFSET = 13
      PLAYER_Y_OFFSET = -3

      private

      # Shared reference for initial placement and native go_in/go_out animations.
      def sprite_position
        x, y = super
        # Keep the native offscreen position of the enemy party in wild battles.
        return x, y if enemy? && !scene.battle_info.trainer_battle?

        return x, y + (enemy? ? ENEMY_Y_OFFSET : PLAYER_Y_OFFSET)
      end
    end

    prepend VerticalPosition
  end
end
