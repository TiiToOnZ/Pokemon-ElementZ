module UI
  class BattleType1Sprite < SpriteSheet
    # Cached on data refresh: movement must not query the Pokedex each frame.
    def type_displayable?
      return @type_displayable == true
    end

    def data=(pokemon)
      @type_displayable = false
      if pokemon && $pokedex.creature_seen?(pokemon.id, pokemon.form)
        self.sy = pokemon.send(*data_source)
        @type_displayable = sy != 0
      end
      self.visible = type_displayable?
    end
  end
end
