# Battle Info Stats
#
# Author : Raty
# License : MIT
#
# PSDK plugin : UI shown during the action choice in battle.
# It displays the current stat stages of battlers currently on the field
# and lets the player cycle through them with LEFT / RIGHT.

module BattleInfoStats
  #--------------------------------------------------------------------------
  # General settings
  #--------------------------------------------------------------------------
  # Input symbol used to toggle the overlay from PlayerChoice.
  # Common values include :SELECT, :START, :A, :B, :X, :Y, :L, :R, :LEFT, :RIGHT, :UP and :DOWN.
  # The actual keyboard mapping depends on PSDK Input and can be checked in pokemonsdk/scripts/0 Dependencies/1 LiteRGSS2/001 Input.rb.
  TOGGLE_KEY = :SELECT
  # Panel position on screen: [x, y]
  PANEL_POSITION = [70, 39]
  # Ordered list of displayed battle stages.
  # Each row stores its text id and the battler stage method to read.
  STAGE_ROWS = [
    [[52, 21], :atk_stage], # attack
    [[52, 23], :ats_stage], # attack spe
    [[52, 22], :dfe_stage], # defense
    [[52, 24], :dfs_stage], # special defense
    [[52, 25], :spd_stage], # speed
    [[52, 27], :eva_stage], # evasiveness
    [[52, 26], :acc_stage]  # accuracy
  ].freeze

  #--------------------------------------------------------------------------
  # Assets
  #--------------------------------------------------------------------------
  # Main panel background asset.
  STATS_BOX_IMAGE = 'battle/stats_box'
  # Marker assets used for neutral, raised and lowered stages.
  MARKER_FILES = {
    neutral: 'battle/stats_neutral',
    up: 'battle/stats_up',
    down: 'battle/stats_down'
  }.freeze

  module_function

  #--------------------------------------------------------------------------
  # General methods
  #--------------------------------------------------------------------------

  # Return the battlers currently active on the field.
  # Team reserves are ignored.
  # @param scene [Battle::Scene]
  # @return [Array<PFM::PokemonBattler>]
  def battlers(scene)
    vs_type = scene.logic.battle_info.vs_type
    scene.logic.bank_count.times.flat_map do |bank|
      vs_type.times.filter_map do |position|
        battler = scene.logic.battler(bank, position)
        battler if battler&.alive?
      end
    end
  end

  # Return the battler currently taking the action in PlayerChoice.
  # @param scene [Battle::Scene]
  # @return [PFM::PokemonBattler, nil]
  def current_battler(scene)
    scene.logic.battler(0, scene.player_actions.size)
  rescue StandardError
    nil
  end

  # Return the interface filename used by a marker type.
  # @param type [Symbol]
  # @return [String]
  def marker_filename(type)
    return MARKER_FILES[type]
  end

  # Return the y position of a row from a column origin.
  # @param origin [Array<Integer>]
  # @param index [Integer]
  # @return [Integer]
  def row_y(origin, index)
    return origin[1] + index * 17
  end

  # Return the visual center of a pokeicon.
  # Non-transparent pixels are scanned so the icon content can be centered
  # inside the 32x32 display area.
  # @param filename [String]
  # @param frame_size [Integer]
  # @return [Array<Float>]
  def icon_origin(filename, frame_size)
    @icon_origin_cache ||= {}
    return @icon_origin_cache[filename] if @icon_origin_cache.key?(filename)

    image = icon_image(filename)
    unless image && image.width >= frame_size && image.height >= frame_size
      return @icon_origin_cache[filename] = [frame_size / 2, frame_size / 2]
    end

    min_x = min_y = frame_size
    max_x = max_y = -1
    frame_size.times do |y|
      frame_size.times do |x|
        next if image.get_pixel_alpha(x, y).to_i.zero?

        min_x = x if x < min_x
        min_y = y if y < min_y
        max_x = x if x > max_x
        max_y = y if y > max_y
      end
    end

    @icon_origin_cache[filename] =
      if max_x < min_x || max_y < min_y
        [frame_size / 2, frame_size / 2]
      else
        [(min_x + max_x + 1) / 2.0, (min_y + max_y + 1) / 2.0]
      end
  ensure
    image.dispose if image.is_a?(LiteRGSS::Image) && !image.disposed?
  end

  # Load a pokeicon as an Image through PSDK's virtual directory.
  # This works with loose development assets and packed release assets.
  # @param filename [String]
  # @return [LiteRGSS::Image, nil]
  def icon_image(filename)
    return unless RPG::Cache.b_icon_exist?(filename)

    file_data = RPG::Cache.instance_variable_get(:@b_icon_data)
    return RPG::Cache.load_image({}, filename, RPG::Cache::Pokedex_PokeIcon_Path, file_data, LiteRGSS::Image)
  rescue StandardError
    return nil
  end
end

