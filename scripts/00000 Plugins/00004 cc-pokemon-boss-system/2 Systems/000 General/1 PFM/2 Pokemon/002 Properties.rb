module PFM
  class Pokemon
    # Return if the Pokemon is a Boss.
    # @return [Boolean]
    attr_accessor :boss
    # The number of hp bars the Pokemon has.
    # @return [Integer]
    attr_accessor :nb_bars_hp
    # The type of halo to display for the boss (:flame, :ice, :orbital, :pulse, :shadow, :vortex)
    # @return [Symbol, nil]
    attr_accessor :boss_halo
  end
end
