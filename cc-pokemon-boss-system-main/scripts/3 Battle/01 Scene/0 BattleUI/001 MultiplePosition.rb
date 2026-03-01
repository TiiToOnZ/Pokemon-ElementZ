module BattleUI
  module MultiplePosition
    # Tell if the sprite is from a enemy Boss
    # @return [Boolean]
    def enemy_boss?
      return false unless enemy?
      return false unless @scene.logic.battler(1, position)&.boss?

      return true
    end
  end
end
