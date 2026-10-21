# frozen_string_literal: true

module BombanceAmbiance
  # Numeric values only, owned by the service, never attached to GameState/Map.
  # Native logical updates remain the clock; no wall clock or extra update loop.
  class SessionState
    attr_reader :map_id, :phase_x, :phase_y, :anchor_x, :anchor_y
    attr_reader :light_x, :light_y, :light_tick
    attr_reader :rays_tick

    def initialize
      @map_id = 0
      @phase_x = @phase_y = 0.0
      @native_x = @native_y = 0.0
      @anchor_x = @anchor_y = 0
      @anchors = {}
      @light_x = @light_y = 0.0
      @light_tick = 0
      @rays_tick = 0
    end

    def step_light
      @light_tick += 1
      @light_x += Settings::LIGHT[:step_x]
      @light_y += Settings::LIGHT[:step_y]
    end

    def step_rays
      @rays_tick += 1
    end

    # MapData offsets convert SOURCE coordinates into TARGET coordinates.
    # Consequently the target's world origin is source origin MINUS the offset.
    # Copy numbers before MapLinker mutates its reused MapData objects in setup.
    def destination(map_id, offset_x = nil, offset_y = nil)
      return [@anchor_x - offset_x, @anchor_y - offset_y] if offset_x && offset_y

      # Distant teleport: a remembered local origin, or an independent origin.
      # Never align two unrelated places using the player's screen position.
      @anchors.fetch(map_id) { [0, 0] }
    end

    def enter(map_id, anchor, native_x, native_y)
      @map_id = map_id
      @anchor_x, @anchor_y = anchor
      @anchors[map_id] = anchor
      @native_x = native_x
      @native_y = native_y
    end

    def seed(native_x, native_y)
      @phase_x = native_x
      @phase_y = native_y
    end

    # Observe the native result, including its exact frequency, fractional steps
    # and event-controlled speeds. Non-cloud fogs do not advance the cloud phase.
    def observe(native_x, native_y, enabled)
      if enabled
        @phase_x += native_x - @native_x
        @phase_y += native_y - @native_y
      end
      @native_x = native_x
      @native_y = native_y
    end
  end
end
