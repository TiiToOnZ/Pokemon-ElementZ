# frozen_string_literal: true

module UI
  module Dex
    # Static front sprites on a 320x240 screen. No creature names are requested.
    class ZoneEncounterPage < SpriteStack
      COLUMNS = 4
      ROWS = 2
      PAGE_SIZE = COLUMNS * ROWS
      GRID_X = 8
      GRID_Y = 52
      CELL_WIDTH = 76
      CELL_HEIGHT = 70
      PADDING = 4
      TIME_LABELS = {
        Yuki::Sw::TJN_DayTime => 'Jour', Yuki::Sw::TJN_NightTime => 'Nuit',
        Yuki::Sw::TJN_MorningTime => 'Matin', Yuki::Sw::TJN_SunsetTime => 'Soir'
      }.freeze

      def initialize(viewport)
        super(viewport)
        @title = black_text(8, 2, 304, 16)
        @context = black_text(8, 18, 304, 16)
        @availability = black_text(8, 34, 304, 16)
        @empty = black_text(8, 114, 304, 16)
        @counts = black_text(8, 194, 218, 16, 0)
        @pagination = black_text(230, 194, 82, 16, 2)
        @cells = Array.new(PAGE_SIZE) do |index|
          x = GRID_X + (index % COLUMNS) * CELL_WIDTH
          y = GRID_Y + (index / COLUMNS) * CELL_HEIGHT
          sprite = add_sprite(x + CELL_WIDTH / 2, y + CELL_HEIGHT / 2, NO_INITIAL_IMAGE)
          fallback = black_text(x, y + (CELL_HEIGHT - 16) / 2, CELL_WIDTH, 16)
          fallback.text = '?'
          {sprite: sprite, fallback: fallback}
        end
      end

      def render(snapshot, group, entries, offset, group_index)
        fit_text(@title, snapshot.zone_name)
        fit_text(@context, group ? "#{group_index}/#{snapshot.groups.size} · #{milieu_label(group)}" : 'Ensemble')
        issues = group ? group.issues : snapshot.issues
        availability = case group&.status
                       when :inactive then 'Inactif · conditions non remplies'
                       when :shadowed then 'Masqué · groupe prioritaire'
                       when :active then 'Groupe actif · selon terrain / outil'
                       else ''
                       end
        availability += ' · Données incomplètes' unless issues.empty?
        fit_text(@availability, availability.sub(/^ · /, ''))
        fit_text(@empty, snapshot.zone_key ? 'Aucune rencontre dans cette sélection.' : 'Aucune zone définie pour cette carte.')
        @empty.visible = entries.empty?
        @cells.each_with_index { |cell, index| render_cell(cell, entries[offset + index]) }
        seen = entries.count(&:revealed?)
        caught = entries.count(&:caught)
        page = offset / PAGE_SIZE + 1
        pages = (entries.size + PAGE_SIZE - 1) / PAGE_SIZE
        fit_text(@counts, group ? "Vus #{seen}/#{entries.size}   Capturés #{caught}/#{entries.size}" : "#{entries.size} Pokémon")
        fit_text(@pagination, pages > 1 ? "Page #{page}/#{pages}" : '')
      end

      private

      def black_text(x, y, width, height, align = 1)
        text = add_text(x, y, width, height, '', align, 0, color: 0)
        text.fill_color = Color.new(0, 0, 0, 255)
        text.draw_shadow = false
        return text
      end

      def fit_text(text, value)
        value = value.to_s
        if text.text_width(value) > text.width
          value = value.chop while !value.empty? && text.text_width(value + '…') > text.width
          value += '…'
        end
        text.text = value
      end

      def milieu_label(group)
        label = group.label.gsub('Eau douce', 'Lac')
        data = data_group(group.key)
        return label unless data && data.db_symbol == group.key

        label = "Pêche · #{label}" if PFM::Wild_Battle::FISHING_TOOLS.include?(data.tool)
        times = data.custom_conditions.filter_map do |condition|
          TIME_LABELS[condition.value] if condition.type == :enabled_switch
        end.uniq
        label += " · #{times.join('/')}" unless times.empty?
        return label
      end

      def render_cell(cell, entry)
        sprite = cell[:sprite]
        sprite.visible = cell[:fallback].visible = false
        return unless entry

        # Crucial: do not even resolve the creature resource for an unknown entry.
        bitmap = entry.revealed? ? front_bitmap(entry) : nil
        bitmap ||= question_bitmap
        unless bitmap && bitmap.width > 0 && bitmap.height > 0
          cell[:fallback].visible = true
          return
        end
        sprite.bitmap = bitmap
        sprite.set_origin(bitmap.width / 2.0, bitmap.height / 2.0)
        scale = [1.0, (CELL_WIDTH - 2 * PADDING).fdiv(bitmap.width),
                 (CELL_HEIGHT - 2 * PADDING).fdiv(bitmap.height)].min
        sprite.zoom_x = sprite.zoom_y = scale
        sprite.visible = true
      end

      def front_bitmap(entry)
        # Use the exact Studio form, without constructing/recalibrating a Pokemon.
        filename = PFM::Pokemon.front_filename(entry.specie, entry.form, false, false, false)
        return unless filename && RPG::Cache.poke_front_exist?(filename)

        return RPG::Cache.poke_front(filename)
      rescue StandardError => error
        log_error("Habitat front: #{error.class}: #{error.message}")
        return nil
      end

      def question_bitmap
        return @question_bitmap if @question_loaded

        @question_loaded = true
        @question_bitmap = RPG::Cache.pokedex('000') if RPG::Cache.pokedex_exist?('000')
        return @question_bitmap
      rescue StandardError => error
        log_error("Habitat placeholder: #{error.class}: #{error.message}")
        return nil
      end
    end

    # Keep native control buttons, applying black text only to this scene.
    class ZoneEncounterControls < GenericBase
      class Button < GenericBase::ControlButton
        def initialize(viewport, coords_index, key, **options)
          super(viewport, coords_index, key, **options)
          @text.fill_color = Color.new(0, 0, 0, 255)
          @text.draw_shadow = false
          @text.outline_thickness = 0
        end
      end

      private

      def control_button_class
        return Button
      end
    end
  end
