# ============================================================
# PFM::GameState Craft Extension
# ------------------------------------------------------------
# Stores crafting unlock state inside the player save data.
# ============================================================

module PFM
  class GameState
    
    # Hash storing unlocked recipes.
    # @return [Hash{Symbol => Boolean}]
    attr_accessor :crafting_data

    # Initialize crafting data when player is created.
    # @return [void]
    on_player_initialize(:crafting_data) do
      @crafting_data = {}
    end

    # Expose crafting data globally as $crafting_data.
    # @return [void]
    on_expand_global_variables(:crafting_data) do
      @crafting_data ||= {}
      $crafting_data = @crafting_data
    end
  end
end
