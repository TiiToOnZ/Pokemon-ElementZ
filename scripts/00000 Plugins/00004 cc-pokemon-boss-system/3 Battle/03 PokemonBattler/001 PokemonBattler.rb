module PFM
  # Class defining a Pokemon during a battle, it aims to copy its properties but also to have the methods related to the battle.
  class PokemonBattler < Pokemon
    module PokemonBattlerBossPatch
      # Create a new PokemonBattler from a Pokemon.
      # @param original [PFM::Pokemon] original Pokemon. (protected during the battle)
      # @param scene [Battle::Scene] current battle scene.
      # @param max_level [Integer] new max level for Online battle.
      def initialize(original, scene, max_level = Float::INFINITY)
        super
        @boss = original.boss || false
        @nb_bars_hp = original.nb_bars_hp || 0
      end

      # Return if the Pokemon is a Boss.
      # @return [Boolean]
      def boss?
        return @boss
      end
    end

    prepend PokemonBattlerBossPatch
  end
end
