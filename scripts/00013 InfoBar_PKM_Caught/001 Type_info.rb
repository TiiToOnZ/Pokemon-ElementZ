module UI
  class BattleType1Sprite < SpriteSheet

    def data=(pokemon)
      if pokemon && $pokedex.creature_seen?(pokemon.id, pokemon.form) && $game_temp.vs_type != 3
        self.visible = true
        self.sy = pokemon.send(*data_source)
      else
        self.visible = false
      end
    end

  end
end

