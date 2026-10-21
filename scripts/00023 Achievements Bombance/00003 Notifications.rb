# frozen_string_literal: true

module BombanceAchievements
  module Notifications
    DURATION = 3.5
    PAGE_SECONDS = 2.4
    FADE_SECONDS = 0.18
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
        @event = nil
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
          if @elapsed >= @duration
            detach
          else
            page = [((@elapsed - FADE_SECONDS).clamp(0, @duration) / PAGE_SECONDS).floor, @pages - 1].min
            draw_page(page) if page != @page
            fade = [@elapsed / FADE_SECONDS, (@duration - @elapsed) / FADE_SECONDS, 1].min.clamp(0, 1)
            @panel.opacity = (255 * fade).round
          end
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
        @event = event
        @entries = []
        if event[:type] == :tier
          id = event.fetch(:achievement)
          @tier_index = DEFINITIONS.fetch(id)[:tiers].index { |tier| tier[:id] == event[:tier] }
          @tier = DEFINITIONS[id][:tiers].fetch(@tier_index)
          @entries = BombanceAchievements.reward_entries(id, @tier)
        end
        @pages = [1, (@entries.size + 1) / 2].max
        @duration = [DURATION, @pages * PAGE_SECONDS + 2 * FADE_SECONDS].max
        @elapsed = 0
        draw_page(0)
        @panel.opacity = 0
        BombanceAchievements.safely { Audio.se_play(NOTIFICATION_SE, 70, 110) }
      end

      def draw_page(page)
        @page = page
        @panel&.dispose
        @panel = Panel.new(@viewport)
        @panel.rect(8, 8, 304, 94, Panel::GOLD)
        @panel.rect(10, 10, 300, 90, Panel::NAVY)
        @panel.trophy(20, 16)
        if @event[:type] == :category
          @panel.text(50, 13, 250, 'NOUVEAUX SUCCÈS !', color: Panel::PALE)
          @panel.text(50, 36, 250, BombanceAchievements.category_title(@event[:category]), color: Panel::CREAM)
          @panel.text(20, 70, 282, 'Une nouvelle catégorie est disponible.', color: Panel::CREAM)
        else
          id = @event.fetch(:achievement)
          definition = DEFINITIONS.fetch(id)
          @panel.text(50, 13, 250, 'SUCCÈS DÉBLOQUÉ !', color: Panel::PALE)
          @panel.text(50, 32, 189, BombanceAchievements.achievement_title(id), color: Panel::CREAM)
          unless BombanceAchievements.unique?(id)
            @panel.text(244, 32, 59, "Palier #{@tier_index + 1}", color: Panel::PALE, align: 2)
          end
          milestone = if BombanceAchievements.unique?(id)
                        'Obtenu'
                      else
                        format(definition.fetch(:milestone, '%{value} %{unit}'), value: BombanceAchievements.tier_value(@tier), unit: definition[:unit])
                      end
          @panel.text(50, 48, @pages > 1 ? 210 : 250, milestone, color: Panel::CREAM)
          @panel.text(266, 48, 38, "#{page + 1}/#{@pages}", color: Panel::PALE, align: 2) if @pages > 1
          @entries.slice(page * 2, 2).each_with_index do |entry, i|
            x = 20 + i * 147
            reward = entry[:reward]
            if entry[:hidden]
              @panel.text(x, 73, 138, '???', color: Panel::CREAM)
            else
              @panel.reward_icon(x, 66, reward)
              @panel.text(x + 34, 66, 107, @panel.reward_name(reward), color: Panel::CREAM)
              @panel.text(x + 34, 80, 107, @panel.reward_quantity(reward), color: Panel::PALE)
            end
          end
        end
        @viewport.sort_z
      end
    end
  end
end
