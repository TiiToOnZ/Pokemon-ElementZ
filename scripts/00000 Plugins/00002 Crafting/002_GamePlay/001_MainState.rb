# ============================================================
# GamePlay::MainState
# ------------------------------------------------------------
# Base state class for the Craft System.
# Provides default input methods and sound helpers.
# ============================================================

module GamePlay
  class MainState
    def initialize(ui, manager)
      @ui = ui
      @manager = manager
    end

    def enter; end
    def exit; end

    def action_a; end
    def action_b; end
    def action_x; end
    def action_y; end
    def action_l; end
    def action_r; end
    def action_up; end
    def action_down; end
    def action_left; end
    def action_right; end

    # Play cancel sound effect.
    # @return [void]
    def cursor_cancel_se
      $game_system.se_play($data_system.cancel_se)
    end

    # Play cursor movement sound effect.
    # @return [void]
    def cursor_se
      $game_system.se_play($data_system.cursor_se)
    end
  end
end
