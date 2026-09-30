module PFM
  class PokemonBattler < Pokemon
    # Gives the overkill properties their resting value on a brand new battler.
    module OverkillProperties
      # Create a new PokemonBattler from a Pokemon
      # @param original [PFM::Pokemon] original Pokemon (protected during the battle)
      # @param scene [Battle::Scene] current battle scene
      # @param max_level [Integer] new max level for Online battle
      def initialize(original, scene, max_level = Float::INFINITY)
        super
        @overkilled = false
        @overkill_pending_excess = 0
      end
    end

    prepend OverkillProperties

    # Damage the hit currently landing deals beyond what the creature can take
    # @return [Integer]
    attr_accessor :overkill_pending_excess

    # Mark the creature as pulverised by an overkill
    # @return [Boolean]
    attr_writer :overkilled

    # Tell if the creature was pulverised during the battle in progress
    # @return [Boolean]
    # @note Held here and nowhere else: the AI clones its battlers, so a simulated blow marks a copy.
    def overkilled?
      return @overkilled == true
    end

    # Get the damage the creature can take in one hit, the reserve bars of a boss included
    # @return [Integer]
    # @note Floored at one, since a hit rolled against a fallen creature would clamp on an empty range.
    def overkill_absorbable_hp
      return [respond_to?(:boss?) && boss? ? total_hp : hp, 1].max
    end

    # Get the excess a hit has to reach to pulverise the creature, one health bar of it
    # @return [Integer]
    def overkill_threshold
      return [(max_hp * Overkill::Settings.threshold_multiplier).to_i, 1].max
    end

    # Tell if the hit currently landing carries enough excess to pulverise the creature
    # @return [Boolean]
    def overkill_reached?
      return @overkill_pending_excess >= overkill_threshold
    end

    # Tell if the hit currently landing pulverises the creature
    # @return [Boolean]
    # @note Only true while the hit is being processed, the excess is dropped once it is over.
    def overkill_landing?
      return dead? && overkill_reached?
    end
  end
end
