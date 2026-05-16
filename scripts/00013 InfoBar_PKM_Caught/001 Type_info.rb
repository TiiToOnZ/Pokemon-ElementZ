module UI
  class BattleType1Sprite < SpriteSheet

    def data=(pokemon)
      if pokemon && $pokedex.creature_caught?(pokemon.id, pokemon.form)
        self.visible = true
        self.sy = pokemon.send(*data_source)
      else
        self.visible = false
      end
    end

  end
end

