# frozen_string_literal: true

module GamePlay
  class BombanceAchievementsScene < BaseCleanUpdate::FrameBalanced
    BA = BombanceAchievements
    attr_reader :screen, :index, :offset

    def initialize
      super
      BA.sync_all
      @screen, @index, @offset = :categories, 0, 0
      @history = []
    end

    def entries
      case @screen
      when :categories then BA.visible_categories
      when :category then BA.achievements_in(@category, visible: true)
      when :detail then BA::DEFINITIONS.fetch(@achievement)[:tiers]
      end
    end

    def capacity
      {categories: 5, category: 3, detail: 6}.fetch(@screen)
    end

    def update_inputs
      if Input.trigger?(:B)
        play_cancel_se
        if @history.empty?
          @running = false
        else
          @screen, @index, @offset = @history.pop
          refresh
        end
      elsif Input.trigger?(:A)
        open_selection
      elsif !entries.empty?
        direction = Input.repeat?(:DOWN) ? 1 : (Input.repeat?(:UP) ? -1 : 0)
        move_selection(direction) unless direction.zero?
      end
      true
    end

    def move_selection(direction)
      return if entries.empty?
      @index = (@index + direction) % entries.size
      @offset = @index if @index < @offset
      @offset = @index - capacity + 1 if @index >= @offset + capacity
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
      @history << [@screen, @index, @offset]
      if @screen == :categories
        @category, @screen = selected, :category
      else
        @achievement, @screen = selected, :detail
      end
      @index = @offset = 0
      refresh
    end

    def update_graphics
      true
    end

    def dispose
      return if @ba_disposed
      @ba_disposed = true
      @panel&.dispose
      super
    end

    private

    def create_graphics
      create_viewport
      refresh
    end

    def refresh
      return unless @viewport
      @panel&.dispose
      @panel = BA::Panel.new(@viewport)
      @panel.rect(0, 0, 320, 240, [234, 242, 247])
      @panel.rect(0, 0, 320, 27, BA::Panel::BLUE)
      title = case @screen
              when :categories then 'Succès'
              when :category then BA.category_title(@category)
              else BA.achievement_title(@achievement)
              end
      @panel.text(12, 5, 296, title, color: [255, 255, 255], size: 0)
      send("draw_#{@screen}")
      @panel.rect(0, 221, 320, 19, [218, 230, 238])
      footer = @screen == :detail ? (BA.unique?(@achievement) ? 'B Retour' : '↑↓ Paliers     B Retour') : '↑↓ Choisir     A Ouvrir     B Retour'
      @panel.text(10, 223, 300, footer)
      if entries.size > capacity
        @panel.text(238, 29, 70, "#{@index + 1}/#{entries.size}", align: 2)
      end
      @viewport.sort_z
    end

    def draw_categories
      @panel.text(12, 30, 220, "Progression globale : #{BA.percentage} %")
      done, total = BA.totals
      @panel.bar(12, 48, 296, done, total)
      entries.slice(@offset, capacity).each_with_index do |id, row|
        y = 59 + row * 29
        selected = @offset + row == @index
        @panel.rect(9, y, 302, 27, selected ? [255, 255, 255] : [226, 236, 243])
        @panel.rect(9, y, 3, 27, BA::Panel::BLUE) if selected
        @panel.text(18, y + 5, 170, BA.category_title(id))
        status = BA.category_unlocked?(id) ? "#{BA.percentage(id)} %" : 'Verrouillé'
        @panel.text(193, y + 5, 108, status, color: BA::Panel::MUTED, align: 2)
      end
      id = entries[@index]
      if id && (!BA::CATEGORIES[id][:hidden_until_unlocked] || BA.category_unlocked?(id))
        @panel.text(12, 203, 296, BA::CATEGORIES[id][:description].to_s, color: BA::Panel::MUTED)
      end
    end

    def draw_category
      @panel.text(12, 30, 220, "Progression : #{BA.percentage(@category)} %")
      if entries.empty?
        @panel.paragraph(22, 92, 276, 'Aucun succès disponible pour le moment.')
        return
      end
      entries.slice(@offset, capacity).each_with_index do |id, row|
        y = 52 + row * 25
        selected = @offset + row == @index
        @panel.rect(9, y, 302, 23, selected ? [255, 255, 255] : [226, 236, 243])
        @panel.rect(9, y, 3, 23, BA::Panel::BLUE) if selected
        definition = BA::DEFINITIONS[id]
        count = definition[:tiers].count { |tier| BA.obtained?(id, tier) }
        @panel.text(18, y + 3, 195, BA.achievement_title(id))
        status = BA.unique?(id) ? BA.unique_status(id) : "#{count}/#{definition[:tiers].size} paliers"
        status = '???' if definition[:secret] && !BA.revealed?(id)
        @panel.text(216, y + 3, 85, status, align: 2)
      end
      id = entries[@index]
      definition = BA::DEFINITIONS[id]
      @panel.rect(9, 132, 302, 83, [255, 255, 255])
      @panel.paragraph(17, 134, 286, BA.achievement_description(id))
      tier = BA.next_tier(id)
      if BA.unique?(id) || (definition[:secret] && !BA.revealed?(id))
        @panel.text(17, 169, 285, BA.unique_status(id))
        @panel.text(17, 194, 285, "Récompense : #{BA.reward_text(id, tier || definition[:tiers].last)}", color: BA::Panel::GREEN)
        return
      end
      target = BA.tier_value(tier || definition[:tiers].last)
      @panel.text(17, 163, 285, "#{BA.progress(id)} / #{target} #{definition[:unit]}")
      @panel.bar(17, 182, 286, BA.progress(id), target)
      label = tier ? "Prochain : #{BA.reward_text(id, tier)}" : 'Tous les paliers sont obtenus !'
      @panel.text(17, 194, 285, label, color: BA::Panel::GREEN)
    end

    def draw_detail
      id = @achievement
      definition = BA::DEFINITIONS[id]
      upcoming = BA.next_tier(id)
      if BA.unique?(id)
        tier = definition[:tiers].first
        @panel.paragraph(17, 52, 286, BA.achievement_description(id))
        @panel.tier_marker(17, 106, BA.obtained?(id, tier) ? :obtained : :next)
        @panel.text(34, 102, 269, BA.unique_status(id))
        reward = BA.reward_text(id, tier)
        reward += ' (en attente)' if BA.obtained?(id, tier) && !BA.rewarded?(id, tier)
        @panel.text(17, 137, 286, "Récompense : #{reward}")
        return
      end
      @panel.text(12, 30, 220, 'Paliers et récompenses')
      entries.slice(@offset, capacity).each_with_index do |tier, row|
        y = 52 + row * 22
        @panel.rect(9, y, 302, 21, @offset + row == @index ? [255, 255, 255] : [226, 236, 243])
        obtained = BA.obtained?(id, tier)
        status = obtained ? :obtained : (tier == upcoming ? :next : :future)
        color = obtained ? BA::Panel::GREEN : BA::Panel::INK
        @panel.tier_marker(16, y + 5, status)
        @panel.text(29, y + 2, 110, BA.tier_label(id, tier), color: color)
        reward = BA.reward_text(id, tier)
        reward += ' (en attente)' if obtained && !BA.rewarded?(id, tier)
        @panel.text(143, y + 2, 161, reward, color: color)
      end
      return if definition[:secret] && !BA.revealed?(id)
      target = BA.tier_value(upcoming || definition[:tiers].last)
      @panel.text(12, 187, 296, "Progression : #{BA.progress(id)} / #{target}")
      @panel.bar(12, 207, 296, BA.progress(id), target)
    end
  end
end
