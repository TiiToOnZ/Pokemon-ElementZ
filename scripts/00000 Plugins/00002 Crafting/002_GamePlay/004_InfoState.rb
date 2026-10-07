# ============================================================
# GamePlay::InfoState
# ------------------------------------------------------------
# Information state of the Craft System UI.
# Displays recipe summary panel.
# ============================================================

module GamePlay
  class InfoState < MainState

    # Enter information state.
    # @return [void]
    def enter
      @ui.base_ui.mode = 1
      @ui.composition.mode = :information if @ui.composition
    end
    
    # Return to selection state.
    # @return [void]
    def action_b
      cursor_cancel_se
      @manager.set(:select)
    end
  end
end
