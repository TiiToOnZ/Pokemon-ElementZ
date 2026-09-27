module BattleUI
  class PlayerChoice
    module BattleInfoStatsHintPatch
      private

      def create_sprites
        super
        create_battle_info_stats_hint
      end

      def create_battle_info_stats_hint
        create_battle_info_stats_hint_background if File.exist?('graphics/interface/battle/button_stats_hint.png')
        @battle_info_stats_hint_key = add_sprite(14, 156, nil, BattleInfoStats::TOGGLE_KEY, type: UI::KeyShortcut)
        @battle_info_stats_hint_text = add_text(38, 156, 72, 16, 'Stats', color: 0)
      end

      def create_battle_info_stats_hint_background
        @battle_info_stats_hint_box = add_sprite(8, 152, 'battle/button_stats_hint')
      end
    end

    prepend BattleInfoStatsHintPatch
  end
end