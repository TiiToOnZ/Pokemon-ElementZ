module PFM
  class Pokemon
    # Extra shiny rolls granted by an ongoing SOS chain.
    module SOSChainShiny
      # Number of attempt to generate a shiny
      # @return [Integer]
      def shiny_attempts
        return super + ($game_temp&.sos_chain_shiny_rolls || 0)
      end
    end
    prepend SOSChainShiny
  end
end

class Game_Temp
  # Extra shiny rolls granted to the next generated creature
  # @return [Integer, nil]
  attr_accessor :sos_chain_shiny_rolls
end