end

module GamePlay
  class ZoneEncounters < BaseCleanUpdate::FrameBalanced
    REFRESH_SECONDS = 0.25
    BUTTON_ACTIONS = %i[action_a action_x action_y action_b].freeze
    INPUT_ACTIONS = {A: :action_a, X: :action_x, Y: :action_y, B: :action_b}.freeze

    def initialize
      super
      @catalog = ElementZ::Habitat::Catalog.new
      @snapshot = nil
      @group_key = nil
      @offset = 0
      @last_refresh = 0
      @last_issues = []
    end

    def update_graphics
      @base_ui.update_background_animation
      refresh_catalog
      return true
    end

    private

    def create_graphics
      @viewport = Viewport.create(:main, 50_000)
      @base_ui = UI::Dex::ZoneEncounterControls.new(@viewport, ['Suivant', 'Précédent', 'Ensemble', 'Retour'])
      @page = UI::Dex::ZoneEncounterPage.new(@viewport)
      Mouse.wheel = 0
      refresh_catalog(force: true)
      Graphics.sort_z
    end

    def refresh_catalog(force: false)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return unless force || now - @last_refresh >= REFRESH_SECONDS

      @last_refresh = now
      snapshot = @catalog.snapshot
      return if !force && snapshot == @snapshot

      if !@snapshot || snapshot.zone_key != @snapshot.zone_key
        @group_key = nil
        @offset = 0
      end
      @snapshot = snapshot
      @group_key = nil unless snapshot.groups.any? { |group| group.key == @group_key }
      issues = (snapshot.issues + snapshot.groups.flat_map(&:issues)).uniq
      issues.each { |issue| log_error("Habitat: #{issue}") } if issues != @last_issues
      @last_issues = issues
      render_page
    end

    def current_group
      @snapshot.groups.find { |group| group.key == @group_key }
    end

    def current_entries
      current_group&.entries || @snapshot.entries
    end

    def render_page
      count = UI::Dex::ZoneEncounterPage::PAGE_SIZE
      max_offset = [((current_entries.size - 1) / count) * count, 0].max
      @offset = @offset.clamp(0, max_offset)
      group = current_group
      group_index = group ? @snapshot.groups.index(group) + 1 : 0
      @page.render(@snapshot, group, current_entries, @offset, group_index)
    end

    def update_inputs
      refresh_catalog
      return false unless automatic_input_update(INPUT_ACTIONS)
      return change_group(-1) if Input.repeat?(:LEFT)
      return change_group(1) if Input.repeat?(:RIGHT)
      return change_page(-1) if Input.repeat?(:UP)
      return change_page(1) if Input.repeat?(:DOWN)

      return true
    end

    def update_mouse(_moved)
      if Mouse.wheel != 0
        direction = Mouse.wheel > 0 ? -1 : 1
        Mouse.wheel = 0
        return change_page(direction)
      end
      return update_mouse_ctrl_buttons(@base_ui.ctrl, BUTTON_ACTIONS)
    end

    def change_group(delta)
      keys = [nil] + @snapshot.groups.map(&:key)
      index = keys.index(@group_key) || 0
      @group_key = keys[(index + delta) % keys.size]
      @offset = 0
      render_page
      return false
    end

    def change_page(delta)
      count = UI::Dex::ZoneEncounterPage::PAGE_SIZE
      pages = [(current_entries.size + count - 1) / count, 1].max
      @offset = ((@offset / count + delta) % pages) * count
      render_page
      return false
    end

    def action_a
      change_group(1)
    end

    def action_x
      change_group(-1)
    end

    def action_y
      @group_key = nil
      @offset = 0
      render_page
    end

    def action_b
      Mouse.wheel = 0
      play_cancel_se
      @running = false
    end
  end
end
