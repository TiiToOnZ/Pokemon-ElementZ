# frozen_string_literal: true

module GamePlay
  class BombanceAchievementsScene < BaseCleanUpdate::FrameBalanced
    BA = BombanceAchievements
    attr_reader :screen, :index, :offset, :reward_page

    def initialize
      super
      BA.sync_all
      @screen, @index, @offset, @reward_page = :categories, 0, 0, 0
      @history, @positions, @reward_positions = [], {}, {}
    end

    def entries
      case @screen
      when :categories then BA.visible_categories
      when :category then BA.achievements_in(@category, visible: true)
      when :detail then BA::DEFINITIONS.fetch(@achievement)[:tiers]
      end
    end

    def capacity
      {categories: 2, category: 3, detail: 5}.fetch(@screen)
    end

    def update_inputs
      if Input.trigger?(:B)
        play_cancel_se
        remember_position
        if @history.empty?
          @running = false
        else
          @screen, @category, @achievement = @history.pop
          restore_position
          refresh
        end
      elsif Input.trigger?(:A)
        open_selection
      elsif !entries.empty?
        direction = Input.repeat?(:DOWN) ? 1 : (Input.repeat?(:UP) ? -1 : 0)
        if !direction.zero?
          move_selection(direction)
        elsif @screen == :detail
          direction = Input.repeat?(:RIGHT) ? 1 : (Input.repeat?(:LEFT) ? -1 : 0)
          move_rewards(direction) unless direction.zero?
        end
      end
      true
    end

    def move_selection(direction)
      return if entries.empty?
      remember_reward_page
      @index = (@index + direction) % entries.size
      @offset = @index if @index < @offset
      @offset = @index - capacity + 1 if @index >= @offset + capacity
      restore_reward_page
      play_cursor_se
      refresh
    end

    def reward_pages
      return 1 unless @screen == :detail && entries[@index]
      [(BA.reward_entries(@achievement, entries[@index]).size + 1) / 2, 1].max
    end

    def move_rewards(direction)
      return if reward_pages <= 1
      @reward_page = (@reward_page + direction) % reward_pages
      remember_reward_page
      play_cursor_se
      refresh
    end

    def open_selection
      return if entries.empty? || @screen == :detail
      selected = entries[@index]
      if @screen == :categories && !BA.category_unlocked?(selected)
        play_buzzer_se
        return
      end
      play_decision_se
      remember_position
      @history << [@screen, @category, @achievement]
      if @screen == :categories
        @category, @screen = selected, :category
      else
        @achievement, @screen = selected, :detail
      end
      restore_position
      refresh
    end

    def update_graphics
      true
    end

    def dispose
      return if @ba_disposed
      @ba_disposed = true
      dispose_panels
      super
    end

    private

    def position_key
      [@screen, @screen == :category ? @category : (@screen == :detail ? @achievement : nil)]
    end

    def remember_position
      @positions[position_key] = [@index, @offset]
      remember_reward_page
    end

    def restore_position
      @index, @offset = @positions.fetch(position_key, [0, 0])
      @index = @index.clamp(0, [entries.size - 1, 0].max)
      @offset = @offset.clamp(0, [entries.size - capacity, 0].max)
      restore_reward_page
    end

    def remember_reward_page
      @reward_positions[[@achievement, entries[@index][:id]]] = @reward_page if @screen == :detail && entries[@index]
    end

    def restore_reward_page
      @reward_page = @screen == :detail ? @reward_positions.fetch([@achievement, entries[@index]&.fetch(:id)], 0) : 0
      @reward_page = @reward_page.clamp(0, reward_pages - 1)
    end

    def create_graphics
      create_viewport
      refresh
    end

    def dispose_panels
      @list_panel&.dispose
      @list_panel = nil
      @list_viewport&.dispose
      @list_viewport = nil
      @panel&.dispose
      @panel = nil
    end

    # A real clipped viewport plus bounded row allocation: O(visible rows), even
    # for thousands of configured objectives. Coordinates inside it are local.
    def list_panel(x, y, width, height)
      @list_viewport = Viewport.create(x, y, width, height, @viewport.z + 1)
      @list_panel = BA::Panel.new(@list_viewport)
    end

    def refresh
      return unless @viewport
      dispose_panels
      @panel = BA::Panel.new(@viewport)
      @panel.rect(0, 0, 320, 240, BA::Panel::NAVY)
      @panel.rect(0, 28, 320, 2, BA::Panel::GOLD)
      @panel.trophy(10, 3)
      title = case @screen
              when :categories then 'SUCCÈS'
              when :category then BA.category_title(@category).upcase
              else BA.achievement_title(@achievement).upcase
              end
      @panel.text(40, 7, 200, title, color: BA::Panel::CREAM)
      info = if @screen == :categories
               entries.size > capacity ? "#{@index + 1}/#{entries.size}" : 'Bombance'
             elsif @screen == :category
               "#{BA.percentage(@category)} %"
             else
               BA.unique?(@achievement) ? '' : "#{@index + 1} / #{entries.size}"
             end
      @panel.text(247, 7, 61, info, color: BA::Panel::PALE, align: 2)
      send("draw_#{@screen}")
      @panel.rect(0, 220, 320, 1, BA::Panel::GOLD)
      footer = if @screen == :detail
                 reward_pages > 1 ? '↑↓ Paliers   ←→ Récompenses   X Retour' : (BA.unique?(@achievement) ? 'X Retour' : '↑↓ Paliers     X Retour')
               else
                 '↑↓ Choisir     C Ouvrir     X Retour'
               end
      @panel.text(10, 224, 300, footer, color: BA::Panel::CREAM)
      @viewport.sort_z
      @list_viewport&.sort_z
    end

    def draw_categories
      @panel.frame(8, 35, 304, 44)
      done, total = BA.totals
      @panel.text(20, 42, 222, "Progression globale : #{done} / #{total}")
      @panel.text(251, 42, 48, "#{BA.percentage} %", align: 2)
      @panel.bar(20, 63, 279, done, total)
      width = entries.size > capacity ? 292 : 304
      rows = list_panel(8, 85, width, 92)
      entries.slice(@offset, capacity).each_with_index do |id, row|
        y = row * 49
        rows.frame(0, y, width, 43)
        rows.selected(8, y + 8, 278, 27) if @offset + row == @index
        unlocked = BA.category_unlocked?(id)
        id == :researcher ? rows.icon(12, y + 5, '433') : rows.trophy(11, y + 10)
        rows.text(47, y + 6, 182, BA.category_title(id))
        rows.text(240, y + 6, 47, unlocked ? "#{BA.percentage(id)} %" : 'Fermé', align: 2)
        count, size = BA.totals(id)
        rows.text(47, y + 22, 240, unlocked ? "#{count} paliers obtenus sur #{size}" : 'Catégorie verrouillée', color: BA::Panel::MUTED)
      end
      @panel.scrollbar(302, 87, 87, @offset, capacity, entries.size)
      id = entries[@index]
      if id && (!BA::CATEGORIES[id][:hidden_until_unlocked] || BA.category_unlocked?(id))
        @panel.paragraph(17, 187, 290, BA::CATEGORIES[id][:description].to_s, color: BA::Panel::CREAM)
      end
    end

    def draw_category
      @panel.text(12, 34, 215, 'Succès de la catégorie', color: BA::Panel::CREAM)
      @panel.text(242, 34, 65, entries.empty? ? '0 / 0' : "#{@index + 1} / #{entries.size}", color: BA::Panel::PALE, align: 2)
      @panel.frame(8, 52, 304, 76)
      @panel.frame(8, 133, 304, 83)
      if entries.empty?
        @panel.paragraph(19, 145, 282, 'Aucun succès disponible pour le moment.')
        return
      end
      rows = list_panel(16, 59, 279, 60)
      entries.slice(@offset, capacity).each_with_index do |id, row|
        y = row * 20
        rows.selected(0, y, 279, 20) if @offset + row == @index
        definition = BA::DEFINITIONS[id]
        count = definition[:tiers].count { |tier| BA.obtained?(id, tier) }
        status = BA.unique?(id) ? BA.unique_status(id) : "#{count} / #{definition[:tiers].size}"
        status = '???' if definition[:secret] && !BA.revealed?(id)
        rows.text(10, y + 2, 184, BA.achievement_title(id))
        rows.text(197, y + 2, 73, status, align: 2)
      end
      @panel.scrollbar(301, 59, 60, @offset, capacity, entries.size)
      id = entries[@index]
      definition = BA::DEFINITIONS[id]
      @panel.paragraph(19, 137, 282, BA.achievement_description(id))
      tier = BA.next_tier(id)
      selected = tier || definition[:tiers].last
      return unless selected
      if BA.unique?(id) || (definition[:secret] && !BA.revealed?(id))
        @panel.text(19, 166, 282, BA.unique_status(id))
      else
        target = BA.tier_value(selected)
        @panel.text(19, 166, 282, "Objectif : #{BA.progress(id)} / #{target} #{definition[:unit]}")
        @panel.bar(19, 183, 282, BA.progress(id), target)
      end
      label = tier ? "Prochain : #{BA.reward_text(id, tier)}" : 'Tous les paliers sont obtenus !'
      @panel.text(19, 195, 282, label, color: BA::Panel::GREEN)
    end

    def draw_detail
      id = @achievement
      definition = BA::DEFINITIONS[id]
      @panel.paragraph(12, 34, 298, BA.achievement_description(id), color: BA::Panel::CREAM)
      selected = entries[@index]
      return unless selected
      upcoming = BA.next_tier(id)
      unique = BA.unique?(id)
      secret = definition[:secret] && !BA.revealed?(id)
      done = entries.count { |tier| BA.obtained?(id, tier) }
      target = BA.tier_value(upcoming || entries.last)
      label = if unique || secret
                BA.unique_status(id)
              elsif upcoming
                "#{BA.progress(id)} #{definition[:unit]} / prochain : #{target}"
              else
                "#{BA.progress(id)} #{definition[:unit]} — Terminé !"
              end
      @panel.text(12, 66, 214, label, color: BA::Panel::PALE)
      @panel.text(236, 66, 71, "#{done} / #{entries.size}", color: BA::Panel::CREAM, align: 2) unless unique || secret
      @panel.bar(12, 84, 296, BA.progress(id), target) unless secret || unique
      @panel.frame(8, 96, 169, 120)
      @panel.frame(181, 96, 131, 120)
      rows = list_panel(16, 104, 147, 100)
      entries.slice(@offset, capacity).each_with_index do |tier, row|
        y = row * 20
        rows.selected(0, y, 147, 20) if @offset + row == @index
        obtained = BA.obtained?(id, tier)
        rows.tier_marker(7, y + 5, obtained ? :obtained : (tier == upcoming ? :next : :future))
        label = unique ? BA.unique_status(id) : format('%02d  %s', @offset + row + 1, BA.tier_label(id, tier))
        rows.text(22, y + 2, 122, label)
      end
      @panel.scrollbar(166, 104, 100, @offset, capacity, entries.size)
      heading = unique ? 'Récompenses' : "Palier #{@index + 1}"
      heading += "  #{@reward_page + 1}/#{reward_pages}" if reward_pages > 1
      @panel.text(194, 101, 106, heading)
      BA.reward_entries(id, selected).slice(@reward_page * 2, 2).each_with_index do |entry, i|
        @panel.reward_row(190, 119 + i * 45, 112, entry, BA.obtained?(id, selected))
      end
    end
  end
end
