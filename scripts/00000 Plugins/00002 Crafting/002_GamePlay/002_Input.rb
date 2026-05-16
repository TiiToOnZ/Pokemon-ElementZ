# ============================================================
# GamePlay::CraftSystemUI::Input
# ------------------------------------------------------------
# Handles input delegation for the Craft System UI.
# Forwards actions to the current active state.
# ============================================================

module GamePlay
  class CraftSystemUI

    AIU_KEY2METHOD = {
      A: :action_a,
      X: :action_x,
      Y: :action_y,
      B: :action_b,
      L: :action_l,
      R: :action_r,
      F: :action_l,
      G: :action_r,
      UP: :action_up,
      DOWN: :action_down,
      LEFT: :action_left,
      RIGHT: :action_right
    }

    ACTIONS = %i[action_a action_x action_y action_b]

    # Update input handling.
    # @return [Boolean]
    def update_inputs
      return false unless @composition.done?
      return false unless automatic_input_update(AIU_KEY2METHOD)
    end

    private

    def action_a; @state_manager.current.action_a; end
    def action_b; @state_manager.current.action_b; end
    def action_x; @state_manager.current.action_x; end
    def action_y; @state_manager.current.action_y; end

    def action_l; @state_manager.current.action_l; end
    def action_r; @state_manager.current.action_r; end

    def action_up;    @state_manager.current.action_up; end
    def action_down;  @state_manager.current.action_down; end
    def action_left;  @state_manager.current.action_left; end
    def action_right; @state_manager.current.action_right; end
  end
end