module BattleUI
  #--------------------------------------------------------------------------
  # Battle Info Stats overlay
  #--------------------------------------------------------------------------
  class BattleInfoStatsOverlay < UI::SpriteStack
    include HideShow
    attr_reader :animation_handler

    def initialize(viewport, scene)
      super(viewport)
      @scene = scene
      @animation_handler = Yuki::Animation::Handler.new
      create_sprites
      self.visible = false
      self.opacity = 0
    end

    # Update the hide/show animation and the inner panel.
    # @return [void]
    def update
      @animation_handler.update
      @panel.update if visible
    end

    # Tell if the hide/show animation finished.
    # @return [Boolean]
    def done?
      return @animation_handler.done?
    end

    # Focus the battler currently acting in PlayerChoice.
    # @return [void]
    def focus_current_battler
      @panel.focus_current_battler
    end

    private

    # Create the full-screen battle background and the stats panel.
    # @return [void]
    def create_sprites
      add_background('battle/background').set_z(50)
      @panel = add_custom_sprite(BattleInfoStatsPanel.new(@viewport, @scene))
    end
  end

  #--------------------------------------------------------------------------
  # Battle Info Stats panel
  #--------------------------------------------------------------------------
  class BattleInfoStatsPanel < UI::SpriteStack
    def initialize(viewport, scene)
      super(viewport, *BattleInfoStats::PANEL_POSITION)
      @scene = scene
      @battlers = []
      @index = 0
      create_sprites
      focus_current_battler
    end

    # Update the battler list and handle previous / next navigation.
    # @return [void]
    def update
      super
      refresh_battlers
      return unless visible

      if Input.trigger?(:LEFT) || Input.trigger?(:L)
        cycle(-1)
      elsif Input.trigger?(:RIGHT) || Input.trigger?(:R)
        cycle(1)
      end
    end

    # Focus the battler currently acting in PlayerChoice.
    # @return [void]
    def focus_current_battler
      refresh_battlers
      battler = BattleInfoStats.current_battler(@scene)
      @index = @battlers.index(battler) || 0
      refresh_display
    end

    private

    # Create the panel UI.
    # @return [void]
    def create_sprites
      add_sprite(0, 0, BattleInfoStats::STATS_BOX_IMAGE)

      add_sprite(
        -16 + 29,
        10 + 2,
        NO_INITIAL_IMAGE,
        :LEFT,
        type: UI::KeyShortcut
      )
      add_sprite(
        121 + 29,
        10 + 2,
        NO_INITIAL_IMAGE,
        :RIGHT,
        type: UI::KeyShortcut
      )

      @name_text = add_text(77, 13, 64, 16, nil.to_s, color: 10)
      @gender = add_sprite(0, 15, NO_INITIAL_IMAGE, type: UI::GenderSprite)
      @icon = add_sprite(53, 21, NO_INITIAL_IMAGE)

      BattleInfoStats::STAGE_ROWS.each_with_index do |(label, _), index|
        add_text(
          11,
          BattleInfoStats.row_y([11, 37], index),
          110,
          16,
          stage_label_text(label),
          color: 0
        )
      end

      # Create every stage marker once, then only swap their bitmap on refresh.
      @markers = BattleInfoStats::STAGE_ROWS.each_with_index.map do |_, row_index|
        6.times.map do |column_index|
          add_sprite(
            113 + column_index * 10,
            BattleInfoStats.row_y([113, 41], row_index),
            BattleInfoStats.marker_filename(:neutral)
          )
        end
      end

      self.z = 51
    end

    # Refresh the active battler list and keep the current selection when possible.
    # @return [void]
    def refresh_battlers
      previous = current_battler
      @battlers = BattleInfoStats.battlers(@scene)
      @index = 0 if @battlers.empty?
      @index = @battlers.index(previous) || @index
      @index %= @battlers.size if @battlers.any?
      refresh_display if previous != current_battler
    end

    # Move to the previous or next battler on the field.
    # @param delta [Integer]
    # @return [void]
    def cycle(delta)
      return if @battlers.size <= 1

      @index = (@index + delta) % @battlers.size
      refresh_display
    end

    # Refresh the displayed battler data.
    # @return [void]
    def refresh_display
      battler = current_battler
      @name_text.text = battler ? battler.given_name.to_s : nil.to_s
      @gender.data = battler
      @gender.x = @name_text.x + @name_text.real_width + 4
      refresh_icon(battler)
      refresh_stage_rows(battler)
    end

    # Refresh every displayed stat stage row.
    # @param battler [PFM::PokemonBattler, nil]
    # @return [void]
    def refresh_stage_rows(battler)
      BattleInfoStats::STAGE_ROWS.each_with_index do |(_, method_name), row_index|
        stage = battler ? battler.send(method_name).to_i : 0
        @markers[row_index].each_with_index do |marker, column_index|
          marker.set_bitmap(stage_marker_filename(stage, column_index), :interface)
        end
      end
    end

    # Return the currently displayed battler.
    # @return [PFM::PokemonBattler, nil]
    def current_battler
      @battlers[@index]
    end

    # Refresh the battler icon.
    # The icon origin is adjusted so the visible content stays centered.
    # @param battler [PFM::PokemonBattler, nil]
    # @return [void]
    def refresh_icon(battler)
      unless (@icon.visible = !battler.nil?)
        @icon.bitmap = nil
        return
      end

      filename = PFM::Pokemon.icon_filename(battler.id, battler.form, battler.female?, battler.shiny?, battler.egg?)
      bitmap = battler.icon
      frame_size = bitmap.height
      @icon.bitmap = bitmap
      @icon.set_rect(0, 0, frame_size, frame_size)
      @icon.set_origin(*BattleInfoStats.icon_origin(filename, frame_size))
    end

    # Return the display text of a stage row label.
    # Array values are resolved through text_get at runtime.
    # @param label [Array<Integer>, String]
    # @return [String]
    def stage_label_text(label)
      return text_get(*label) if label.is_a?(Array)

      label
    end

    # Return the marker asset matching a stage value and marker column.
    # @param stage [Integer]
    # @param column_index [Integer]
    # @return [String]
    def stage_marker_filename(stage, column_index)
      return BattleInfoStats.marker_filename(:up) if stage.positive? && column_index < stage
      return BattleInfoStats.marker_filename(:down) if stage.negative? && column_index < stage.abs

      return BattleInfoStats.marker_filename(:neutral)
    end
  end

  class PlayerChoice
    #--------------------------------------------------------------------------
    # Battle Info Stats PlayerChoice patch
    #--------------------------------------------------------------------------
    module BattleInfoStatsPlayerChoicePatch
      # Dispose the custom overlay with the rest of the UI.
      # @return [void]
      def dispose
        @battle_info_stats_overlay&.dispose
        super
      end

      # Update the overlay when it is visible, otherwise keep the normal
      # PlayerChoice flow and listen for the toggle input.
      # @return [void]
      def update
        @battle_info_stats_overlay&.update
        return update_battle_info_stats_overlay if battle_info_stats_overlay_visible?

        super
        return unless in? && done? && !validated?
        return unless battle_info_stats_toggle_trigger?

        open_battle_info_stats
      end

      # Reset the overlay state when PlayerChoice is rebuilt.
      # @return [void]
      def reset
        super
        @battle_info_stats_overlay&.focus_current_battler
        sync_battle_info_stats_visibility
      end

      # Keep the overlay visibility in sync with PlayerChoice visibility.
      # @param value [Boolean]
      # @return [void]
      def visible=(value)
        super
        sync_battle_info_stats_visibility
      end

      # Keep the overlay visibility in sync when PlayerChoice enters the screen.
      # @return [void]
      def go_in
        super
        sync_battle_info_stats_visibility
      end

      # Keep the overlay visibility in sync when PlayerChoice leaves the screen.
      # @param forced_delta [Numeric, nil]
      # @return [void]
      def go_out(forced_delta = nil)
        super
        sync_battle_info_stats_visibility
      end

      private

      # Create the overlay after the vanilla PlayerChoice UI.
      # @return [void]
      def create_sprites
        super
        create_battle_info_stats_overlay
      end

      # Create the Battle Info Stats overlay.
      # @return [void]
      def create_battle_info_stats_overlay
        @battle_info_stats_overlay = BattleInfoStatsOverlay.new(@viewport, @scene)
        sync_battle_info_stats_visibility
      end

      # Open the overlay with the same fade-in behaviour as move description.
      # @return [void]
      def open_battle_info_stats
        @battle_info_stats_overlay.focus_current_battler
        @battle_info_stats_overlay.show
        play_decision_se
      end

      # Close the overlay with the same fade-out behaviour as move description.
      # @return [void]
      def close_battle_info_stats
        @battle_info_stats_overlay.hide
        play_cancel_se
      end

      # Handle inputs while the overlay is open.
      # Closing waits for the current animation to finish.
      # @return [void]
      def update_battle_info_stats_overlay
        return unless @battle_info_stats_overlay.done?

        return close_battle_info_stats if Input.trigger?(:B) || battle_info_stats_toggle_trigger?
      end

      # Tell if the overlay toggle input has been pressed.
      # @return [Boolean]
      def battle_info_stats_toggle_trigger?
        return Input.trigger?(BattleInfoStats::TOGGLE_KEY)
      end

      # Tell if the overlay is currently visible.
      # @return [Boolean]
      def battle_info_stats_overlay_visible?
        return @battle_info_stats_overlay&.visible
      end

      # Force-hide the overlay when PlayerChoice is no longer active.
      # @return [void]
      def sync_battle_info_stats_visibility
        return unless @battle_info_stats_overlay
        return if in? && @buttons&.first&.visible
        return unless @battle_info_stats_overlay.visible

        @battle_info_stats_overlay.visible = false
        @battle_info_stats_overlay.opacity = 0
      end
    end

    prepend BattleInfoStatsPlayerChoicePatch
  end
end
