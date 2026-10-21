# frozen_string_literal: true

module BombanceAmbiance
  # One Plane belonging to the spriteset. Shared texture belongs to RPG::Cache.
  # Does not modify native fog, characters, viewports, tone or weather.
  class DiffuseLight
    attr_reader :plane, :base_opacity

    def initialize(viewport, manager)
      @plane = Plane.new(viewport)
      @plane.bitmap = RPG::Cache.animation(Settings::LIGHT[:texture])
      @plane.zoom = 1
      @plane.z = Settings::LIGHT[:z]
      @plane.opacity = 0
      @color = Color.new(255, 255, 255, 255)
      @rgb = manager.light_plan.rgb.map(&:to_f)
      @start_rgb = @rgb.dup
      @base_opacity = @start_opacity = 0.0
      @start_tick = manager.state.light_tick
      @plan = nil
      viewport.sort_z
      update(manager)
    rescue StandardError
      dispose
      raise
    end

    def update(manager)
      state = manager.state
      advance(state.light_tick) if @plan
      unless @plan.equal?(manager.light_plan)
        @start_rgb[0], @start_rgb[1], @start_rgb[2] = @rgb[0], @rgb[1], @rgb[2]
        @start_opacity = @base_opacity
        @start_tick = state.light_tick
        @plan = manager.light_plan
        advance(state.light_tick)
      end
      config = Settings::LIGHT
      wave = state.light_tick * 2 * Math::PI / config[:wave_steps]
      modulation = 1 + config[:variation] * (Math.sin(wave) * 0.6 + Math.sin(wave * 0.613) * 0.4)
      @plane.opacity = (@base_opacity * modulation).round.clamp(0, 255)
      @color.set(@rgb[0].round, @rgb[1].round, @rgb[2].round, 255)
      @plane.color = @color
      @plane.set_origin($game_map.display_x / 8.0 + state.anchor_x * 16 + state.light_x,
                        $game_map.display_y / 8.0 + state.anchor_y * 16 + state.light_y)
    end

    def hidden?
      @plan.opacity.zero? && @base_opacity <= 0.001
    end

    def dispose
      @plane.dispose if @plane && !@plane.disposed?
    end

    private

    def advance(tick)
      duration = Settings::LIGHT[:transition_steps]
      t = duration.positive? ? ((tick - @start_tick).to_f / duration).clamp(0, 1) : 1.0
      t = t * t * (3 - 2 * t) # Smooth start/end, retarget from current values.
      @base_opacity = @start_opacity + (@plan.opacity - @start_opacity) * t
      3.times { |i| @rgb[i] = @start_rgb[i] + (@plan.rgb[i] - @start_rgb[i]) * t }
    end
  end

  module LightMapAdapter
    private

    def update_sprites
      super
      manager = BombanceAmbiance.manager
      manager.sync_context($game_map)
      if !manager.light_plan.enabled || !@ambiance_manager.equal?(manager)
        @ambiance_light&.dispose
        @ambiance_light = nil
      end
      @ambiance_manager = manager
      return unless manager.light_plan.enabled

      if !@ambiance_light && manager.light_plan.opacity.positive?
        @ambiance_light = DiffuseLight.new(@viewport1, manager)
      end
      @ambiance_light&.update(manager)
      if @ambiance_light&.hidden?
        @ambiance_light.dispose
        @ambiance_light = nil
      end
    end

    def dispose_sprites
      @ambiance_light&.dispose
      @ambiance_light = @ambiance_manager = nil
      super
    end
  end
end

Spriteset_Map.prepend(BombanceAmbiance::LightMapAdapter)
