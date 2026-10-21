# frozen_string_literal: true

module BombanceAmbiance
  # V4 only: no changes to the V1/V2/V3 clocks, plans or graphics.
  module FireflyConfiguration
    Plan = Struct.new(:enabled, :name, :profile, :density, :opacity, :rgb, :weather)
    Zone = Struct.new(:key, :x, :y, :width, :height, :count, :intensity)
    EMPTY = [].freeze

    def self.plan(context, settings)
      outdoor = settings[:outdoor] == :native ? context.outdoor : settings[:outdoor]
      enabled = settings[:fireflies] == true && outdoor == true && context.tjn_enabled
      return Plan.new(false).freeze unless enabled

      profile = Settings::FIREFLIES_PROFILES.fetch(settings[:fireflies_profile])
      period = profile[:periods].fetch(context.period)
      night, evening, day, morning = Configuration.rays_timeset
      first, last = case context.period
                    when :morning then [morning, day]
                    when :day then [day, evening]
                    when :sunset then [evening, night]
                    else [night, morning + 24]
                    end
      hour = Configuration.rays_minute / 60.0
      hour += 24 if context.period == :night && hour < first
      t = ((hour - first) / (last - first).to_f).clamp(0.0, 1.0)
      t = t * t * (3 - 2 * t)
      weather = profile[:weather].fetch(context.weather, profile[:unknown_weather])
      density = period[:density][0] + (period[:density][1] - period[:density][0]) * t
      opacity = period[:opacity][0] + (period[:opacity][1] - period[:opacity][0]) * t
      Plan.new(true, settings[:fireflies_profile], profile, density * weather,
               opacity * weather, period.fetch(:rgb, profile[:rgb]), context.weather).freeze
    end

    def self.append(zones, id, settings, ax, ay, profile)
      settings[:fireflies_zones].each_with_index do |zone, index|
        count = [zone.fetch(:count), profile[:max_per_zone]].min
        next unless count.positive? && zone[:width].positive? && zone[:height].positive?

        zones << Zone.new("#{id}:#{index}".freeze,
                          (ax + zone[:x]) * 16, (ay + zone[:y]) * 16,
                          zone[:width] * 16, zone[:height] * 16,
                          count, zone.fetch(:intensity, 1.0)).freeze
      end
    end
  end

  module FireflyManagerAdapter
    attr_reader :fireflies_plan, :fireflies_zones, :fireflies_tick

    def initialize
      super
      @fireflies_tick = 0
    end

    def sync_context(map)
      super
      # V4 clock cache is separate: minute changes never retarget V2 or V3.
      minute, timeset = Configuration.rays_minute, Configuration.rays_timeset
      layout_changed = !@fireflies_settings.equal?(@settings)
      return if !layout_changed && @fireflies_revision == @context.revision &&
                @fireflies_minute == minute && @fireflies_timeset == timeset

      previous = @fireflies_plan
      @fireflies_plan = FireflyConfiguration.plan(@context, @settings)
      if layout_changed || !previous || previous.enabled != @fireflies_plan.enabled
        @fireflies_zones = FireflyConfiguration::EMPTY
        if @fireflies_plan.enabled
          zones = []
          FireflyConfiguration.append(zones, map.map_id, @settings, @state.anchor_x, @state.anchor_y, @fireflies_plan.profile)
          maps = Yuki::MapLinker.map_datas
          if !$game_switches[Yuki::Sw::MapLinkerDisabled] && maps.first&.map_id == map.map_id
            maps.each do |data|
              next if data.map_id == map.map_id

              settings = Configuration.resolve(data.map_id, @event_overrides[data.map_id])
              next unless settings[:fireflies] == true && settings[:fireflies_profile] == @fireflies_plan.name
              next if settings[:outdoor] == false

              FireflyConfiguration.append(zones, data.map_id, settings,
                                          @state.anchor_x - data.offset_x, @state.anchor_y - data.offset_y,
                                          @fireflies_plan.profile)
            end
          end
          @fireflies_zones = zones.freeze
        end
      end
      @fireflies_settings, @fireflies_revision = @settings, @context.revision
      @fireflies_minute, @fireflies_timeset = minute, timeset
    end

    def advance_light(map)
      super
      @fireflies_tick += 1 if @fireflies_plan.enabled
    end
  end

  class Fireflies
    Particle = Struct.new(:zone, :rank, :u, :v, :phase, :speed, :brightness)
    attr_reader :sprites, :particles, :density, :base_opacity, :profile_name, :texture

    def initialize(viewport, manager)
      @viewport, @profile_name = viewport, manager.fireflies_plan.name
      @profile = manager.fireflies_plan.profile
      @sprites, @particles = {}, {}
      @density = @base_opacity = 0.0
      @rgb = manager.fireflies_plan.rgb.map(&:to_f)
      @color = Color.new(*@rgb, 255)
      build_texture
      update(manager)
    rescue StandardError
      dispose
      raise
    end

    def update(manager)
      tick = manager.fireflies_tick
      advance(tick) if @plan
      unless @plan.equal?(manager.fireflies_plan)
        target = manager.fireflies_plan
        @duration = @profile[@plan && @plan.weather != target.weather ? :weather_transition_steps : :transition_steps]
        @start_density, @start_opacity, @start_rgb = @density, @base_opacity, @rgb.dup
        @start_tick, @plan = tick, target
        advance(tick)
      end
      sync_zones(manager.fireflies_zones) unless @zones.equal?(manager.fireflies_zones)
      @color.set(*@rgb.map(&:round), 255)
      camera_x = $game_map.display_x / 8.0 + manager.state.anchor_x * 16
      camera_y = $game_map.display_y / 8.0 + manager.state.anchor_y * 16
      motion = tick * 2 * Math::PI / @profile[:move_steps]
      pulse = tick * 2 * Math::PI / @profile[:pulse_steps]
      @particles.each do |key, particle|
        zone, sprite = particle.zone, @sprites.fetch(key)
        weight = (@density * zone.count - particle.rank).clamp(0.0, 1.0)
        left, top = zone.x - camera_x, zone.y - camera_y
        if weight <= 0.001 || @base_opacity <= 0.001 ||
           left > Graphics.width || top > Graphics.height || left + zone.width < 0 || top + zone.height < 0
          sprite.visible = false
          sprite.opacity = 0
          next
        end
        # Bounded sums of slow oscillations: no abrupt random targets or bounces.
        margin = 3.5 * @profile[:scale]
        ax = [@profile[:drift_x], [zone.width / 2 - margin, 0].max].min
        ay = [@profile[:drift_y], [zone.height / 2 - margin, 0].max].min
        mx, my = [ax + margin, zone.width / 2].min, [ay + margin, zone.height / 2].min
        t, phase = motion * particle.speed, particle.phase
        x = left + mx + particle.u * (zone.width - 2 * mx) + ax * (0.62 * Math.sin(t + phase) + 0.38 * Math.sin(t * 0.413 + phase * 1.71))
        y = top + my + particle.v * (zone.height - 2 * my) + ay * (0.58 * Math.sin(t * 0.739 + phase * 1.37) + 0.42 * Math.sin(t * 0.281 + phase * 2.13))
        glow = (1 + Math.sin(pulse * particle.speed + phase * 2.37)) / 2
        glow = @profile[:pulse_min] + (1 - @profile[:pulse_min]) * glow * glow
        sprite.set_position(x.round, y.round) # Logical pixels: crisp, tiny halo.
        sprite.color = @color
        sprite.opacity = (@base_opacity * weight * zone.intensity * particle.brightness * glow).round.clamp(0, 255)
        sprite.visible = true
      end
    end

    def dispose
      @sprites&.each_value { |sprite| sprite.dispose unless sprite.disposed? }
      @sprites&.clear
      @particles&.clear
      @texture.dispose if @texture && !@texture.disposed?
    end

    private

    def build_texture
      # Shared 7x7 mask. Only halo pixels are attenuated, core remains untouched.
      source = RPG::Cache.animation(@profile[:texture])
      pixels = Image.new(source.to_png, true)
      pixels.height.times do |y|
        pixels.width.times do |x|
          pixel = pixels.get_pixel(x, y)
          next if pixel.alpha == 255

          pixel.alpha = (pixel.alpha * @profile[:halo_strength]).round.clamp(0, 255)
          pixels.set_pixel(x, y, pixel)
        end
      end
      @texture = Texture.new(pixels.width, pixels.height)
      pixels.copy_to_bitmap(@texture)
    ensure
      pixels&.dispose
    end

    def advance(tick)
      t = @duration.positive? ? ((tick - @start_tick).to_f / @duration).clamp(0, 1) : 1.0
      t = t * t * (3 - 2 * t)
      @density = @start_density + (@plan.density - @start_density) * t
      @base_opacity = @start_opacity + (@plan.opacity - @start_opacity) * t
      3.times { |i| @rgb[i] = @start_rgb[i] + (@plan.rgb[i] - @start_rgb[i]) * t }
    end

    def sync_zones(zones)
      @zones = zones
      keep = {}
      zones.each do |zone|
        zone.count.times do |rank|
          key = "#{zone.key}:#{rank}"
          keep[key] = true
          if @particles[key]
            @particles[key].zone = zone
            next
          end
          # Stable across processes, maps and sessions; never Ruby's salted hash.
          seed = key.bytes.reduce(17) { |value, byte| (value * 31 + byte) & 0x7fffffff }
          values = 5.times.map { seed = (seed * 1_103_515_245 + 12_345) & 0x7fffffff; seed / 2_147_483_648.0 }
          @particles[key] = Particle.new(zone, rank, values[0], values[1], values[2] * 2 * Math::PI,
                                         0.75 + values[3] * 0.5, 1 - values[4] * @profile[:intensity_variation])
          sprite = @sprites[key] = Sprite::WithColor.new(@viewport)
          sprite.bitmap = @texture
          sprite.set_origin(@texture.width / 2, @texture.height / 2)
          sprite.zoom_x = sprite.zoom_y = @profile[:scale]
          sprite.z, sprite.opacity, sprite.visible = @profile[:z], 0, false
          sprite.shader.blend_type = 0 # LiteRGSS normal alpha, not additive glow.
        end
      end
      @sprites.delete_if do |key, sprite|
        next false if keep[key]

        sprite.dispose
        @particles.delete(key)
        true
      end
      @viewport.sort_z
    end
  end

  module FireflyMapAdapter
    private

    def update_sprites
      super
      manager = BombanceAmbiance.manager
      plan = manager.fireflies_plan
      if !plan.enabled || !@firefly_manager.equal?(manager) ||
         (@ambiance_fireflies && @ambiance_fireflies.profile_name != plan.name)
        @ambiance_fireflies&.dispose
        @ambiance_fireflies = nil
      end
      @firefly_manager = manager
      if plan.enabled && !manager.fireflies_zones.empty?
        if !@ambiance_fireflies && plan.density.positive? && plan.opacity.positive?
          @ambiance_fireflies = Fireflies.new(@viewport1, manager)
        end
        @ambiance_fireflies&.update(manager)
      elsif @ambiance_fireflies
        @ambiance_fireflies.dispose
        @ambiance_fireflies = nil
      end
    end

    def dispose_sprites
      @ambiance_fireflies&.dispose
      @ambiance_fireflies = @firefly_manager = nil
      super
    end
  end
end

BombanceAmbiance::Manager.prepend(BombanceAmbiance::FireflyManagerAdapter)
Spriteset_Map.prepend(BombanceAmbiance::FireflyMapAdapter)
