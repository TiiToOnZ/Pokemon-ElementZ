module Studio
  class Group
    class Encounter
      alias __capture_chain_to_creature to_creature

      # Applies chain bonuses as soon as a wild encounter Pokemon is generated.
      def to_creature(level = nil)
        CaptureChain.apply_bonus!(__capture_chain_to_creature(level))
      end
    end
  end
end

module PFM
  class Wild_Battle
    alias __capture_chain_init_battle init_battle

    # Applies chain bonuses to each Pokemon of a forced wild battle.
    def init_battle(id, level = 70, *others)
      __capture_chain_init_battle(id, level, *others)
      return unless @forced_wild_battle.is_a?(Array)

      @forced_wild_battle.each { |pokemon| CaptureChain.apply_bonus!(pokemon) }
    end
  end
end
