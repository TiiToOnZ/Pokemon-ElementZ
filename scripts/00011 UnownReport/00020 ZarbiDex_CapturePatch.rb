# Monkey patch: hook into the battle catch sequence once the Pokemon is really obtained.

module Battle
  class Scene
    module ZarbiDexCapturePatch
      # Extend the catch flow to register newly captured Zarbi letters.
      # @param battler [PFM::PokemonBattler]
      # @param ball [Studio::BallItem]
      def give_pokemon_procedure(battler, ball)
        pokemon = battler.original
        super
        ZarbiDex.register_captured_pokemon(pokemon, self)
      end
    end

    prepend ZarbiDexCapturePatch
  end
end
