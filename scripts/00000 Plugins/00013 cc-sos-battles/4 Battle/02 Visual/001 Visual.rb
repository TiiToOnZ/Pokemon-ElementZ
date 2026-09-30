module Battle
  class Visual
    # Extra battler slot pre-allocated so that no graphic object is created mid-battle.
    module SOSPreallocation
      # Bring a battler on its pre-allocated slot.
      # @param battler [PFM::PokemonBattler] battler entering the field
      # @param from_ball [Boolean] false to walk in from the side, as a wild ally with no trainer to throw one does
      def show_incoming_battler(battler, from_ball: true)
        sprite = battler_sprite(battler.bank, battler.position)
        sprite.pokemon = battler
        sort_battler_sprites
        sprite.visible = false
        # Put back whatever happens: only some entry paths clear it, and it is saved to disk left on.
        $game_switches[Yuki::Sw::BT_NO_BALL_ANIMATION] = true unless from_ball
        sprite.go_in
        show_info_bar(battler)
        wait_for_sprites(sprite)
      ensure
        $game_switches[Yuki::Sw::BT_NO_BALL_ANIMATION] = false unless from_ball
      end

      # Bring the sprite of a trainer joining the battle in, standing where their creature will land.
      # @note Stored at the negative key -party_id - 1, the one enemy_trainer_sprites reads them back from.
      # @param bank [Integer] bank the trainer joins
      # @param party_id [Integer] index of their party on that bank
      # @param position [Integer] field position they stand on
      def show_incoming_trainer(bank, party_id, position)
        resource = @scene.battle_info.battlers[bank][party_id]
        return unless resource

        sprite = build_trainer_sprite(resource, bank, position)
        sprite.create_animation
        @animatable << sprite
        store_battler_sprite(bank, -party_id - 1, sprite)
        sprite.walk_in
        wait_for_sprites(sprite)
        @team_info[bank]&.refresh
      end

      # Walk a beaten trainer back on screen, so their defeat line is spoken by someone visible.
      # @param bank [Integer] bank of the trainer
      # @param party_id [Integer] index of their party on that bank
      def show_beaten_trainer(bank, party_id)
        sprite = battler_sprite(bank, -party_id - 1)
        return unless sprite

        sprite.walk_in
        wait_for_sprites(sprite)
      end

      # Send a beaten trainer away for good and take their sprite out of the battler hash.
      # @note Dropping the key is what keeps a trainer who already had their scene out of the final one.
      # @param bank [Integer] bank of the trainer
      # @param party_id [Integer] index of their party on that bank
      def forget_trainer_sprite(bank, party_id)
        sprite = battler_sprite(bank, -party_id - 1)
        send_trainer_away(sprite)
        sprite&.visible = false
        @battlers[bank]&.delete(-party_id - 1)
      end

      # Sprites of the enemy trainers still on the books, in party order.
      # @note A trainer who already had their defeat scene is dropped from the hash, so they are left out.
      # @return [Array<BattleUI::TrainerSprite>]
      def enemy_trainer_sprites
        return @scene.battle_info.parties[1].each_index.map { |party_id| battler_sprite(1, -party_id - 1) }.compact
      end

      # Have a trainer send their creature out, once they have left the place to it.
      # @param bank [Integer] bank of the trainer
      # @param party_id [Integer] index of their party on that bank
      # @param battler [PFM::PokemonBattler] creature being sent out
      def send_out_from_trainer(bank, party_id, battler)
        send_trainer_away(battler_sprite(bank, -party_id - 1))
        show_incoming_battler(battler)
      end

      # Re-point the sprite and the bar of a place at the battler that now stands there.
      # @note Mirrors Actions::Shift: the sprite owns its place, and pokemon= is the one way to refresh it.
      # @param battler [PFM::PokemonBattler] battler that changed place
      def reseat_battler(battler)
        sprite = battler_sprite(battler.bank, battler.position)
        sprite.pokemon = battler
        # pokemon= restores nothing else, and a knock out left this place faded out. Same set as follower_go_in_animation.
        sprite.visible = true
        sprite.opacity = 255
        sprite.zoom = sprite.sprite_zoom
        sprite.set_tone_status(battler.status, true)
        sort_battler_sprites
        show_info_bar(battler)
      end

      # Free the slot of a battler that left an enlarged field.
      # @param battler [PFM::PokemonBattler] battler leaving the field
      def hide_outgoing_battler(battler)
        # A negative position addresses a trainer sprite, so the caller lost track of who stands there.
        return log_error("SOS tried to hide a battler off the field: #{battler}") if battler.position.nil? || battler.position.negative?

        hide_info_bar(battler)
        # Blanked as well as sent out: a bar slides out over several frames, showing whoever it still holds.
        @info_bars.dig(battler.bank, battler.position)&.pokemon = nil
        sprite = battler_sprite(battler.bank, battler.position)
        sprite.pokemon = nil
        sprite.visible = false
      end

      # Re-place every creature sprite and info bar after the field format changed.
      # @note MultiplePosition reads vs_type on each call, so the layout follows a format change.
      def refresh_field_positions
        @battlers.each_value do |sprites|
          sprites.each do |position, sprite|
            next if position.negative?
            next unless sprite.pokemon

            # reset_position is private; pokemon= would reload the bitmap and restart the animation.
            sprite.send(:reset_position)
          end
        end
        sort_battler_sprites
        @info_bars.each_value { |bars| bars.each(&:refresh) }
      end

      private

      # Re-order the viewport after a battler sprite took a new z.
      # @note The scene sorts once, before an extra slot holds a creature: its sprite is still tied at z 0 with its own shadow there.
      def sort_battler_sprites
        @viewport.sort_z
      end

      # Create the battler sprites (Trainer + Pokemon)
      def create_battlers
        super
        preallocate_extra_slots
      end

      # Take a trainer off the screen and wait until they are gone.
      # @note Left visible on purpose: the battle end sequence brings them back by opacity alone.
      # @param trainer [BattleUI::TrainerSprite, nil] sprite of the trainer leaving
      def send_trainer_away(trainer)
        return unless trainer

        trainer.walk_out
        wait_for_sprites(trainer)
      end

      # Let going in and going out animations play to their end, together.
      # @param sprites [Array<#done?, nil>] sprites being animated
      def wait_for_sprites(*sprites)
        animated = sprites.compact
        until animated.all?(&:done?)
          update
          Graphics.update
        end
      end

      # Build the sprite and the bars of the place each bank may gain.
      def preallocate_extra_slots
        return unless @scene.logic.field_growth_possible?

        preallocate_extra_slot(0)
        preallocate_extra_slot(1)
        hide_info_bars(true)
      end

      # Build the creature sprite of a place the starting format does not hold.
      # @note A method of its own because the 3D camera builds this sprite differently.
      # @return [BattleUI::PokemonSprite]
      def build_extra_battler_sprite
        return BattleUI::PokemonSprite.new(@viewport, @scene)
      end

      # Build the sprite of a trainer joining the battle.
      # @param resource [Studio::Trainer] trainer the sprite stands for
      # @param bank [Integer] bank the trainer joins
      # @param position [Integer] field position they stand on
      # @return [BattleUI::TrainerSprite]
      def build_trainer_sprite(resource, bank, position)
        return BattleUI::TrainerSprite.new(@viewport, @scene, resource, bank, position, @scene.battle_info)
      end

      # Build the sprite and the bars of the extra slot of a bank.
      # @param bank [Integer] bank getting an extra slot
      def preallocate_extra_slot(bank)
        position = @scene.logic.extra_position
        sprite = build_extra_battler_sprite
        sprite.visible = false
        @animatable << sprite
        store_battler_sprite(bank, position, sprite)
        create_info_bar(bank, position)
        create_ability_bar(bank, position)
        create_item_bar(bank, position)
        # create_info_bar picks up the reserve creature sitting at that index, which show_info_bars would then slide in.
        @info_bars[bank][position].pokemon = nil
      end
    end
    prepend SOSPreallocation
  end
end
