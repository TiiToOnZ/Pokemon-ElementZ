module Battle
  # Class that manage all the thing that are visually seen on the screen.
  class Visual
    # Clear a bar of hp of the Boss.
    # @param bank [Integer]
    # @param position [Integer]
    # @param nb_bar [Integer]
    def boss_battle_clear_bar(bank, position, nb_bar = 0)
      info_bar = @info_bars[bank][position]
      info_bar.bars_hp[nb_bar].switch_state(filled: false)
    end

    # Fills a bar of HP for the Boss.
    # @param bank [Integer]
    # @param position [Integer]
    # @param nb_bar [Integer]
    def boss_battle_add_bar(bank, position, nb_bar = 0)
      info_bar = @info_bars[bank][position]
      info_bar.bars_hp[nb_bar - 1].switch_state
    end
  end
end
