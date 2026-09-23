# frozen_string_literal: true

module UI
  module Dex
    # A small paged list. Hidden entries never request a name or a bitmap.
    class ZoneEncounterPage < SpriteStack
      ROW_COUNT = 5

      def initialize(viewport)
        super(viewport)
        @title = add_text(8, 0, 304, 20, '', 1, color: 10)
        @context = add_text(8, 20, 304, 18, '', 1, color: 10)
        @availability = add_text(8, 38, 304, 16, '', 1, color: 10)
        @empty = add_text(8, 100, 304, 18, '', 1, color: 10)
        @counts = add_text(8, 200, 304, 16, '', 1, color: 10)
        @rows = Array.new(ROW_COUNT) do |index|
          y = 57 + index * 28
          {
            icon: add_sprite(9, y - 1, NO_INITIAL_IMAGE, 1, 1, type: SpriteSheet),
            name: add_text(44, y, 187, 16, '', color: 10),
            status: add_text(234, y, 78, 16, '', 2, color: 10),
            detail: add_text(44, y + 13, 268, 14, '', color: 10)
          }
        end
      end

      def render(snapshot, group, entries, offset, group_index)
        @title.text = snapshot.zone_name
        @context.text = group ? "#{group_index}/#{snapshot.groups.size} : #{group.label}" : 'Ensemble des milieux actifs'
        issues = group ? group.issues : snapshot.issues
        @availability.text = if !issues.empty?
                               'Données incomplètes (voir journal)'
                             elsif group&.status == :inactive
                               'Inactif : conditions non remplies'
                             elsif group&.status == :shadowed
                               'Inactif : un autre groupe est prioritaire'
                             else
                               'Selon le terrain et l’outil indiqués'
                             end
        @empty.text = snapshot.zone_key ? 'Aucune rencontre dans cette sélection.' : 'Aucune zone définie pour cette carte.'
        @empty.visible = entries.empty?
        @rows.each_with_index { |row, index| render_row(row, entries[offset + index]) }
        seen = entries.count(&:revealed?)
        caught = entries.count(&:caught)
        page = entries.empty? ? 0 : offset / ROW_COUNT + 1
        pages = (entries.size + ROW_COUNT - 1) / ROW_COUNT
        @counts.text = "Vus #{seen}/#{entries.size}   Capturés #{caught}/#{entries.size}   Page #{page}/#{pages}"
      end

      private

      def render_row(row, entry)
        row.each_value { |sprite| sprite.visible = !entry.nil? }
        return unless entry

        row[:icon].visible = false
        row[:name].text = '?'
        row[:status].text = ''
        row[:detail].text = entry.habitats.join(', ')
        return unless entry.revealed?

        form = data_creature_form(entry.specie, entry.form)
        row[:name].text = form.name
        row[:status].text = entry.caught ? 'Capturé' : 'Vu'
        row[:detail].text = "F#{entry.form} : #{form.form_name} / #{entry.habitats.join(', ')}"
        render_icon(row[:icon], entry)
      end

      def render_icon(sprite, entry)
        # Resolve the exact Studio form directly, avoiding Pokemon#form= and its
        # automatic recalibration (Meowstic, Deerling, item-dependent forms...).
        filename = PFM::Pokemon.icon_filename(entry.specie, entry.form, false, false, false)
        return unless filename && RPG::Cache.b_icon_exist?(filename)

        bitmap = RPG::Cache.b_icon(filename)
        sprite.nb_x = [bitmap.width / bitmap.height, 1].max
        sprite.bitmap = bitmap
        sprite.visible = true
      rescue StandardError => error
        # A missing/corrupt optional icon must not take down the whole Pokedex.
        sprite.visible = false
        log_error("Habitat icon: #{error.class}: #{error.message}")
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
      @base_ui = UI::GenericBase.new(@viewport, ['Suivant', 'Précédent', 'Ensemble', 'Retour'])
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
      count = UI::Dex::ZoneEncounterPage::ROW_COUNT
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
      count = UI::Dex::ZoneEncounterPage::ROW_COUNT
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
