module SOSBattles
  # One-shot SOS configuration attached to the next battle.
  class Request
    # Whether the SOS mechanic runs during this battle
    # @return [Boolean]
    attr_reader :enabled

    # Trainers that may join, each entry being [Studio trainer ID, rate in percent]
    # @return [Array<Array(Integer, Integer)>]
    attr_reader :trainers

    # Create a new configuration for the next battle.
    # @param enabled [Boolean] whether the SOS mechanic runs
    # @param species [Array<Symbol>, nil] fixed species answering the calls
    # @param trainers [Array<Array(Integer, Integer)>, nil] trainers that may join
    def initialize(enabled: true, species: nil, trainers: nil)
      @enabled = enabled
      @species = Array(species)
      @species_imposed = !species.nil?
      @trainers = trainers || []
    end

    # Whether this battle was given its own list of species to summon.
    # @note Told apart from an exhausted list, so a scripted battle never falls back on the area.
    # @return [Boolean]
    def species_imposed?
      return @species_imposed
    end

    # Next species to summon, popped from the fixed order.
    # @return [Symbol, nil]
    def next_species
      return @species.shift
    end

    # Whether an imposed list was given and has been summoned to the last one.
    # @return [Boolean]
    def species_exhausted?
      return species_imposed? && @species.empty?
    end

    # Whether the spent list has been announced, which ends the calls of this battle for good.
    # @return [Boolean]
    def calls_over?
      return species_exhausted? && @exhaustion_told == true
    end

    # Remember the player has been told the list is spent.
    def exhaustion_told
      @exhaustion_told = true
    end
  end
end

class Game_Temp
  # SOS configuration attached to the next battle
  # @return [SOSBattles::Request, nil]
  attr_accessor :sos_request
end
