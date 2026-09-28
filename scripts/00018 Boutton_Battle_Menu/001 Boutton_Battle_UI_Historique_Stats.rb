module BattleUI
  class PlayerChoice
    # Reuse the native secondary command's background, font and key shortcut.
    class BattleInfoStatsHintButton < SpecialButton
      def refresh
        @text.text = 'Stats'
      end

      private

      def obtain_button_data
        return ['battle/button_y', BattleInfoStats::TOGGLE_KEY]
      end
    end

    # Keep SpecialButton's native label selection and refresh, resizing only its
    # background. The middle strip can grow for long item names without scaling
    # the key, text or rounded borders, or allocating textures on each refresh.
    class BattleInfoCompactButton < SpecialButton
      attr_reader :compact_width

      def refresh
        super
        fit_background
      end

      private

      # Create all background pieces before the native text and key sprites.
      def add_background(filename, **options)
        @compact_background = super
        @compact_middle = add_sprite(0, 0, nil)
        @compact_border = add_sprite(0, 0, nil)
        @compact_middle.bitmap = @compact_border.bitmap = @compact_background.bitmap
        return @compact_background
      end

      def fit_background
        padding = BattleInfoStatsHintPatch::HINT_RIGHT_PADDING
        edge = BattleInfoStatsHintPatch::HINT_BORDER_WIDTH
        text_offset = @text.x - x
        width = (text_offset + @text.real_width).ceil + padding
        return if width == @compact_width

        @compact_width = width
        bitmap = @compact_background.bitmap
        @compact_background.set_rect(0, 0, text_offset, bitmap.height)
        @compact_middle.set_rect(text_offset, 0, 1, bitmap.height)
        @compact_middle.zoom_x = width - text_offset - edge
        @compact_middle.set_position(x + text_offset, y)
        @compact_border.set_rect(bitmap.width - edge, 0, edge, bitmap.height)
        @compact_border.set_position(x + width - edge, y)
      end
    end

    class BattleInfoHistoryButton < BattleInfoCompactButton
      def refresh
        @text.text = 'Historique'
        fit_background
      end

      private

      def obtain_button_data
        return ['battle/button_y', Configs.zv_battle_log.open_button]
      end
    end

    # Only the label changes; SubChoice still handles the Information action.
    class BattleInfoShortInfoButton < SpecialButton
      def refresh
        @text.text = 'Info'
      end
    end

    # Use the native SubChoice and its visibility/input rules. Visual subclasses
    # resize V and shorten B's label without changing their actions.
    class BattleInfoSubChoice < SubChoice
      def add_sprite(x, y, bitmap, *args, **options)
        if options[:type] == SpecialButton && %i[last_item shift].include?(args.first)
          options[:type] = BattleInfoCompactButton
        elsif options[:type] == SpecialButton && args.first == :info
          options[:type] = BattleInfoShortInfoButton
        end
        super
      end
    end

    module BattleInfoStatsHintPatch
      HINT_GAP = 4
      HINT_RIGHT_PADDING = 4
      # Preserve the rounded right border of battle/button_y without scaling it.
      HINT_BORDER_WIDTH = 4
      ACTION_GRID = [[172, 181], [246, 181], [172, 211], [246, 211]].freeze
      ACTION_CURSOR_OFFSET_X = -8

      private

      def create_sprites
        super
        create_battle_info_stats_hint
        create_battle_info_history_hint
      end

      def create_buttons
        super
        return unless instance_of?(PlayerChoice)

        @buttons.zip(ACTION_GRID).each do |button, (button_x, button_y)|
          button.set_position(x + button_x, y + button_y)
        end
      end

      def cursor_offset_x
        return ACTION_CURSOR_OFFSET_X if instance_of?(PlayerChoice)

        super
      end

      def create_sub_choice
        return super unless instance_of?(PlayerChoice) && battle_info_history_available?

        @sub_choice = add_sprite(0, 0, nil, @scene, self, type: BattleInfoSubChoice)
      end

      def battle_info_history_available?
        return defined?(ZVBattleLog::Scene) && Configs.respond_to?(:zv_battle_log) &&
               respond_to?(:zv_trigger_choice_history?, true)
      end

      def create_battle_info_history_hint
        return unless @sub_choice.is_a?(BattleInfoSubChoice)

        v_button = @sub_choice.instance_variable_get(:@x_button)
        @battle_info_history_hint = add_sprite(
          @battle_info_stats_hint.x - x, v_button.y - y, nil, :info, type: BattleInfoHistoryButton
        )
        @battle_info_history_hint.refresh
        info_button = @sub_choice.instance_variable_get(:@info_button)
        v_button.set_position(info_button.x, info_button.y)
        info_button.set_position(
          @battle_info_history_hint.x + @battle_info_history_hint.compact_width + HINT_GAP,
          @battle_info_history_hint.y
        )
        v_button.refresh
      end

      def create_battle_info_stats_hint
        info_button = @sub_choice.instance_variable_get(:@info_button)
        # SubChoice already carries PlayerChoice's initial offscreen offset.
        hint_x = info_button.x - x
        hint_y = info_button.y - y
        @battle_info_stats_hint = add_sprite(
          hint_x, hint_y, nil, :info, type: BattleInfoStatsHintButton
        )
        info_button.refresh

        hint_text = @battle_info_stats_hint.stack.find { |sprite| sprite.is_a?(Text) }
        # Give Information exactly the width saved from the previous label.
        hint_text.text = 'STATS'
        previous_width = hint_text.real_width.ceil
        @battle_info_stats_hint.refresh
        saved_width = previous_width - hint_text.real_width.ceil
        hint_width = fit_battle_info_stats_hint_button(@battle_info_stats_hint)
        fit_battle_info_stats_hint_button(info_button, extra_padding: saved_width)
        info_button.x += hint_width + HINT_GAP
      end

      # Trim only unused background space. Both pieces share the cached bitmap
      # and remain in the native stack for movement, fades, visibility and disposal.
      def fit_battle_info_stats_hint_button(button, extra_padding: 0)
        background = button.stack.first
        text = button.stack.find { |sprite| sprite.is_a?(Text) }
        left_padding = extra_padding / 2
        text.x += left_padding
        width = (text.x - button.x + text.real_width).ceil + HINT_RIGHT_PADDING
        width += extra_padding - left_padding
        body_width = width - HINT_BORDER_WIDTH
        bitmap = background.bitmap
        background.set_rect(0, 0, body_width, bitmap.height)
        border = button.add_sprite(body_width, 0, nil)
        border.bitmap = bitmap
        border.set_rect(bitmap.width - HINT_BORDER_WIDTH, 0, HINT_BORDER_WIDTH, bitmap.height)
        border.z = background.z
        return width
      end
    end

    prepend BattleInfoStatsHintPatch
  end
end
