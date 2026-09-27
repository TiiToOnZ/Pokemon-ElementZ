# frozen_string_literal: true

module ApricornTrees
  module MapRefresh
    def update(*args)
      # Native event creation already sets the correct graphic before rendering.
      # Check visible original-map identities at minute boundaries, including
      # MapLinker neighbours that TJN's current-map-only scan would miss.
      minute = ApricornTrees.real_minute
      if @apricorn_last_minute != minute
        @apricorn_last_minute = minute
        @events.each_value do |event|
          next unless event.apricorn_color && event.activated? && !event.erased && !event.apricorn_animating
          ApricornTree.new(event).refresh
        end
      end
      token = ApricornTrees.session
      ApricornTrees.cancel_session if token && !ApricornTrees.session_valid?(token)
      super
    end
  end
end
Game_Map.prepend(ApricornTrees::MapRefresh)
