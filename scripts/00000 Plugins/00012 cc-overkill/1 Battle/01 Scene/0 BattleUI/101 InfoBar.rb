module BattleUI
  class InfoBar < UI::SpriteStack
    # Adds the overkill gauge, laid over the HP one and idle until a knockout overshoots.
    module InfoBarOverkillPatch
      # Drive the overkill gauge, laid over the HP one wherever that one currently sits.
      # @param value [Numeric] 0 ~ 1
      def overkill_rate=(value)
        follow_hp_bar
        @overkill_bar.rate = value
      end

      # Sets the Pokemon shown by this bar
      # @param pokemon [PFM::Pokemon]
      def pokemon=(pokemon)
        # Only a new occupant empties the gauge: refresh_info_bar calls this every frame, same creature.
        self.overkill_rate = 0 if @overkill_bar && !pokemon.equal?(@pokemon)
        super
      end

      private

      # Creates all the sprites used by the InfoBar.
      def create_sprites
        super
        create_overkill
      end

      # Create the overkill gauge, empty until an overkill animation drives its rate.
      def create_overkill
        bar_info = @is_triple_battle ? HP_BAR_INFO_V3 : HP_BAR_INFO
        bitmap = RPG::Cache.interface("battle/bars_overkill#{suffix_3v3}")
        # One single state: UI::Bar reads its colour from the rate, and six would turn green.
        @overkill_bar = push_sprite(UI::Bar.new(@viewport, *hp_bar_coordinates, bitmap, *bar_info[0, 4], 1))
        # Idle is a zero rate, never an invisible sprite: SpriteStack#visible= would turn it back on.
        self.overkill_rate = 0
      end

      # Lay the gauge onto the HP gauge it stands in for, which another patch may have moved.
      # @note push_sprite does not set z, and the gauge has to cover the HP one.
      def follow_hp_bar
        @overkill_bar.set_position(@hp_bar.x, @hp_bar.y)
        @overkill_bar.z = @hp_bar.z + 1
      end
    end

    prepend InfoBarOverkillPatch
  end
end
