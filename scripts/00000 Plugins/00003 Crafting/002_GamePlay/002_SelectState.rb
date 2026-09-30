# ============================================================
# GamePlay::SelectState
# ------------------------------------------------------------
# Default selection state of the Craft System UI.
# Handles grid navigation, category switching
# and crafting confirmation.
# ============================================================

module GamePlay
  class SelectState < MainState
    include UI::CraftSystemUI::DataProvider

    # Enter selection state.
    # @return [void]
    def enter
      @ui.base_ui.mode = 0
      @ui.composition.mode = :select
    end

    # Confirm crafting.
    # @return [void]
    def action_y
      data = @ui.composition.current_recipe_data
      return play_buzzer_se if data.nil?

      if data[:max_craft] < 1
        play_buzzer_se
        $scene.display_message(ext_text(140000, 0))
        return
      end

      item = data_item(data[:result])

      $game_temp.num_input_variable_id = Yuki::Var::EnteredNumber
      $game_temp.num_input_digits_max  = data[:max_craft].to_s.length
      $game_temp.num_input_start       = data[:max_craft]

      $scene.display_message(format(ext_text(140000, 1), item: item.exact_name))
      value = $game_variables[Yuki::Var::EnteredNumber]

      if value > 0
        if @ui.composition.craft(value)
          $scene.display_message(
            format(ext_text(140000, 2), quantity: value, item: item.exact_name)
          )
        else
          play_buzzer_se
        end
      end

      PFM::Text.reset_variables
    end

    # Switch to information state.
    # @return [void]
    def action_x
      data = @ui.composition.current_recipe_data
      return play_buzzer_se if data.nil?
      return play_buzzer_se if data[:ingredients].to_a.empty?

      cursor_se
      @manager.set(:info)
    end

    # Exit crafting UI.
    # @return [void]
    def action_b
      cursor_cancel_se
      @ui.instance_variable_set(:@running, false)
    end

    def action_l; cursor_se; @ui.composition.previous_category; end
    def action_r; cursor_se; @ui.composition.next_category; end

    def action_up;    cursor_se; @ui.composition.move_up; end
    def action_down;  cursor_se; @ui.composition.move_down; end
    def action_left;  cursor_se; @ui.composition.move_left; end
    def action_right; cursor_se; @ui.composition.move_right; end
  end
end
