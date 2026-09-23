# frozen_string_literal: true

module UI
  module Dex
    # Temporal preference, not an exhaustive promise of current availability.
    module ZoneEncounterPeriods
      SWITCH_BITS = {Yuki::Sw::TJN_MorningTime => 1, Yuki::Sw::TJN_DayTime => 2,
                     Yuki::Sw::TJN_SunsetTime => 4, Yuki::Sw::TJN_NightTime => 8}.freeze

      def self.for_group(data)
        # Project only the temporal restrictions. Other prerequisites remain in
        # the catalogue; here they are assumed fulfilled, never mapped to a time.
        data.custom_conditions.reduce(15) do |mask, condition|
          allowed = condition.type == :enabled_switch ? SWITCH_BITS.fetch(condition.value, 15) : 15
          condition.relation_with_previous_condition == :OR ? mask | allowed : mask & allowed
        end
      end

      def self.icons(mask)
        day = (mask & 1) + ((mask >> 1) & 1)
        night = ((mask >> 2) & 1) + ((mask >> 3) & 1)
        return [] if day + night == 0
        return %w[daytime nighttime] if day == night

        return day > night ? ['daytime'] : ['nighttime']
      end

      def self.schedule
        # current_time_set is private in 26.60. Read the public setting and
        # configuration constants, preserving the engine's tone-only fallback.
        key = PFM.game_state.tint_time_set
        return (Yuki::TJN::TIME_SETS[key] || Yuki::TJN::TIME).dup
      end

      def self.category(mask)
        return :all if mask == 15

        return icons(mask).first == 'daytime' ? :day : :night
      end

      def self.legend(schedule)
        night, evening, day, morning = schedule.map do |hour|
          minutes = ((hour % 1) * 60).round
          minutes.zero? ? format('%02dh', hour.to_i) : format('%02dh%02d', hour.to_i, minutes)
        end
        return ["Matin/Jour #{morning}–#{day}–#{evening}", "Soir/Nuit #{evening}–#{night}–#{morning}"]
      end
    end

    # One presentation view per environment/method, regardless of conditions.
    module ZoneEncounterEnvironments
      View = Struct.new(:key, :label, :status, :entries, :issues, :periods, :members, keyword_init: true)

      def self.build(snapshot)
        groups = snapshot.groups.group_by do |view|
          data = data_group(view.key)
          next [view.key] unless data && data.db_symbol == view.key

          [data.system_tag, data.tool]
        end.values.map do |members|
          first = members.first
          view = View.new(key: first.key, label: first.label, members: members, periods: {})
          data = data_group(view.key)
          if data && data.db_symbol == view.key
            terrain = ElementZ::Habitat::TERRAIN_NAMES.fetch(data.system_tag, data.system_tag.to_s)
            tool = ElementZ::Habitat::TOOL_NAMES.fetch(data.tool, data.tool&.to_s)
            view.label = tool ? "#{tool} / #{terrain}" : terrain
          end
          view.entries = members.flat_map(&:entries).uniq(&:key)
          view.issues = members.flat_map(&:issues).uniq
          view.status = members.map(&:status).uniq.size == 1 ? first.status : :mixed
          members.each do |member|
            raw = data_group(member.key)
            mask = raw && raw.db_symbol == member.key ? ZoneEncounterPeriods.for_group(raw) : 0
            member.entries.each { |entry| view.periods[entry.key] = view.periods.fetch(entry.key, 0) | mask }
          end
          view.entries = view.entries.each_with_index.sort_by do |entry, index|
            [%i[all day night].index(ZoneEncounterPeriods.category(view.periods[entry.key])), index]
          end.map(&:first)
          view
        end
        return snapshot.dup.tap { |copy| copy.groups = groups }
      end
    end

    # Category bands occupy vertical space, never a creature slot. Rows may
    # overlap within one category, but never cross a category band.
    class ZoneEncounterLayout
      TOP = 32
      BOTTOM = 192
      BAND_HEIGHT = 18
      MIN_STEP = 32
      MAX_STEP = 46

      def self.pages(entries, periods, top: TOP, &height)
        pages = []
        offset = 0
        while offset < entries.size
          chosen = nil
          1.upto([12, entries.size - offset].min) do |count|
            plan = arrange(entries.slice(offset, count), periods, MIN_STEP, top: top, &height)
            break unless plan
            chosen = plan.merge(offset: offset, count: count)
          end
          raise 'Encounter sprite cannot fit in the grid' unless chosen
          MAX_STEP.downto(MIN_STEP) do |step|
            plan = arrange(entries.slice(offset, chosen[:count]), periods, step, top: top, &height)
            next unless plan
            chosen = chosen.merge(plan)
            break
          end
          pages << chosen
          offset += chosen[:count]
        end
        return pages.empty? ? [{offset: 0, count: 0, slots: [], bands: []}] : pages
      end

      def self.arrange(entries, periods, step, top: TOP)
        y = top
        slots, bands = [], []
        row_count = 0
        entries.chunk { |entry| ZoneEncounterPeriods.category(periods.fetch(entry.key)) }.each do |category, members|
          y += 4 unless slots.empty?
          unless category == :all
            bands << {category: category, y: y}
            y += BAND_HEIGHT + 2
          end
          rows = members.each_slice(4).to_a
          row_count += rows.size
          return nil if row_count > 3
          heights = rows.map { |row| row.map { |entry| yield(entry) }.max }
          top = heights.each_with_index.map { |h, i| i * step - h / 2.0 }.min
          bottom = heights.each_with_index.map { |h, i| i * step + h / 2.0 }.max
          section_height = (bottom - top).ceil
          return nil if y + section_height > BOTTOM
          rows.each_with_index do |row, i|
            row.each_with_index do |entry, col|
              slots << {entry: entry, col: col, cy: y + i * step - top, top: y, bottom: y + section_height}
            end
          end
          y += section_height
        end
        return {slots: slots, bands: bands}
      end
    end

    # Static front sprites on a 320x240 screen. No creature names are requested.
    class ZoneEncounterPage < SpriteStack
      COLUMNS = 4
      ROWS = 3
      PAGE_SIZE = COLUMNS * ROWS
      GRID_X = 8
      GRID_Y = 52
      CELL_WIDTH = 76
      CELL_HEIGHT = 46
      GRID_BOTTOM = 192
      UNKNOWN_SCALE = 0.83
      BADGE_SCALE = 0.75

      def initialize(viewport)
        super(viewport)
        @title = black_text(8, 2, 304, 16)
        @context = black_text(8, 18, 304, 16)
        @availability = black_text(8, 34, 304, 16)
        @empty = black_text(8, 114, 304, 16)
        @counts = black_text(8, 194, 218, 16, 0)
        @pagination = black_text(230, 194, 82, 16, 2)
        @legend_icons = [add_sprite(8, 32, NO_INITIAL_IMAGE), add_sprite(164, 32, NO_INITIAL_IMAGE)]
        @legend_texts = with_font(20) { [black_text(40, 34, 116, 16, 0), black_text(196, 34, 116, 16, 0)] }
        @bands = Array.new(2) do
          background = add_sprite(GRID_X, 0, NO_INITIAL_IMAGE)
          icon = add_sprite(108, 0, NO_INITIAL_IMAGE)
          [background, icon].each { |s| s.set_origin(0, 0); s.zoom_x = s.zoom_y = 1; s.z = 11_000 }
          label = with_font(20) { black_text(140, 2, 100, 18, 0) }
          label.z = 11_001
          {background: background, icon: icon, label: label}
        end
        @cells = Array.new(PAGE_SIZE) do |index|
          x = GRID_X + (index % COLUMNS) * CELL_WIDTH
          y = GRID_Y + (index / COLUMNS) * CELL_HEIGHT
          sprite = add_sprite(x + CELL_WIDTH / 2, y + CELL_HEIGHT / 2, NO_INITIAL_IMAGE)
          fallback = black_text(x, y + (CELL_HEIGHT - 16) / 2, CELL_WIDTH, 16)
          fallback.text = '?'
          badge = add_sprite(x + CELL_WIDTH - 20, y + CELL_HEIGHT - 16, NO_INITIAL_IMAGE)
          badge.set_origin(0, 0)
          badge.zoom_x = badge.zoom_y = BADGE_SCALE
          badge.z = 11_000
          {sprite: sprite, fallback: fallback, badge: badge,
           x: x, center_x: x + CELL_WIDTH / 2, center_y: y + CELL_HEIGHT / 2}
        end
      end

      def pages_for(group, entries)
        if group
          top = group.issues.empty? ? ZoneEncounterLayout::TOP : GRID_Y
          return ZoneEncounterLayout.pages(entries, group.periods, top: top) { |entry| metrics(entry)[:height] }
        end
        slices = entries.each_slice(PAGE_SIZE).to_a
        slices = [[]] if slices.empty?
        return slices.each_with_index.map do |slice, index|
          slots = slice.each_with_index.map do |entry, i|
            {entry: entry, col: i % COLUMNS, cy: GRID_Y + (i / COLUMNS) * CELL_HEIGHT + CELL_HEIGHT / 2,
             top: GRID_Y, bottom: GRID_BOTTOM}
          end
          {offset: index * PAGE_SIZE, count: slice.size, slots: slots, bands: []}
        end
      end

      def dispose
        super
        @band_bitmaps&.each_value(&:dispose)
      end

      def render(snapshot, group, entries, offset, group_index, plans: nil)
        plans ||= pages_for(group, entries)
        page_index = plans.rindex { |plan| plan[:offset] <= offset } || 0
        plan = plans[page_index]
        fit_text(@title, snapshot.zone_name)
        fit_text(@context, group ? "#{group_index}/#{snapshot.groups.size} · #{milieu_label(group)}" : 'Ensemble')
        issues = group ? group.issues : snapshot.issues
        fit_text(@availability, issues.empty? ? '' : 'Données incomplètes')
        render_legend(!group && issues.empty?)
        fit_text(@empty, snapshot.zone_key ? 'Aucune rencontre dans cette sélection.' : 'Aucune zone définie pour cette carte.')
        @empty.visible = entries.empty?
        @cells.each_with_index { |cell, index| render_cell(cell, plan[:slots][index]) }
        render_bands(plan[:bands])
        Graphics.sort_z
        seen = entries.count(&:revealed?)
        caught = entries.count(&:caught)
        page = page_index + 1
        pages = plans.size
        fit_text(@counts, "Vus #{seen}/#{entries.size} · Capturés #{caught}/#{entries.size}")
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
        return label
      end

      def metrics(entry)
        @metrics ||= {}
        key = [entry.key, !!entry.revealed?]
        return @metrics[key] if @metrics.key?(key)
        bitmap = entry.revealed? ? front_bitmap(entry) : nil
        scale = bitmap ? 1 : UNKNOWN_SCALE
        bitmap ||= question_bitmap
        bounds = bitmap ? visible_bounds(bitmap) : [0, 0, 16, 16]
        return @metrics[key] = {bitmap: bitmap, bounds: bounds, scale: scale,
                               width: (bounds[2] * scale).ceil, height: (bounds[3] * scale).ceil}
      end

      def render_cell(cell, slot)
        sprite = cell[:sprite]
        sprite.visible = cell[:fallback].visible = cell[:badge].visible = false
        return unless slot
        entry = slot[:entry]
        cell[:center_x] = GRID_X + slot[:col] * CELL_WIDTH + CELL_WIDTH / 2
        cell[:center_y] = slot[:cy]

        # Crucial: do not even resolve the creature resource for an unknown entry.
        info = metrics(entry)
        bitmap = info[:bitmap]
        unless bitmap && bitmap.width > 0 && bitmap.height > 0
          cell[:fallback].visible = true
          cell[:fallback].set_position(cell[:center_x] - CELL_WIDTH / 2, slot[:cy] - 8)
          return
        end
        sprite.bitmap = bitmap
        left, top = info[:bounds]
        width, height = info.values_at(:width, :height)
        # Ignore transparent padding for alignment. Real creature fronts stay 1:1.
        sprite.set_origin(left, top)
        x = (cell[:center_x] - width / 2).clamp(GRID_X, GRID_X + COLUMNS * CELL_WIDTH - width)
        y = (cell[:center_y] - height / 2.0).round.clamp(slot[:top], slot[:bottom] - height)
        sprite.set_position(x, y)
        sprite.zoom_x = sprite.zoom_y = info[:scale]
        # Large silhouettes sit behind small ones when rows overlap.
        sprite.z = 10_000 - width * height
        sprite.visible = true
        cell[:badge].set_position((x + width - 2).clamp(GRID_X, 300),
                                 (y - 4).clamp(slot[:top], slot[:bottom] - 12))
        if entry.caught && (badge = capture_bitmap)
          cell[:badge].bitmap = badge
          cell[:badge].visible = true
        end
      end

      def render_bands(bands)
        @bands.each_with_index do |elements, index|
          elements.each_value { |element| element.visible = false }
          next unless (band = bands[index])
          category, y = band.values_at(:category, :y)
          elements[:background].bitmap = band_bitmap(category)
          elements[:background].y = y
          elements[:icon].bitmap = time_bitmap(category == :day ? 'daytime' : 'nighttime')
          elements[:icon].y = y
          elements[:label].text = category == :day ? 'MATIN / JOUR' : 'SOIR / NUIT'
          elements[:label].y = y
          elements.each_value { |element| element.visible = true }
        end
      end

      def band_bitmap(category)
        @band_bitmaps ||= {}
        return @band_bitmaps[category] if @band_bitmaps.key?(category)
        stops = category == :day ? [[255, 235, 168], [243, 193, 120], [224, 138, 105]] :
                                  [[171, 213, 237], [128, 166, 204], [70, 99, 153]]
        image = Image.new(304, ZoneEncounterLayout::BAND_HEIGHT)
        304.times do |x|
          t = x.fdiv(303) * 2
          segment = [t.floor, 1].min
          color = stops[segment].zip(stops[segment + 1]).map { |a, b| (a + (b - a) * (t - segment)).round }
          image.fill_rect(x, 0, 1, ZoneEncounterLayout::BAND_HEIGHT, Color.new(*color, 255))
        end
        return @band_bitmaps[category] = Texture.new(image.to_png, true)
      ensure
        image&.dispose
      end

      def time_bitmap(name)
        @time_bitmaps ||= {}
        return @time_bitmaps[name] if @time_bitmaps.key?(name)

        return @time_bitmaps[name] = RPG::Cache.pokedex_exist?(name) ? RPG::Cache.pokedex(name) : nil
      rescue StandardError => error
        log_error("Habitat time: #{error.class}: #{error.message}")
        return @time_bitmaps[name] = nil
      end

      def render_legend(visible)
        labels = ZoneEncounterPeriods.legend(ZoneEncounterPeriods.schedule)
        %w[daytime nighttime].each_with_index do |name, index|
          icon = @legend_icons[index]
          icon.visible = false
          if visible
            icon.bitmap = time_bitmap(name)
            icon.set_origin(0, 0)
            icon.zoom_x = icon.zoom_y = 1
            icon.visible = !icon.bitmap.nil?
          end
          @legend_texts[index].visible = visible
          fit_text(@legend_texts[index], labels[index])
        end
      end

      def visible_bounds(bitmap)
        @bounds ||= {}
        return @bounds[bitmap] if @bounds.key?(bitmap)

        image = Image.new(bitmap.to_png, true)
        left, top, right, bottom = bitmap.width, bitmap.height, -1, -1
        bitmap.height.times do |y|
          bitmap.width.times do |x|
            next if image.get_pixel_alpha(x, y).zero?

            left = x if x < left
            top = y if y < top
            right = x if x > right
            bottom = y if y > bottom
          end
        end
        return @bounds[bitmap] = right < 0 ? [0, 0, 1, 1] : [left, top, right - left + 1, bottom - top + 1]
      ensure
        image&.dispose
      end

      def capture_bitmap
        return @capture_bitmap if @capture_loaded

        @capture_loaded = true
        @capture_bitmap = RPG::Cache.pokedex('Catch') if RPG::Cache.pokedex_exist?('Catch')
        return @capture_bitmap
      rescue StandardError => error
        log_error("Habitat capture: #{error.class}: #{error.message}")
        return nil
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
        @question_bitmap = RPG::Cache.poke_front('000') if RPG::Cache.poke_front_exist?('000')
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
      schedule = UI::Dex::ZoneEncounterPeriods.schedule
      return if !force && snapshot == @catalog_snapshot && schedule == @schedule

      if !@snapshot || snapshot.zone_key != @snapshot.zone_key
        @group_key = nil
        @offset = 0
      end
      @catalog_snapshot = snapshot
      @schedule = schedule
      @snapshot = UI::Dex::ZoneEncounterEnvironments.build(snapshot)
      @group_key = nil unless @snapshot.groups.any? { |group| group.key == @group_key }
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
      group = current_group
      @pages = @page.pages_for(group, current_entries)
      page_index = @pages.rindex { |plan| plan[:offset] <= @offset } || 0
      @offset = @pages[page_index][:offset]
      group_index = group ? @snapshot.groups.index(group) + 1 : 0
      @page.render(@snapshot, group, current_entries, @offset, group_index, plans: @pages)
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
      index = @pages.index { |plan| plan[:offset] == @offset } || 0
      @offset = @pages[(index + delta) % @pages.size][:offset]
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
