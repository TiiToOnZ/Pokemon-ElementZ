# Move Effectiveness Preview
#
# Author : Raty
# License : MIT
#
# PSDK plugin that shows the expected type effectiveness
# directly in the move selection UI.
#
# Notes:
# - Single-target moves preview the default target chosen by PSDK before the target-selection step.
# - Multi-target moves can show mixed values, displayed as "Variable (x0.5 / x2)".
# - In 3v3, mixed values use the compact format "x0.5 / x2 / x4".

module EffectivenessPreview
  #--------------------------------------------------------------------------
  # General settings
  #--------------------------------------------------------------------------
  # Preview display mode:
  # 0 = disable the plugin
  # 1 = fixed preview with background asset
  # 2 = text preview inside each move button
  DISPLAY_MODE = 2
  # Show or hide the neutral preview "Efficace (x1)" in every display mode.
  SHOW_WHEN_NEUTRAL = false
  # Limit the preview to specific Pokedex states:
  # :ALL = always show the preview
  # :SEEN = only show it for creatures already seen
  # :CAUGHT = only show it for creatures already caught
  SHOW_FOR_CREATURES = :ALL
  # Text color used by the effectiveness preview in every display mode.
  TEXT_COLOR = 9
  # Label used when different targets have different multipliers.
  VARIABLE_TEXT = 'Variable'

  #--------------------------------------------------------------------------
  # Display mode 1 settings
  #--------------------------------------------------------------------------
  # Background asset shown behind the preview text in mode 1.
  # This asset is a 3-frame vertical spritesheet.
  BACKGROUND_IMAGE = 'battle/button_effectiveness_fixed_preview'
  # Background position in the move choice UI in mode 1: [x, y]
  BACKGROUND_POSITION = [2, 188] # 2, 9 for top left

  #--------------------------------------------------------------------------
  # Display mode 2 settings
  #--------------------------------------------------------------------------
  # Background asset shown behind the preview text in mode 2.
  # This asset is a 3-frame vertical spritesheet.
  MODE_2_BACKGROUND_IMAGE = 'battle/button_effectiveness_skill_preview'
  # Background offset from its default bottom-right position in mode 2: [x, y]
  MODE_2_BACKGROUND_OFFSET = [-3, 2]

  module_function

  #--------------------------------------------------------------------------
  # General methods
  #--------------------------------------------------------------------------

  # Return the battlers used by the preview.
  # Single-target moves preview every valid enemy target when PSDK allows the
  # player to choose a target. Otherwise they preview the default target.
  # Multi-target moves preview every valid enemy target.
  # @param move [Battle::Move]
  # @param user [PFM::PokemonBattler]
  # @param logic [Battle::Logic]
  # @return [Array<PFM::PokemonBattler>]
  def preview_targets(move, user, logic)
    targets = move.battler_targets(user, logic).compact.select(&:alive?)
    targets.reject! { |target| target.bank == user.bank }
    return [] if targets.empty?

    return targets if preview_all_targets?(move, logic, targets)
    return [targets.first] if move.one_target?

    targets
  end

  # Tell if the preview should use every possible target for a one-target move.
  # This happens when the battle actually opens the target selection UI.
  # @param move [Battle::Move]
  # @param logic [Battle::Logic]
  # @param targets [Array<PFM::PokemonBattler>]
  # @return [Boolean]
  def preview_all_targets?(move, logic, targets)
    return false unless move.one_target?
    return false if move.no_choice_skill?
    return false if logic.battle_info.vs_type == 1

    targets.size > 1
  end

  # Tell if the preview can be shown for a specific target.
  # @param target [PFM::PokemonBattler]
  # @param setting [String]
  # @return [Boolean]
  def show_preview_for_target?(target, setting)
    return true if setting == 'ALL'
    return false unless $pokedex

    case setting
    when 'CAUGHT' then $pokedex.creature_caught?(target.db_symbol)
    when 'SEEN' then $pokedex.creature_seen?(target.db_symbol)
    else true
    end
  end

  # Return the previewed target values in target order.
  # Allowed targets return their multiplier. Hidden targets return nil so the
  # preview can display a "?" placeholder in their position.
  # When every target is allowed, duplicate values are still collapsed in
  # order to keep the original compact behaviour.
  # @param move [Battle::Move, nil]
  # @param user [PFM::PokemonBattler, nil]
  # @param logic [Battle::Logic, nil]
  # @return [Array<Float, nil>, nil]
  def multipliers_for(move, user, logic)
    return unless move && user && logic
    with_silent_move_logs do
      targets = preview_targets(move, user, logic)
      next if targets.empty?

      setting = SHOW_FOR_CREATURES.to_s.upcase
      values = targets.map do |target|
        next multiplier_for(move, user, target) if show_preview_for_target?(target, setting)

        nil
      end
      next values if values.any?(&:nil?)

      values.uniq
    end
  end

  # Compute the previewed multiplier.
  # The move internal effectiveness state is restored after the calculation.
  # @param move [Battle::Move]
  # @param user [PFM::PokemonBattler]
  # @param target [PFM::PokemonBattler]
  # @return [Float]
  def multiplier_for(move, user, target)
    previous_effectiveness = move.effectiveness
    return 0.0 if move.send(:target_immune?, user, target)

    move.type_modifier(user, target).to_f
  ensure
    move.instance_variable_set(:@effectiveness, previous_effectiveness)
  end

  # Return the localized label matching a multiplier.
  # @param multiplier [Float]
  # @return [String]
  def label_for(multiplier)
    return ext_text(8999, 24) if multiplier.zero?
    return ext_text(8999, 23) if multiplier > 1
    return ext_text(8999, 25) if multiplier < 1

    ext_text(8999, 22)
  end

  # Build the final preview text from the target values list.
  # Hidden targets are shown as "?" while keeping the real target order.
  # In 3v3, mixed values use a compact "x1 / x2 / x4" format to save space.
  # @param multipliers [Array<Float, nil>]
  # @param logic [Battle::Logic, nil]
  # @return [String, nil]
  def build_text(multipliers, logic)
    known_multipliers = multipliers.compact
    return if known_multipliers.empty?
    return if known_multipliers.all? { |multiplier| multiplier == 1.0 } && !SHOW_WHEN_NEUTRAL

    displayed_multipliers = displayed_multipliers_for(multipliers, logic)
    return if displayed_multipliers.empty?

    values = displayed_multipliers.map do |multiplier|
      multiplier.nil? ? '?' : "x#{format_multiplier(multiplier)}"
    end.join(' / ')
    return values if compact_variable_text?(multipliers, logic)

    label = displayed_multipliers.size == 1 ? label_for(known_multipliers.first) : VARIABLE_TEXT
    "#{label} (#{values})"
  end

  # Format a multiplier for display.
  # @param multiplier [Float]
  # @return [String]
  def format_multiplier(multiplier)
    formatted = format('%.3f', multiplier).sub(/\.?0+\z/, '')
    formatted.empty? ? '0' : formatted
  end

  # Execute a preview calculation without emitting Battle::Move debug data logs.
  # This only affects the UI preview and does not change battle logs elsewhere.
  # @yieldreturn [Object]
  # @return [Object]
  def with_silent_move_logs
    previous = $effectiveness_preview_silent_move_logs
    $effectiveness_preview_silent_move_logs = true
    yield
  ensure
    $effectiveness_preview_silent_move_logs = previous
  end

  # Build the preview text shared by every display mode.
  # Returns nil when the preview should not be shown.
  # @param move [Battle::Move, nil]
  # @param user [PFM::PokemonBattler, nil]
  # @param logic [Battle::Logic, nil]
  # @return [String, nil]
  def preview_text_for(move, user, logic)
    multipliers = multipliers_for(move, user, logic)
    return unless multipliers

    build_text(multipliers, logic)
  end

  # Build the multiplier list and final text in a single pass.
  # This avoids recalculating the same preview twice when the UI needs
  # both the background frame and the displayed text.
  # @param move [Battle::Move, nil]
  # @param user [PFM::PokemonBattler, nil]
  # @param logic [Battle::Logic, nil]
  # @return [Array<Array<Float>, String>, Array<Array<Float>, nil>, Array(nil, nil)]
  def preview_data_for(move, user, logic)
    multipliers = multipliers_for(move, user, logic)
    return [nil, nil] unless multipliers

    [multipliers, build_text(multipliers, logic)]
  end

  # Tell if the preview should use the compact mixed-values format.
  # This only applies in 3v3 when more than one multiplier is shown.
  # @param multipliers [Array<Float>]
  # @param logic [Battle::Logic, nil]
  # @return [Boolean]
  def compact_variable_text?(multipliers, logic)
    logic&.battle_info&.vs_type == 3 && multipliers.size > 1
  end

  # Return the target values that should appear in the final text.
  # In the 3v3 compact format, x1 can be hidden if SHOW_WHEN_NEUTRAL is false.
  # Hidden targets keep their "?" placeholder.
  # @param multipliers [Array<Float, nil>]
  # @param logic [Battle::Logic, nil]
  # @return [Array<Float, nil>]
  def displayed_multipliers_for(multipliers, logic)
    return multipliers unless compact_variable_text?(multipliers, logic)
    return multipliers if SHOW_WHEN_NEUTRAL

    multipliers.reject { |multiplier| multiplier == 1.0 }
  end

  # Return the background frame index used by the preview spritesheets.
  # Frame 0 is used for values below x1, frame 1 for x1, mixed or partial values,
  # and frame 2 for values above x1.
  # @param multipliers [Array<Float, nil>, nil]
  # @return [Integer]
  def background_frame_index_for(multipliers)
    return 1 unless multipliers

    known_multipliers = multipliers.compact
    return 1 if known_multipliers.empty?
    return 1 if multipliers.any?(&:nil?)
    return 0 if known_multipliers.all? { |multiplier| multiplier < 1 }
    return 2 if known_multipliers.all? { |multiplier| multiplier > 1 }

    1
  end

  #--------------------------------------------------------------------------
  # Display mode 1 method
  #--------------------------------------------------------------------------

  # Build the fixed preview text shown in MoveInfo in display mode 1.
  # Returns nil when the preview should not be shown.
  # @param move [Battle::Move, nil]
  # @param user [PFM::PokemonBattler, nil]
  # @param logic [Battle::Logic, nil]
  # @return [String, nil]
  def text_for(move, user, logic)
    preview_text_for(move, user, logic)
  end

  #--------------------------------------------------------------------------
  # Display mode 2 method
  #--------------------------------------------------------------------------

  # Build the inline preview text shown in each MoveButton in display mode 2.
  # Returns nil when the preview should not be shown.
  # @param move [Battle::Move, nil]
  # @param user [PFM::PokemonBattler, nil]
  # @param logic [Battle::Logic, nil]
  # @return [String, nil]
  def button_text_for(move, user, logic)
    preview_text_for(move, user, logic)
  end
