# ============================================================
# GamePlay::CraftSystemUI
# ------------------------------------------------------------
# Main Craft System UI controller.
# Responsible for UI creation, update loop management
# and state manager initialization.
# ============================================================

module GamePlay
  class CraftSystemUI < BaseCleanUpdate
    attr_reader :base_ui, :composition, :state_manager

    # Initialize the Craft System UI.
    # @return [void]
    def initialize
      super()
      @running = true
    end

    # Update graphical elements.
    # @return [void]
    def update_graphics
      @base_ui.update_background_animation
      @composition.update
    end

    private

    # Create all graphical components of the UI.
    # @return [void]
    def create_graphics
      super
      create_base_ui
      create_composition
      create_state_manager
      Graphics.sort_z
    end

    # Initialize the state manager.
    # @return [void]
    def create_state_manager
      @state_manager = CraftStateManager.new(self)
    end

    # Create the base UI (background and button hints).
    # @return [void]
    def create_base_ui
      btn_texts = button_texts
      @base_ui = UI::GenericBaseMultiMode.new(
        @viewport,
        btn_texts,
        [UI::GenericBase::DEFAULT_KEYS] * btn_texts.size
      )
      @base_ui.ctrl
    end

    # Define button texts for each mode.
    # @return [Array<Array<String, nil>>]
    def button_texts
      [
        [nil, ext_text(140000, 11), ext_text(140000, 12), ext_text(140000, 13)],
        [nil, nil, nil, ext_text(140000, 13)]
      ]
    end

    # Create the main crafting composition.
    # @return [void]
    def create_composition
      @composition = UI::CraftSystemUI::Composition.new(@viewport)
    end
  end
end

GamePlay.craft_system_class = GamePlay::CraftSystemUI
