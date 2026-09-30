module GamePlay
  # Cinematic egg hatching scene, replacing the engine one
  #
  # The scene owns the sequence and the engine beats, the composition owns the pixels.
  # Every phase of the source animation is a Yuki::Animation the composition builds, so the
  # timing stays the one it was transcribed from.
  class HatchCinematic < Hatch
    include UI::HatchCinematic

    # Update the hatching process
    # @note The engine drives its whole sequence from a frame counter and this one plays animations,
    #   so the body replaces it rather than its steps, message pumping of the base scene included
    # @return [Boolean]
    def update
      @pokemon_gif&.update(@pokemon_sprite.bitmap)
      @composition.update
      message_update
      return false if message_processing?

      update_fast_forward
      return true unless can_display_message_be_called?

      @animation&.update
      return true
    end

    # Dispose the scene graphics.
    # @note @viewport and @message_window will be disposed.
    def dispose
      @composition&.dispose
      super
    end

    private

    # Create the scene graphics
    # @note The creature sprites come first because the composition takes them over, and the order they
    #   are built in says nothing of the order they are drawn in: every z is explicit and sorted below
    def create_graphics
      create_viewport
      create_pokemon_sprite
      create_egg_sprite
      create_composition
      Graphics.sort_z
      play(create_opening_animation)
    end

    def create_composition
      @composition = Composition.new(@viewport, @pokemon.db_symbol, @egg_sprite, @pokemon_sprite)
    end
  end
end

CCUICollection::Settings.hatching = true
