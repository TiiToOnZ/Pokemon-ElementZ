# frozen_string_literal: true

module BombanceAchievements
  # Small code-drawn panels: no new bitmap assets or shared texture ownership.
  class Panel < UI::SpriteStack
    INK = [35, 53, 73].freeze
    MUTED = [85, 105, 123].freeze
    BLUE = [38, 117, 168].freeze
    GREEN = [42, 135, 102].freeze

    def rect(x, y, width, height, rgb)
      shape = Shape.new(@viewport, :rectangle, width, height)
      shape.set_position(x, y)
      shape.color = Color.new(*rgb)
      push_sprite(shape)
    end

    def text(x, y, width, value, color: INK, size: 3, align: 0)
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

    def paragraph(x, y, width, value, lines: 2)
      measure = text(x, y, width, '')
      words = value.split
      output = ['']
      words.each do |word|
        candidate = [output.last, word].reject(&:empty?).join(' ')
        if measure.text_width(candidate) > width && !output.last.empty? && output.size < lines
          output << word
        else
          output[-1] = candidate
        end
      end
      measure.text = ''
      output.each_with_index { |line, i| text(x, y + 14 * i, width, line, color: MUTED) }
    end

    def bar(x, y, width, current, target)
      rect(x, y, width, 5, [213, 225, 232])
      ratio = target.positive? ? (current.to_f / target).clamp(0, 1) : 0
      rect(x, y, [1, (width * ratio).round].max, 5, GREEN) if ratio.positive?
    end

    # PokemonDS does not contain reliable check/circle glyphs. Draw the symbols.
    def tier_marker(x, y, status)
      if status == :obtained
        [[0, 3], [1, 4], [2, 5], [3, 4], [4, 3], [5, 2], [6, 1]].each do |dx, dy|
          rect(x + dx, y + dy, 2, 2, GREEN)
        end
      else
        circle = Shape.new(@viewport, :circle, 3, 16)
        circle.set_position(x + 1, y + 2)
        circle.color = status == :next ? Color.new(*BLUE) : Color.new(0, 0, 0, 0)
        circle.outline_color = Color.new(*MUTED)
        circle.outline_thickness = status == :next ? 0 : 1
        push_sprite(circle)
      end
    end
  end

  module Notifications
    DURATION = 3.5
    class << self
      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def queue
        @queue ||= []
      end

      def enqueue(event)
        queue << event
      end

      def reset
        detach
        @queue = []
      end

      # A scene switch drops only the currently displayed banner. Queued banners
      # may resume on the map; activating another save clears the whole queue.
      def detach
        @panel&.dispose
        @panel = nil
        @viewport&.dispose unless @viewport&.disposed?
        @viewport = nil
        @owner = @spriteset = nil
        @elapsed = 0
      end

      def safe_to_show?(scene)
        return false unless $scene.equal?(scene) && scene.is_a?(Scene_Map)
        return false if $game_temp.in_battle || $game_temp.player_transferring || $game_temp.transition_processing
        return false if scene.message_processing? || $game_temp.message_window_showing
        spriteset = scene.spriteset
        return false if spriteset.disposed?
        informers = spriteset.instance_variable_get(:@quest_informers)
        return false if informers && !informers.empty?
        map_panel = spriteset.instance_variable_get(:@map_panel)
        return false if map_panel
        true
      end

      def update(scene)
        detach if @owner && (!@owner.equal?(scene) || !@spriteset.equal?(scene.spriteset))
        tick = now
        delta = @last_tick ? (tick - @last_tick).clamp(0, 0.1) : 0
        @last_tick = tick
        unless safe_to_show?(scene)
          @viewport.visible = false if @viewport
          return
        end
        @viewport.visible = true if @viewport
        if @panel
          @elapsed += delta
          detach if @elapsed >= DURATION
        elsif !queue.empty?
          show(scene, queue.shift)
        end
      rescue StandardError => error
        detach
        log_error("BombanceAchievements notification: #{error.class}: #{error.message}")
      end

      def show(scene, event)
        @owner, @spriteset = scene, scene.spriteset
        @viewport = Viewport.create(:main, 19_000)
        @panel = Panel.new(@viewport)
        @panel.rect(7, 9, 306, 70, Panel::BLUE)
        @panel.rect(9, 11, 302, 66, [249, 252, 253])
        if event[:type] == :category
          @panel.text(17, 14, 285, 'NOUVEAUX SUCCÈS !', color: Panel::BLUE)
          @panel.text(17, 33, 285, BombanceAchievements.category_title(event[:category]))
          @panel.text(17, 54, 285, 'Une nouvelle catégorie est disponible.', color: Panel::MUTED)
        else
          id = event.fetch(:achievement)
          definition = DEFINITIONS.fetch(id)
          index = definition[:tiers].index { |tier| tier[:id] == event[:tier] }
          tier = definition[:tiers].fetch(index)
          @panel.text(17, 14, 285, 'SUCCÈS ATTEINT !', color: Panel::BLUE)
          title = BombanceAchievements.achievement_title(id)
          title += " — Palier #{index + 1}" unless BombanceAchievements.unique?(id)
          @panel.text(17, 33, 285, title)
          milestone = if BombanceAchievements.unique?(id)
                        'Obtenu'
                      else
                        format(definition.fetch(:milestone, '%{value} %{unit}'), value: BombanceAchievements.tier_value(tier), unit: definition[:unit])
                      end
          @panel.text(17, 54, 285, "#{milestone} : #{BombanceAchievements.reward_text(id, tier)}")
        end
        @viewport.sort_z
        @elapsed = 0
        BombanceAchievements.safely { Audio.se_play(NOTIFICATION_SE, 70, 110) }
      end
    end
  end
end
