# frozen_string_literal: true

module ApricornTrees
  TYPES = {
    white: {item: :white_apricorn, id: 490, graphic: 'apr_White', ball: :fast_ball},
    green: {item: :green_apricorn, id: 488, graphic: 'apr_Green', ball: :friend_ball},
    blue: {item: :blue_apricorn, id: 486, graphic: 'apr_blue', ball: :lure_ball},
    pink: {item: :pink_apricorn, id: 489, graphic: 'apr_Pink', ball: :love_ball},
    yellow: {item: :yellow_apricorn, id: 487, graphic: 'apr_Yellow', ball: :moon_ball},
    red: {item: :red_apricorn, id: 485, graphic: 'apr_Red', ball: :level_ball},
    black: {item: :black_apricorn, id: 491, graphic: 'apr_Black', ball: :heavy_ball}
  }.transform_values(&:freeze).freeze
  COLORS = TYPES.keys.freeze
  DISPLAY_ORDER = %i[red blue yellow green pink white black].freeze
  ITEM_COLORS = TYPES.each_with_object({}) { |(color, data), result| result[data[:item]] = result[data[:id]] = color }.freeze
  TIMER_SWITCH = 'D'
  READY_FRAME = [2, 0].freeze
  EMPTY_FRAME = [8, 2].freeze
  # [row/direction, column/pattern, seconds]. Entire sequence: 1.24 seconds.
  ANIMATION = [
    [2, 0, 0.08], [2, 1, 0.08], [2, 2, 0.08], [2, 1, 0.08], [2, 0, 0.08],
    [2, 3, 0.06], [4, 0, 0.06], [4, 1, 0.06], [4, 2, 0.06], [4, 3, 0.08],
    [6, 0, 0.08], [6, 1, 0.08], [6, 2, 0.10], [6, 3, 0.08],
    [8, 0, 0.08], [8, 1, 0.08], [8, 2, 0.02]
  ].map(&:freeze).freeze
  TEXTS = {
    fr: {empty: ":[align=center]:\\s[i]Il n'y a plus de Noigrume à récolter pour le moment[WAIT 10].[WAIT 10].[WAIT 10].[WAIT 10]\\s[r]", stored: ":[align=center]:\\s[i]Il est rangé dans la Boîte Noigrume.\\s[r]",
         title: 'BOÎTE NOIGRUME', close: 'Retour', quantity: 'Quantité : %d', makes: 'Pour fabriquer', collection: 'Collection'},
    en: {empty: ':[align=center]:\\s[i]There are no Apricorns to harvest right now[WAIT 10].[WAIT 10].[WAIT 10].[WAIT 10]\\s[r]', stored: ':[align=center]:\\s[i]It was put in the Apricorn Box.\\s[r]',
         title: 'APRICORN BOX', close: 'Back', quantity: 'Quantity: %d', makes: 'Used to make', collection: 'Collection'}
  }.freeze
  ACQUISITION_HOOKS = {}

  class << self
    def color_for(item)
      ITEM_COLORS[item.is_a?(String) ? item.to_sym : item]
    end

    # One explicit declaration in an RMXP comment (108, continued by 408).
    # Read the source page, never the generated runtime list or the event name.
    def color_from_page(page)
      color = nil
      page&.list&.each do |command|
        next unless command.code == 108 || command.code == 408
        line = command.parameters.first.to_s.strip
        next unless line.start_with?('<apricorn_tree')
        match = /\A<apricorn_tree:\s*([a-z_]+)\s*>\z/.match(line)
        unless match && TYPES.key?(match[1].to_sym)
          raise ArgumentError, "Invalid Apricorn declaration: #{line.inspect} (colors: #{COLORS.join(', ')})"
        end
        raise ArgumentError, 'Only one <apricorn_tree: color> declaration is allowed per page' if color
        color = match[1].to_sym
      end
      color
    end

    def text(key)
      language = $options&.language&.to_sym
      (TEXTS[language] || TEXTS[:en]).fetch(key)
    end

    def now
      Time.now
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Same local-wall-minute coordinate as Interpreter#current_time in real mode.
    def real_minute
      time = now
      time.to_i / 60 + time.utc_offset / 60
    end

    def next_day_minute(minute = real_minute)
      (minute / 1440 + 1) * 1440
    end

    def on_acquire(name, &block)
      raise ArgumentError, 'A callback is required' unless block
      ACQUISITION_HOOKS[name] = block
    end

    # Notifications cannot undo a committed acquisition, nor block cleanup.
    def safely_notify
      yield
    rescue StandardError => error
      log_error("Apricorn acquisition hook: #{error.class}: #{error.message}")
    end
  end
end
