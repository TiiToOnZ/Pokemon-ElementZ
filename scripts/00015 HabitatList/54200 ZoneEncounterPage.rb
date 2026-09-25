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

      def self.band_labels(schedule)
        night, evening, day, morning = schedule.map do |hour|
          minutes = ((hour % 1) * 60).round
          minutes.zero? ? format('%02dh', hour.to_i) : format('%02dh%02d', hour.to_i, minutes)
        end
        return {all: 'MATIN / JOUR / SOIR / NUIT',
                day: "Matin : #{morning} - #{day}   Jour : #{day} - #{evening}",
                night: "Soir : #{evening} - #{night}   Nuit : #{night} - #{morning}"}
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
        return snapshot.dup.tap do |copy|
          copy.groups = groups
          # Home is the same configured collection as the environment views,
          # including temporarily inactive/shadowed groups, deduplicated by form.
          copy.entries = groups.flat_map(&:entries).uniq(&:key)
        end
      end
    end

    # Availability organizes the full home catalogue; it never filters it.
    module ZoneEncounterHome
      View = Struct.new(:entries, :categories, :issues, keyword_init: true)
      LABELS = {available: 'DISPONIBLE ACTUELLEMENT', unavailable: 'INDISPONIBLE ACTUELLEMENT'}.freeze

      def self.build(snapshot)
        active_pairs = {}
        snapshot.groups.each do |environment|
          environment.members.each do |member|
            next unless member.status == :active

            member.entries.each { |entry| active_pairs[entry.key] = true }
          end
        end
        available, unavailable = snapshot.entries.partition { |entry| active_pairs.key?(entry.key) }
        categories = snapshot.entries.to_h do |entry|
          [entry.key, active_pairs.key?(entry.key) ? :available : :unavailable]
        end
        return View.new(entries: available + unavailable, categories: categories, issues: snapshot.issues)
      end
    end

    # Category bands occupy vertical space, never a creature slot. Rows may
    # overlap within one category, but never cross a category band.
    class ZoneEncounterLayout
      TOP = 34
      BOTTOM = 212
      BAND_HEIGHT = 10
      BAND_LABEL_HEIGHT = 14 # Preserve the font's line box; only the background shrinks.
      BAND_GAP = 0
      CATEGORY_GAP = 1
      HOME_ROW_GAP = 2
      HOME_MAX_COMPRESSION = 12
      MIN_STEP = 32
      MAX_STEP = 56

      # Pack whole rows and use the least compression that admits the next row.
      # Limited overlap is allowed inside a category, never across its band.
      def self.home_pages(entries, categories, top: TOP)
        rows = entries.chunk { |entry| categories.fetch(entry.key) }.flat_map do |category, members|
          members.each_slice(4).map do |row|
            {category: category, entries: row, height: row.map { |entry| yield(entry) }.max}
          end
        end
        pages, row_offset, offset = [], 0, 0
        while row_offset < rows.size
          chosen = nil
          1.upto([3, rows.size - row_offset].min) do |count|
            plan = nil
            0.upto(HOME_MAX_COMPRESSION) do |compression|
              plan = arrange_home_rows(rows.slice(row_offset, count), compression, top: top)
              break if plan
            end
            break unless plan
            chosen = plan.merge(offset: offset, count: plan[:slots].size, rows: count)
          end
          raise 'Encounter sprite cannot fit in the grid' unless chosen
          pages << chosen
          row_offset += chosen[:rows]
          offset += chosen[:count]
        end
        return pages.empty? ? [{offset: 0, count: 0, slots: [], bands: []}] : pages
      end

      def self.arrange_home_rows(rows, compression, top: TOP)
        y, previous = top, nil
        slots, bands = [], []
        rows.each do |row|
          height = row[:height]
          if previous && previous[:category] == row[:category]
            # Small silhouettes must not collapse into one another either.
            overlap_limit = [previous[:height], height].min / 4
            y += [HOME_ROW_GAP - compression, -overlap_limit].max
          else
            y += CATEGORY_GAP if previous
            bands << {category: row[:category], y: y}
            y += BAND_HEIGHT + BAND_GAP
          end
          return nil if y + height > BOTTOM
          row[:entries].each_with_index do |entry, col|
            slots << {entry: entry, col: col, cy: y + height / 2.0, top: y, bottom: y + height}
          end
          y += height
          previous = row
        end
        return {slots: slots, bands: bands, compression: compression}
      end

      def self.pages(entries, periods = nil, categories: nil, top: TOP, &height)
        categories ||= entries.to_h { |entry| [entry.key, ZoneEncounterPeriods.category(periods.fetch(entry.key))] }
        pages = []
        offset = 0
        while offset < entries.size
          chosen = nil
          1.upto([12, entries.size - offset].min) do |count|
            plan = arrange(entries.slice(offset, count), categories, MIN_STEP, top: top, &height)
            break unless plan
            chosen = plan.merge(offset: offset, count: count)
          end
          raise 'Encounter sprite cannot fit in the grid' unless chosen
          MAX_STEP.downto(MIN_STEP) do |step|
            plan = arrange(entries.slice(offset, chosen[:count]), categories, step, top: top, &height)
            next unless plan
            chosen = chosen.merge(plan)
            break
          end
          pages << chosen
          offset += chosen[:count]
        end
        return pages.empty? ? [{offset: 0, count: 0, slots: [], bands: []}] : pages
      end

      def self.arrange(entries, categories, step, top: TOP)
        y = top
        slots, bands = [], []
        row_count = 0
        entries.chunk { |entry| categories.fetch(entry.key) }.each do |category, members|
          y += CATEGORY_GAP unless slots.empty?
          bands << {category: category, y: y}
          y += BAND_HEIGHT + BAND_GAP
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
      GRID_Y = 34
      CELL_WIDTH = 76
      CELL_HEIGHT = 56
      UNKNOWN_SCALE = 0.83
      BADGE_SCALE = 0.75

      def initialize(viewport)
        super(viewport)
        @title = black_text(84, 2, 152, 16)
        @context = with_font(20) { black_text(84, 18, 152, 16) }
        @availability = with_font(20) { black_text(8, 38, 304, 16) }
        @empty = black_text(8, 114, 304, 16)
        with_font(20) do
          @seen_count = black_text(8, 2, 74, 16, 0)
          @caught_count = black_text(8, 18, 74, 16, 0)
          @pagination = black_text(238, 2, 74, 16, 2)
        end
        @bands = Array.new(3) do
          background = add_sprite(GRID_X, 0, NO_INITIAL_IMAGE)
          icon = add_sprite(28, 0, NO_INITIAL_IMAGE)
          right_icon = add_sprite(260, 0, NO_INITIAL_IMAGE)
          [background, icon, right_icon].each { |s| s.set_origin(0, 0); s.zoom_x = s.zoom_y = 1; s.z = 11_000 }
          icon.z = right_icon.z = 11_001
          label = with_font(20) { black_text(60, 2, 232, ZoneEncounterLayout::BAND_LABEL_HEIGHT, 1) }
          label.z = 11_002
          {background: background, icon: icon, right_icon: right_icon, label: label}
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

      def pages_for(group, entries, home: nil)
        if group
          top = group.issues.empty? ? ZoneEncounterLayout::TOP : 56
          return ZoneEncounterLayout.pages(entries, group.periods, top: top) { |entry| metrics(entry)[:height] }
        end
        top = home.issues.empty? ? ZoneEncounterLayout::TOP : 56
        return ZoneEncounterLayout.home_pages(home.entries, home.categories, top: top) { |entry| metrics(entry)[:height] }
      end

      def dispose
        super
        @band_bitmaps&.each_value(&:dispose)
      end

      def render(snapshot, group, entries, offset, group_index, plans: nil)
        plans ||= pages_for(group, entries, home: group ? nil : ZoneEncounterHome.build(snapshot))
        page_index = plans.rindex { |plan| plan[:offset] <= offset } || 0
        plan = plans[page_index]
        fit_text(@title, snapshot.zone_name)
        fit_text(@context, group ? "#{page_index + 1}/#{plans.size} · #{milieu_label(group)}" : '')
        issues = group ? group.issues : snapshot.issues
        fit_text(@availability, issues.empty? ? '' : 'Données incomplètes')
        fit_text(@empty, snapshot.zone_key ? 'Aucune rencontre dans cette sélection.' : 'Aucune zone définie pour cette carte.')
        @empty.visible = entries.empty?
        @cells.each_with_index { |cell, index| render_cell(cell, plan[:slots][index]) }
        render_bands(plan[:bands])
        Graphics.sort_z
        seen = entries.count(&:revealed?)
        caught = entries.count(&:caught)
        page = page_index + 1
        pages = plans.size
        fit_text(@seen_count, "Vus #{seen}/#{entries.size}")
        fit_text(@caught_count, "Capturés #{caught}/#{entries.size}")
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
        labels = ZoneEncounterPeriods.band_labels(ZoneEncounterPeriods.schedule)
        @bands.each_with_index do |elements, index|
          elements.each_value { |element| element.visible = false }
          next unless (band = bands[index])
          category, y = band.values_at(:category, :y)
          label_y = y + (ZoneEncounterLayout::BAND_HEIGHT - ZoneEncounterLayout::BAND_LABEL_HEIGHT) / 2
          elements[:background].bitmap = band_bitmap(category)
          elements[:background].y = y
          if ZoneEncounterHome::LABELS.key?(category)
            elements[:label].set_position(GRID_X, label_y)
            elements[:label].width = COLUMNS * CELL_WIDTH
            fit_text(elements[:label], ZoneEncounterHome::LABELS.fetch(category))
            elements[:background].visible = elements[:label].visible = true
            next
          end
          elements[:icon].bitmap = time_bitmap(category == :night ? 'nighttime' : 'daytime')
          elements[:right_icon].bitmap = time_bitmap('nighttime') if category == :all
          [elements[:icon], elements[:right_icon]].each_with_index do |icon, side|
            icon.set_origin(16, 9)
            icon.zoom_x = icon.zoom_y = ZoneEncounterLayout::BAND_HEIGHT.fdiv(18)
            icon.set_position(side.zero? ? 44 : 276, y + ZoneEncounterLayout::BAND_HEIGHT / 2)
          end
          elements[:label].x = 60
          elements[:label].width = category == :all ? 200 : 232
          fit_text(elements[:label], labels.fetch(category))
          elements[:label].y = label_y
          elements.each_value { |element| element.visible = true }
          elements[:right_icon].visible = category == :all
        end
      end

      def band_bitmap(category)
        @band_bitmaps ||= {}
        return @band_bitmaps[category] if @band_bitmaps.key?(category)
        stops = {all: [[205, 238, 174], [147, 207, 134], [86, 160, 117]],
                 available: [[205, 238, 174], [147, 207, 134], [86, 160, 117]],
                 unavailable: [[222, 228, 234], [184, 198, 210], [143, 164, 183]],
                 day: [[255, 235, 168], [243, 193, 120], [224, 138, 105]],
                 night: [[171, 213, 237], [128, 166, 204], [70, 99, 153]]}.fetch(category)
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
      # Native KeyShortcut resolves physical B/X via the project's bindings:
      # virtual Y = keyboard B (home), virtual B = keyboard X (back).
      KEYS = %i[RIGHT DOWN Y B].freeze
      LABELS = ['Suivant', 'Suivant', 'Accueil', 'Retour'].freeze
      ARROW_SKIN = 'Pause2'
      ARROW_RECT = [0, 0, 10, 12].freeze

      class Button < GenericBase::ControlButton
        def initialize(viewport, coords_index, key, **options)
          super(viewport, coords_index, key, **options)
          @text.fill_color = Color.new(0, 0, 0, 255)
          @text.draw_shadow = false
          @text.outline_thickness = 0
          return unless coords_index < 2

          @key_button.visible = false
          arrow = add_sprite(8, 9, NO_INITIAL_IMAGE)
          arrow.bitmap = RPG::Cache.windowskin(ARROW_SKIN)
          arrow.src_rect.set(*ARROW_RECT)
          arrow.set_origin(5, 6)
          arrow.angle = coords_index.zero? ? 90 : 0
          arrow.z = 502
        end

        def visible=(value)
          super
          # GenericBase reapplies visibility when setting labels/showing its bar.
          @key_button.visible = false if @coords_index && @coords_index < 2
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
    BUTTON_ACTIONS = %i[next_environment next_page action_y action_b].freeze
    INPUT_ACTIONS = {Y: :action_y, B: :action_b}.freeze

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
      @base_ui = UI::Dex::ZoneEncounterControls.new(@viewport, UI::Dex::ZoneEncounterControls::LABELS, UI::Dex::ZoneEncounterControls::KEYS)
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
      @home = UI::Dex::ZoneEncounterHome.build(@snapshot)
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
      current_group&.entries || @home.entries
    end

    def render_page
      group = current_group
      @pages = @page.pages_for(group, current_entries, home: @home)
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

    def next_environment
      change_group(1)
    end

    def next_page
      change_page(1)
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
