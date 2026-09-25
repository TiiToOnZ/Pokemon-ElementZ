module ElementZ
  module QuestJournal
    class MenuButton < UI::PSDKMenuButtonBase
      private

      def text
        QuestJournal.label(:menu)
      end

      def create_icon
        # A 1x1 sheet accepts native select(0/1, index) calls through modulo.
        # Keep the native selection movement/rotation, without editing menu_icons.
        @icon = with_cache(:icon) { add_sprite(24, 11, '433', 1, 1, type: SpriteSheet) }
        @icon.set_origin(@icon.width / 2, @icon.height / 2)
        @icon.zoom = 22.0 / [@icon.width, @icon.height].max
      end
    end

    module MenuExtension
      private

      def init_indexes
        super
        actions = GamePlay::Menu::ACTION_LIST
        quest_index = actions.index(:open_elementz_quests)
        return unless @image_indexes.delete(quest_index)

        # Move only the display index; retain native registrations 0..6 and
        # BUTTON_OVERWRITES[2] (girl bag), CONDITION_LIST[3] (trainer card).
        bag_position = @image_indexes.index(actions.index(:open_bag))
        @image_indexes.insert(bag_position ? bag_position + 1 : 0, quest_index)
      end

      def open_elementz_quests
        GamePlay.open_quest_ui
      end
    end
  end
end

GamePlay::Menu.prepend(ElementZ::QuestJournal::MenuExtension)
unless GamePlay::Menu::ACTION_LIST.include?(:open_elementz_quests)
  GamePlay::Menu.register_button(:open_elementz_quests) { $bag.contain_item?(:journal) }
end
GamePlay::Menu.register_button_overwrite(GamePlay::Menu::ACTION_LIST.index(:open_elementz_quests)) do
  ElementZ::QuestJournal::MenuButton
end
