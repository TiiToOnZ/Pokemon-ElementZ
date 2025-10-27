class Interpreter
  # Start a Boss battle
  # @param first_pokemon [PFM::Pokemon] The first Pokemon
  # @param second_pokemon [PFM::Pokemon] The potential second Pokemon
  # @param id [Integer] id of the scenarize battle to get the right Boss Effect
  def call_battle_boss(first_pokemon, second_pokemon = nil, id = 1)
    $wild_battle.start_boss_battle(first_pokemon, second_pokemon, battle_id: id)
    @wait_count = 2
  end
end
