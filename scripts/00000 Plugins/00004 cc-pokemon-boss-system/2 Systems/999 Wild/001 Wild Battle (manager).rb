module PFM
  class Wild_Battle
    # Start a boss battle
    # @param first_pokemon [PFM::Pokemon] The first Pokemon
    # @param second_pokemon [PFM::Pokemon] The potential second Pokemon
    # @param battle_id [Integer] id of the scenarize battle to get the right Boss Effect
    def start_boss_battle(first_pokemon, second_pokemon = nil, battle_id: 1)
      $game_temp.battle_can_lose = false
      init_boss_battle(first_pokemon, second_pokemon)
      Graphics.freeze
      $scene = Battle::Scene.new(setup(battle_id))
      Yuki::FollowMe.set_battle_entry
    end

    # Init a boss battle
    # @param first_pokemon [PFM::Pokemon] The first Pokemon
    # @param second_pokemon [PFM::Pokemon] The potential second Pokemon
    def init_boss_battle(first_pokemon, second_pokemon = nil)
      @forced_wild_battle = [first_pokemon]
      @forced_wild_battle << second_pokemon if second_pokemon.instance_of? PFM::Pokemon
    end
  end
end
