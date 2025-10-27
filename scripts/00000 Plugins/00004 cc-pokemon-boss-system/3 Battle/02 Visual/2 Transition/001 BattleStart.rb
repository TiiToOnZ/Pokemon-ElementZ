module Battle
  # Module holding all the message function used by the battle engine
  module Message
    # A Wild Pokemon appeared
    # @return [String]
    def wild_battle_appearance
      sentence_index = @battle_info.wild_battle_reason.to_i % 7
      first_pokemon = @logic.battler(1, 0)
      second_pokemon = @logic.battler(1, 1)
      @text.reset_variables

      if second_pokemon
        @text.parse(10_000, 25, PKNAME[0] => first_pokemon.name, PKNAME[1] => second_pokemon.name)
      else
        @text.parse(18, 1 + sentence_index, PKNAME[0] => first_pokemon.name)
      end
    end
  end
end
