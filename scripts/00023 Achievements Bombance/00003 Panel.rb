# frozen_string_literal: true

module BombanceAchievements
  # Shared presentation. Textures belong to RPG::Cache; only sprites are disposed.
  class Panel < UI::SpriteStack
    NAVY = [21, 35, 64].freeze
    BLUE = [41, 64, 101].freeze
    INK = [36, 46, 68].freeze
    CREAM = [250, 247, 234].freeze
    GOLD = [221, 178, 71].freeze
    PALE = [246, 227, 168].freeze
    MUTED = [110, 118, 134].freeze
    GREEN = [51, 121, 94].freeze

    def opacity=(alpha)
      stack.each do |sprite|
        if sprite.is_a?(Shape)
          color = sprite.color
          color.alpha = alpha
          sprite.color = color
        elsif sprite.is_a?(Text)
          color = sprite.fill_color
          color.alpha = alpha
          sprite.fill_color = color
        else
          sprite.opacity = alpha
        end
      end
    end

    def rect(x, y, width, height, rgb)
      shape = Shape.new(@viewport, :rectangle, width, height)
      shape.set_position(x, y)
      shape.color = Color.new(*rgb)
      push_sprite(shape)
    end

    def text(x, y, width, value, color: INK, size: 3, align: 0)
      value = value.to_s
      result = add_text(x, y, width, 16, value, align, nil, sizeid: size)
      result.fill_color = Color.new(*color)
      result.draw_shadow = false
      if result.text_width(value) > width
        shortened = value.dup
        shortened = shortened[0...-1] while !shortened.empty? && result.text_width(shortened + '…') > width
        result.text = shortened + '…'
      end
      result
    end

    def paragraph(x, y, width, value, lines: 2, color: INK)
      measure = text(x, y, width, '')
      output = ['']
      value.to_s.split.each do |word|
        candidate = [output.last, word].reject(&:empty?).join(' ')
        if measure.text_width(candidate) > width && !output.last.empty? && output.size < lines
          output << word
        else
          output[-1] = candidate
        end
      end
      output.each_with_index { |line, i| text(x, y + 14 * i, width, line, color: color) }
    end

    def icon(x, y, name, cache = :icon)
      with_cache(cache) { add_sprite(x, y, name) }
    end

    def trophy(x, y)
      icon(x, y, 'achievements/trophy', :interface)
    end

    def fragment(x, y, sx, sy, sw, sh, w = sw, h = sh)
      sprite = icon(x, y, 'Message_12', :windowskin)
      sprite.src_rect.set(sx, sy, sw, sh)
      sprite.zoom_x, sprite.zoom_y = w.to_f / sw, h.to_f / sh
      sprite
    end

    def frame(x, y, w, h)
      rect(x + 4, y + 4, w - 8, h - 8, CREAM)
      fragment(x, y, 0, 0, 8, 8)
      fragment(x + w - 8, y, 48, 0, 8, 8)
      fragment(x, y + h - 8, 0, 59, 8, 8)
      fragment(x + w - 8, y + h - 8, 48, 59, 8, 8)
      fragment(x + 8, y, 8, 0, 4, 8, w - 16, 8)
      fragment(x + 8, y + h - 8, 8, 59, 4, 8, w - 16, 8)
      fragment(x, y + 8, 0, 8, 8, 4, 8, h - 16)
      fragment(x + w - 8, y + 8, 48, 8, 8, 4, 8, h - 16)
    end

    def bar(x, y, width, current, target)
      rect(x, y, width, 6, NAVY)
      rect(x + 1, y + 1, width - 2, 4, [219, 225, 225])
      ratio = target.positive? ? (current.to_f / target).clamp(0, 1) : 0
      rect(x + 1, y + 1, [(width - 2) * ratio, 1].max.round, 4, GOLD) if ratio.positive?
    end

    def self.scroll_metrics(height, offset, visible, total)
      return [0, height] if total <= visible
      thumb = [8, (height * visible.to_f / total).round].max
      position = ((height - thumb) * offset.clamp(0, total - visible).to_f / (total - visible)).round
      [position, thumb]
    end

    def scrollbar(x, y, h, offset, visible, total)
      return if total <= visible
      rect(x, y, 6, h, NAVY)
      rect(x + 2, y + 2, 2, h - 4, MUTED)
      position, thumb = self.class.scroll_metrics(h, offset, visible, total)
      rect(x - 1, y + position, 8, thumb, GOLD)
      rect(x, y + position + 1, 6, thumb - 2, PALE)
      # End caps make both limits visible, even when the thumb is in the middle.
      rect(x - 1, y - 2, 8, 1, offset.zero? ? MUTED : GOLD)
      rect(x - 1, y + h + 1, 8, 1, offset + visible >= total ? MUTED : GOLD)
    end

    def selected(x, y, w, h)
      rect(x, y, w, h, PALE)
      rect(x, y, 3, h, GOLD)
    end

    def tier_marker(x, y, status)
      if status == :obtained
        [[0, 3], [1, 4], [2, 5], [3, 4], [4, 3], [5, 2], [6, 1]].each do |dx, dy|
          rect(x + dx, y + dy, 2, 2, GREEN)
        end
      elsif status == :next
        rect(x, y + 1, 3, 8, GOLD)
        rect(x + 3, y + 3, 3, 4, GOLD)
        rect(x + 6, y + 4, 2, 2, GOLD)
      else
        rect(x, y + 1, 8, 8, MUTED)
        rect(x + 1, y + 2, 6, 6, CREAM)
      end
    end

    def reward_icon(x, y, reward)
      if reward[:type] == :item
        icon(x, y, format('%03d', data_item(reward[:id]).id))
      else
        # Money/custom types have no fabricated item icon.
        rect(x + 6, y + 6, 19, 19, GOLD)
        text(x + 6, y + 7, 19, reward[:type] == :money ? '$' : '+', align: 1)
      end
    end

    def reward_name(reward)
      return data_item(reward[:id]).name if reward[:type] == :item
      return 'Argent' if reward[:type] == :money
      REWARD_LABELS.fetch(reward[:type]).call(reward)
    end

    def reward_quantity(reward)
      return "× #{reward.fetch(:quantity, 1)}" if reward[:type] == :item
      return "#{reward[:amount]} $" if reward[:type] == :money
      ''
    end

    def reward_row(x, y, w, entry, obtained)
      if entry[:hidden]
        text(x + 3, y + 2, w - 6, '???', color: MUTED)
        text(x + 3, y + 17, w - 6, 'À obtenir', color: MUTED)
        return
      end
      reward = entry[:reward]
      reward_icon(x, y, reward)
      text(x + 32, y, w - 32, reward_name(reward))
      text(x + 32, y + 14, w - 32, reward_quantity(reward))
      status = entry[:status] == :rewarded ? 'Obtenu' : (obtained ? 'En attente' : 'À obtenir')
      text(x + 3, y + 28, w - 6, status, color: entry[:status] == :rewarded ? GREEN : MUTED)
    end
  end
end
