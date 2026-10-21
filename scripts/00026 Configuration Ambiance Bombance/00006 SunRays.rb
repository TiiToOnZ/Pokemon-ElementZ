# frozen_string_literal: true

module BombanceAmbiance
  # Read-only sampling of the ACTUAL native Plane. One CPU copy per texture,
  # no second cloud layer and no GPU readback in the frame loop.
  class RayCloudShadow
    POINTS = [[0, 0], [-8, 0], [8, 0], [0, -4], [0, 4]].map(&:freeze).freeze

    def prepare(plane)
      @plane = nil
      return unless Configuration.clouds?($game_map) && plane && !plane.disposed?
      return unless plane.visible && plane.opacity.positive? && plane.blend_type == 0
      return unless plane.texture && plane.zoom_x.positive? && plane.zoom_y.positive?

      unless @texture.equal?(plane.texture)
        dispose
        @texture = plane.texture
        @image = Image.new(@texture.to_png, true)
      end
      @plane = plane
    end

    def transmission(sprite, profile)
      return 1.0 unless @plane

      angle = sprite.angle * Math::PI / 180
      cosine, sine = Math.cos(angle), Math.sin(angle)
      coverage = POINTS.sum do |dx, dy|
        dx *= sprite.zoom_x
        dy *= sprite.zoom_y
        sample(sprite.x + dx * cosine + dy * sine, sprite.y - dx * sine + dy * cosine)
      end / POINTS.size
      threshold = profile[:cloud_threshold]
      feather = [profile[:cloud_softness], 0.001].max
      t = ((coverage - threshold + feather) / feather).clamp(0.0, 1.0)
      1 - t * t * (3 - 2 * t)
    end

    def dispose
      @image&.dispose
      @image = @texture = @plane = nil
    end

    private

    def sample(x, y)
      # Exact Plane::SHADER transform: mod(origin + screenCoord / zoom, size).
      # Both sprites share viewport1, so camera shake/viewport scaling cancel.
      px = (@plane.ox + x / @plane.zoom_x).floor % @image.width
      py = (@plane.oy + y / @plane.zoom_y).floor % @image.height
      pixel = @image.get_pixel(px, py)
      return 0.0 if pixel.alpha.zero?

      # clouds.png: dark RGB (37,33,30), alpha 255, or transparent white.
      # Alpha gates sampling; RGB/tone distinguish a shadow from opaque light.
      color, tone = @plane.color, @plane.tone
      mix = color.alpha / 255.0
      red = pixel.red + (color.red - pixel.red) * mix
      green = pixel.green + (color.green - pixel.green) * mix
      blue = pixel.blue + (color.blue - pixel.blue) * mix
      luma = red * 0.299 + green * 0.587 + blue * 0.114
      gray = tone.gray / 255.0
      red = ((red + tone.red) * (1 - gray) + luma * gray).clamp(0, 255)
      green = ((green + tone.green) * (1 - gray) + luma * gray).clamp(0, 255)
      blue = ((blue + tone.blue) * (1 - gray) + luma * gray).clamp(0, 255)
      darkness = 1 - (red * 0.299 + green * 0.587 + blue * 0.114) / 255.0
      darkness * pixel.alpha / 255.0 * @plane.opacity / 255.0
    end
  end

  # Local masks: one sprite contains beam + ground pool. RPG::Cache owns the
  # shared bitmap; the spriteset owns sprites above characters, below UI.
  class SunRays
    MASK_FOOT_X = 40.0
    MASK_FOOT_Y = 124.0
    MASK_BODY_WIDTH = 24.0
    MASK_BODY_LENGTH = 108.0
    attr_reader :sprites, :base_opacity, :angle, :profile_name, :density

    def initialize(viewport, manager, fog = nil)
      @viewport = viewport
      @profile_name = manager.rays_plan.name
      @profile = manager.rays_plan.profile
      @sprites = {}
      @clouds = RayCloudShadow.new
      @transmissions = {}
      @cloud_targets = {}
      @rgb = manager.rays_plan.rgb.map(&:to_f)
      @start_rgb = @rgb.dup
      @color = Color.new(255, 255, 255, 255)
      @base_opacity = @start_opacity = 0.0
      @density = @start_density = manager.rays_plan.density
      @solar = @start_solar = manager.rays_plan.period == :night ? 0.0 : 1.0
      @angle = @start_angle = manager.rays_plan.angle
      @start_tick = manager.state.rays_tick
      @duration = @profile[:time_transition_steps]
      update(manager, fog)
    rescue StandardError
      dispose
      raise
    end

    def update(manager, fog = nil)
      tick = manager.state.rays_tick
      elapsed = @last_tick ? [tick - @last_tick, 0].max : 0
      @last_tick = tick
      advance(tick) if @plan
      unless @plan.equal?(manager.rays_plan)
        target = manager.rays_plan
        weather_changed = @plan && @plan.weather != target.weather
        @duration = @profile[weather_changed ? :weather_transition_steps : :time_transition_steps]
        @start_rgb[0], @start_rgb[1], @start_rgb[2] = @rgb[0], @rgb[1], @rgb[2]
        @start_opacity, @start_angle, @start_tick = @base_opacity, @angle, tick
        @start_density, @start_solar = @density, @solar
        @plan = target
        advance(tick)
      end
      sync_emitters(manager.rays_emitters) unless @emitters.equal?(manager.rays_emitters)
      @clouds.prepare(fog) if @base_opacity.positive?
      @color.set(@rgb[0].round, @rgb[1].round, @rgb[2].round, 255)
      camera_x = $game_map.display_x / 8.0 + manager.state.anchor_x * 16
      camera_y = $game_map.display_y / 8.0 + manager.state.anchor_y * 16
      wave = tick * 2 * Math::PI / @profile[:wave_steps]
      @emitters.each do |emitter|
        x = emitter.world_x - camera_x
        y = emitter.world_y - camera_y
        radius = radius_for(emitter)
        sprite = @sprites[emitter.key]
        weight = (@density - emitter.rank).clamp(0.0, 1.0) * (emitter.moon ? 1.0 : @solar)
        phase = wave + emitter.phase
        variation = 1 + @profile[:variation] * (0.7 * Math.sin(phase) + 0.3 * Math.sin(phase * 0.617))
        sprite.color = @color
        sprite.angle = @angle + emitter.angle
        sprite.set_position(x + Math.sin(phase) * @profile[:sway_x],
                            y + Math.sin(phase * 0.73) * @profile[:sway_y])
        if weight <= 0.001 || @base_opacity <= 0.001 ||
           x + radius < 0 || y + radius < 0 || x - radius > Graphics.width || y - radius > Graphics.height
          sprite.visible = false
          sprite.opacity = 0
          @cloud_targets.delete(emitter.key)
          @transmissions.delete(emitter.key)
          next
        end
        sprite.visible = true
        sample = @cloud_targets[emitter.key]
        unless sample && tick - sample[0] < @profile[:cloud_sample_steps]
          sample = @cloud_targets[emitter.key] = [tick, @clouds.transmission(sprite, @profile)]
        end
        target = sample[1]
        previous = @transmissions.fetch(emitter.key, target)
        step = elapsed.to_f / [@profile[:cloud_fade_steps], 1].max
        transmission = previous + (target - previous).clamp(-step, step)
        @transmissions[emitter.key] = transmission
        sprite.opacity = (@base_opacity * emitter.opacity * variation * transmission * weight).round.clamp(0, 255)
      end
    end

    def hidden?
      @plan.opacity.zero? && @base_opacity <= 0.001
    end

    def dispose
      @sprites&.each_value { |sprite| sprite.dispose unless sprite.disposed? }
      @sprites&.clear
      @clouds&.dispose
      @transmissions&.clear
      @cloud_targets&.clear
    end

    private

    def advance(tick)
      t = @duration.positive? ? ((tick - @start_tick).to_f / @duration).clamp(0, 1) : 1.0
      t = t * t * (3 - 2 * t)
      @base_opacity = @start_opacity + (@plan.opacity - @start_opacity) * t
      @angle = @start_angle + (@plan.angle - @start_angle) * t
      @solar = @start_solar + ((@plan.period == :night ? 0.0 : 1.0) - @start_solar) * t
      duration = @profile[:density_transition_steps]
      d = duration.positive? ? ((tick - @start_tick).to_f / duration).clamp(0, 1) : 1.0
      d = d * d * (3 - 2 * d)
      @density = @start_density + (@plan.density - @start_density) * d
      3.times { |i| @rgb[i] = @start_rgb[i] + (@plan.rgb[i] - @start_rgb[i]) * t }
    end

    def sync_emitters(emitters)
      @emitters = emitters
      keys = {}
      emitters.each { |emitter| keys[emitter.key] = true }
      @transmissions.delete_if { |key, _| !keys[key] }
      @cloud_targets.delete_if { |key, _| !keys[key] }
      @sprites.delete_if do |key, sprite|
        next false if keys[key]

        sprite.dispose
        true
      end
      emitters.each { |emitter| @sprites[emitter.key] ||= create_sprite(emitter) }
      @viewport.sort_z
    end

    def radius_for(emitter)
      # Conservative bound for every angle including the ground pool, avoiding
      # a pop during sunrise/sunset rotation at a viewport boundary.
      x = MASK_FOOT_X * @profile[:width] / MASK_BODY_WIDTH * emitter.width
      y = MASK_FOOT_Y * @profile[:length] / MASK_BODY_LENGTH * emitter.length
      Math.sqrt(x * x + y * y) * @profile[:mask_scale] + 2 + @profile[:sway_x].abs + @profile[:sway_y].abs
    end

    def create_sprite(emitter)
      sprite = Sprite::WithColor.new(@viewport)
      sprite.bitmap = RPG::Cache.animation(@profile[:texture])
      sprite.set_origin(MASK_FOOT_X, MASK_FOOT_Y)
      sprite.zoom_x = @profile[:width] / MASK_BODY_WIDTH * emitter.width * @profile[:mask_scale]
      sprite.zoom_y = @profile[:length] / MASK_BODY_LENGTH * emitter.length * @profile[:mask_scale]
      sprite.z = Settings::RAYS[:z]
      sprite.opacity = 0
      sprite
    rescue StandardError
      sprite&.dispose
      raise
    end
  end

  module RaysMapAdapter
    private

    def update_sprites
      super
      manager = BombanceAmbiance.manager
      plan = manager.rays_plan # Context was refreshed by the V2 adapter.
      if !plan.enabled || !@rays_manager.equal?(manager) ||
         (@ambiance_rays && @ambiance_rays.profile_name != plan.name)
        @ambiance_rays&.dispose
        @ambiance_rays = nil
      end
      @rays_manager = manager
      return unless plan.enabled

      if !@ambiance_rays && !manager.rays_emitters.empty?
        @ambiance_rays = SunRays.new(@viewport1, manager, @fog)
      end
      @ambiance_rays&.update(manager, @fog)
    end

    def dispose_sprites
      @ambiance_rays&.dispose
      @ambiance_rays = @rays_manager = nil
      super
    end
  end
end

Spriteset_Map.prepend(BombanceAmbiance::RaysMapAdapter)
