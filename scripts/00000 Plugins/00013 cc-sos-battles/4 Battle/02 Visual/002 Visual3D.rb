module Battle
  class Visual3D
    # Same pre-allocation as the plain camera, with the sprites the 3D camera drives.
    # @note Prepended here as well as on Battle::Visual because Visual3D#create_battlers does not call super.
    module SOSPreallocation3D
      private

      # Create the battler sprites (Trainer + Pokemon)
      def create_battlers
        super
        preallocate_extra_slots
      end

      # Build the creature sprite of a place the starting format does not hold.
      # @note Shaded and listed right away, since load_battler only runs once a creature takes the place.
      # @return [BattleUI::PokemonSprite3D]
      def build_extra_battler_sprite
        sprite = BattleUI::PokemonSprite3D.new(@viewport, @scene, @camera, @camera_positionner)
        sprite.shader = Shader.create(:fake_3d)
        @sprites3D.append(sprite, sprite.shadow)

        return sprite
      end

      # Build the sprite of a trainer joining the battle.
      # @param resource [Studio::Trainer] trainer the sprite stands for
      # @param bank [Integer] bank the trainer joins
      # @param position [Integer] field position they stand on
      # @return [BattleUI::TrainerSprite3D]
      def build_trainer_sprite(resource, bank, position)
        sprite = BattleUI::TrainerSprite3D.new(@viewport, @scene, resource, bank, position, @scene.battle_info)
        @sprites3D.append(sprite)

        return sprite
      end
    end
    prepend SOSPreallocation3D
  end
end
