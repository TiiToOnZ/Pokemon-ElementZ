module PFM
  # The InGame Pokemon management
  # @author Nuri Yuri
  class Pokemon
    # Give the shiny rate for the Pokemon, The number should be between 0 & 0xFFFF.
    # 0 means absolutely no chance to be shiny, 0xFFFF means always shiny
    # @return [Integer]
    def shiny_rate
      655
    end
  end
end