# frozen_string_literal: true

module ApricornTrees
  # Use the existing timer writer, always in real time even if a cutscene changes
  # TJN's virtual/real switch. Never change TJN switches or other event timers.
  class RealClockInterpreter < Interpreter
    def initialize(minute = ApricornTrees.real_minute)
      super()
      @apricorn_minute = minute
    end

    def current_time
      @apricorn_minute
    end
  end

  class ApricornTree
    attr_reader :event, :color, :key, :page

    def initialize(event)
      @event = event
      @color = event.apricorn_color
      raise ArgumentError, 'Not an Apricorn tree' unless @color
      @key = [event.original_map, event.original_id].freeze
      @page = event.apricorn_page
    end

    # A new page can reuse the same color: its identity still must match.
    # Read the declaration too, so edits without a refresh cannot award a fruit.
    def current?
      $game_map.events[event.id].equal?(event) && !event.erased && event.activated? &&
        event.apricorn_page.equal?(page) && [event.original_map, event.original_id] == key &&
        event.apricorn_color == color && ApricornTrees.color_from_page(page) == color
    rescue ArgumentError
      false
    end

    def timer
      PFM.game_state.user_data.dig(:tjn_events, *key)
    end

    def available?
      data = timer
      !data || data.first <= ApricornTrees.real_minute
    end

    # No yield between the persistent cooldown and inventory mutation.
    # The timer is authoritative; the local D switch is only its native signal.
    def harvest!
      return false unless available?
      old_timer = timer&.dup
      switch_key = [*key, TIMER_SWITCH]
      old_switch = $game_self_switches[switch_key]
      minute = ApricornTrees.real_minute
      RealClockInterpreter.new(minute).trigger_event_in(ApricornTrees.next_day_minute(minute) - minute,
                                                       TIMER_SWITCH, key[1], key[0])
      PFM.game_state.apricorns.add(color, 1, source: :harvest)
      true
    rescue StandardError
      records = PFM.game_state.user_data.dig(:tjn_events, key[0])
      old_timer ? records[key[1]] = old_timer : records&.delete(key[1])
      $game_self_switches[switch_key] = old_switch if switch_key
      raise
    end

    def refresh
      data = timer
      if data && available?
        PFM.game_state.user_data[:tjn_events][key[0]].delete(key[1])
        $game_self_switches[[*key, TIMER_SWITCH]] = true
      end
      event.apricorn_set_frame(*(available? ? READY_FRAME : EMPTY_FRAME))
    end
  end

  class << self
    attr_reader :session

    def begin_session(tree)
      return nil if @session || !tree.current? || !tree.available?
      @session = {tree: tree, player: $game_player, state: PFM.game_state, start: monotonic}
    end

    def session_valid?(token)
      @session.equal?(token) && PFM.game_state.equal?(token[:state]) &&
        $game_player.equal?(token[:player]) && token[:tree].current? &&
        !$game_temp.player_transferring && monotonic - token[:start] < 5.0
    end

    def cancel_session
      token = @session
      @session = nil
      return unless token
      token[:player].leave_apricorn_state
      token[:tree].event.apricorn_animating = false
      token[:tree].refresh if token[:state].equal?(PFM.game_state) && token[:tree].current?
    end

    def finish_session(token)
      cancel_session if @session.equal?(token)
    end
  end
end