end

module Battle
  class Move
    module EffectivenessPreviewSilentLogPatch
      private

      # Silence move debug data logs while the effectiveness preview is being computed.
      # This keeps the battle debug console readable without affecting normal move logs.
      # @param message [String]
      # @return [String]
      def log_data(message)
        return nil.to_s if $effectiveness_preview_silent_move_logs

        super
      end
    end

    prepend EffectivenessPreviewSilentLogPatch
  end
end

module BattleUI
  class SkillChoice
    #--------------------------------------------------------------------------
    # General UI setup
    #--------------------------------------------------------------------------
    module SkillChoiceEffectivenessPreviewPatch
      # Preview cache generation used to avoid recalculating the same preview
      # every time GenericChoice re-sends the current data to the UI.
      # @return [Integer]
      attr_reader :effectiveness_preview_generation

      # Invalidate the cached previews when the move choice is reset.
      # This keeps the preview accurate between turns while skipping
      # redundant recalculations during cursor movement.
      # @param pokemon [PFM::PokemonBattler]
      def reset(pokemon)
        @effectiveness_preview_generation = @effectiveness_preview_generation.to_i + 1
        super
      end

      private

      # Attach the current SkillChoice to each move button in display mode 2.
      # This allows every button to access the scene logic when refreshing.
      def create_buttons
        super
        return unless EffectivenessPreview::DISPLAY_MODE == 2

        @buttons.each { |button| button.move_choice = self }
      end
    end

    prepend SkillChoiceEffectivenessPreviewPatch

    #--------------------------------------------------------------------------
    # Display mode 1 UI
    #--------------------------------------------------------------------------
    class MoveInfo
      module MoveInfoEffectivenessPreviewPatch
        # Refresh the display mode 1 preview when the selected move actually changes.
        # Redundant UI refreshes during cursor movement are skipped within the same generation.
        # @param pokemon [PFM::PokemonBattler]
        def data=(pokemon)
          move = pokemon&.moveset&.[](@move_choice.index)
          generation = @move_choice.effectiveness_preview_generation.to_i
          super
          return if @effectiveness_preview_move.equal?(move) && @effectiveness_preview_generation == generation

          @effectiveness_preview_move = move
          @effectiveness_preview_generation = generation
          refresh_effectiveness_preview(pokemon)
        end

        # Keep the fixed preview hidden when the parent UI restores child opacity.
        # This happens when opening and closing the move description.
        # @param value [Integer]
        def opacity=(value)
          super
          return unless EffectivenessPreview::DISPLAY_MODE == 1
          return unless @effectiveness_text&.text.to_s.empty?

          @effectiveness_background.opacity = 0 if @effectiveness_background
          @effectiveness_text.opacity = 0 if @effectiveness_text
        end

        private

        # Create the fixed background and text shown by MoveInfo in display mode 1.
        def create_sprites
          super
          return unless EffectivenessPreview::DISPLAY_MODE == 1

          background_x, background_y = *EffectivenessPreview::BACKGROUND_POSITION
          @effectiveness_background = add_sprite(background_x, background_y, EffectivenessPreview::BACKGROUND_IMAGE, 1, 3, type: SpriteSheet)
          @effectiveness_background.opacity = 0
          @effectiveness_text = add_text(
            background_x + 7,
            background_y + 4,
            0,
            nil,
            nil.to_s,
            0,
            color: EffectivenessPreview::TEXT_COLOR
          )
          @effectiveness_text.opacity = 0
          @effectiveness_background.z = @effectiveness_text.z - 1
        end

        # Refresh the move effectiveness preview under the move list.
        # The fixed preview is shown only in display mode 1.
        # @param pokemon [PFM::PokemonBattler, nil]
        def refresh_effectiveness_preview(pokemon)
          return unless EffectivenessPreview::DISPLAY_MODE == 1

          move = pokemon&.moveset&.[](@move_choice.index)
          multipliers, text = EffectivenessPreview.preview_data_for(move, pokemon, @move_choice.scene.logic)
          visible = !text.to_s.empty?
          @effectiveness_background.sy = EffectivenessPreview.background_frame_index_for(multipliers)
          @effectiveness_text.text = text.to_s
          @effectiveness_background.opacity = visible ? 255 : 0
          @effectiveness_text.opacity = visible ? 255 : 0
        end
      end

      prepend MoveInfoEffectivenessPreviewPatch
    end

    #--------------------------------------------------------------------------
    # Display mode 2 UI
    #--------------------------------------------------------------------------
    class MoveButton
      attr_writer :move_choice

      module MoveButtonEffectivenessPreviewPatch
        # Refresh the display mode 2 preview when the button move actually changes.
        # Redundant UI refreshes during cursor movement are skipped within the same generation.
        # @param pokemon [PFM::PokemonBattler]
        def data=(pokemon)
          move = pokemon&.moveset&.[](@index)
          generation = @move_choice&.effectiveness_preview_generation.to_i
          super
          return if @effectiveness_preview_move.equal?(move) && @effectiveness_preview_generation == generation

          @effectiveness_preview_move = move
          @effectiveness_preview_generation = generation
          refresh_effectiveness_preview(pokemon)
        end

        # Keep the mode 2 background fully opaque even when the move button fades.
        # Only the custom background is forced back to full opacity.
        # @param value [Integer]
        def opacity=(value)
          super
          @effectiveness_background.opacity = 255 if @effectiveness_background
        end

        # Keep the mode 2 preview hidden when the parent UI restores child visibility.
        # This happens when opening and closing the move description.
        # @param value [Boolean]
        def visible=(value)
          super
          return unless EffectivenessPreview::DISPLAY_MODE == 2
          return unless @effectiveness_text&.text.to_s.empty?

          @effectiveness_background.visible = false if @effectiveness_background
          @effectiveness_text.visible = false if @effectiveness_text
        end

        # Keep the custom preview above the move button graphics.
        # @param value [Integer]
        def z=(value)
          super
          sync_effectiveness_preview_z
        end

        private

        # Create the display mode 2 background and center the text on it.
        def create_sprites
          super
          return unless EffectivenessPreview::DISPLAY_MODE == 2

          @effectiveness_background = add_sprite(0, 0, EffectivenessPreview::MODE_2_BACKGROUND_IMAGE, 1, 3, type: SpriteSheet)
          offset_x, offset_y = *EffectivenessPreview::MODE_2_BACKGROUND_OFFSET
          background_x = @background.width - @effectiveness_background.width + offset_x
          background_y = @background.height - @effectiveness_background.height + offset_y
          @effectiveness_background.set_position(background_x, background_y)
          with_font(20) do
            line_height = Fonts.line_height(20)
            @effectiveness_text = add_text(
              background_x,
              background_y + (@effectiveness_background.height - line_height) / 2 + 1,
              @effectiveness_background.width,
              line_height,
              nil.to_s,
              1,
              color: EffectivenessPreview::TEXT_COLOR
            )
          end
          sync_effectiveness_preview_z
          @effectiveness_background.visible = false
          @effectiveness_text.draw_shadow = false
          @effectiveness_text.visible = false
        end

        # Refresh the move effectiveness preview in display mode 2.
        # The text is shown inside each move button and hidden when no preview should be shown.
        # @param pokemon [PFM::PokemonBattler, nil]
        def refresh_effectiveness_preview(pokemon)
          return unless EffectivenessPreview::DISPLAY_MODE == 2

          multipliers, text = EffectivenessPreview.preview_data_for(@data, pokemon, @move_choice&.scene&.logic)
          visible = !text.to_s.empty?
          @effectiveness_background.sy = EffectivenessPreview.background_frame_index_for(multipliers)
          @effectiveness_text.text = text.to_s
          @effectiveness_background.visible = visible
          @effectiveness_text.visible = visible
        end

        # Ensure the mode 2 preview stays above the base button background and text.
        # This avoids the custom preview being drawn under the next move button.
        def sync_effectiveness_preview_z
          return unless @effectiveness_background && @effectiveness_text

          @effectiveness_background.z = @background.z + 1
          @effectiveness_text.z = @background.z + 2
        end
      end

      prepend MoveButtonEffectivenessPreviewPatch
    end
  end
end
