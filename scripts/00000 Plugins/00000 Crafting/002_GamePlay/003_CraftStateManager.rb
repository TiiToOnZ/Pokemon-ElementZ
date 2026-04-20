# ============================================================
# GamePlay::CraftStateManager
# ------------------------------------------------------------
# Manages state transitions for the Craft System UI.
# ============================================================

module GamePlay
  class CraftStateManager
    attr_reader :current

    # Initialize state manager and default state.
    # @param ui [Object]
    # @return [void]
    def initialize(ui)
      @ui = ui
      @states = {
        select: SelectState.new(ui, self),
        info:   InfoState.new(ui, self)
      }
      set(:select)
    end

    # Change current state.
    # @param name [Symbol]
    # @return [void]
    def set(name)
      @current = @states[name]
      @current.enter
    end
  end
end
