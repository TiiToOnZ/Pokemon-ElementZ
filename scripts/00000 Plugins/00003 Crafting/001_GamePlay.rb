# ============================================================
# GamePlay Craft System Entry
# ------------------------------------------------------------
# Provides access to the Craft System UI scene.
# ============================================================

module GamePlay
  class << self
    
    # Craft System UI class reference.
    # @return [Class]
    attr_accessor :craft_system_class
    
    # Open the Craft System UI scene.
    # @return [void]
    def open_craft_system_ui
      current_scene.call_scene(craft_system_class)
    end
  end
end

# Example:
# GamePlay.open_craft_system_ui
