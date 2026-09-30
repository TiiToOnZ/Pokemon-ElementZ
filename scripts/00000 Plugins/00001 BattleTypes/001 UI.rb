module UI
  class BattleType1Sprite < SpriteSheet
    def initialize(viewport)
      super(viewport, 1, each_data_type.size)
      load_texture
    end

    def data=(pokemon)
      self.sy = pokemon.send(*data_source) if (self.visible = (pokemon ? true : false))
    end

    private

    def load_texture
      filename = "bat_types_#{$options.language}"
      load(RPG::Cache.interface_exist?(filename) ? filename : 'bat_types', :interface)
    end

    def data_source
      :type1
    end
  end

  class BattleType2Sprite < BattleType1Sprite
    private

    def data_source
      :type2
    end
  end

  class BattleTypeSprite < BattleType1Sprite
    private

    def data_source
      :type
    end
  end
end