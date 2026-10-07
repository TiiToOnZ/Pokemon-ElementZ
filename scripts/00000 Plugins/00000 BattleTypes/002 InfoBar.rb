module BattleUI
  class InfoBar < UI::SpriteStack
    def create_type_sprite
      add_sprite(*type1_coordinates, NO_INITIAL_IMAGE, type: BattleType1Sprite)
      add_sprite(*type2_coordinates, NO_INITIAL_IMAGE, type: BattleType2Sprite)
    end

    def type1_coordinates
      return -20, -7 if enemy?

      return 135, 0
    end

    def type2_coordinates
      return -20, 12 if enemy?

      return 135, 19
    end
  end
end

module SpritePatch
  def create_sprites
    super
    create_type_sprite
  end
end

module BattleUI
  class InfoBar < UI::SpriteStack
    prepend SpritePatch
  end
end