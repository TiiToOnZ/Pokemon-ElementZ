module GamePlay
  # Cinematic evolution scene, replacing the engine one
  #
  # The scene owns the sequence and the engine beats, the composition owns the pixels.
  # Every phase of the source animation is a Yuki::Animation the composition builds, so the
  # timing stays the one it was transcribed from.
  class EvolveCinematic < Evolve
    include UI::EvolveCinematic

    # Launch the Pokemon Evolution scene
    # @param pokemon [PFM::Pokemon] the evolving Pokemon
    # @param id [Integer] the ID of the evolution
    # @param form [Integer] the form of the evolution
    # @param forced [Boolean] if the evolution can be stopped or not
    def initialize(pokemon, id, form = nil, forced = false) # rubocop:disable Style/OptionalBooleanParameter
      super
      @cancellable = false
    end

    # Update the graphics
    def update_graphics
      @pokemon_gif&.update(@sprite_pokemon.bitmap)
      @clone_gif&.update(@sprite_clone.bitmap)
      @composition.update
      return unless can_display_message_be_called?

      @animation&.update
    end

    # Dispose the scene graphics.
    # @note @viewport and @message_window will be disposed.
    def dispose
      @composition&.dispose
      super
    end

    private

    # Build the scene graphics
    # @note The order they are created in does not order them on the screen: every z is explicit, and
    #   the engine sorts the viewport once this is done
    def create_graphics
      create_viewport
      create_sprite_pkmn
      create_sprite_pkmn_evolved
      create_composition
      Graphics.sort_z
      play(create_opening_animation)
    end

    def create_composition
      @composition = Composition.new(@viewport, @sprite_pokemon, @sprite_clone)
    end
  end
end

CCUICollection::Settings.evolution = true
