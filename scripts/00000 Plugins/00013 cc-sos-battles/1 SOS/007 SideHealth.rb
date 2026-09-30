module SOSBattles
  # Pure computation of the remaining HP ratio of a side.
  module SideHealth
    class << self
      # Ratio of the remaining HP over the max HP of a group of battlers.
      # @param battlers [Array<#hp, #max_hp>] battlers making up the side
      # @return [Float]
      def ratio(battlers)
        max = battlers.sum(&:max_hp)
        return 0.0 if max.zero?

        return battlers.sum(&:hp).to_f / max
      end
    end
  end
end
