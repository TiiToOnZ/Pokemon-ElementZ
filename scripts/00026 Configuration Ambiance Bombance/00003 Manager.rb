# frozen_string_literal: true

module BombanceAmbiance
  # Reused value object. Reading weather/time has no gameplay side effects.
  class Context
    attr_reader :map_id, :zone_id, :period, :weather, :outdoor, :scene, :tjn_enabled, :revision

    def initialize(scene = :map)
      @scene = scene
      @revision = 0
    end

    def refresh(map)
      old_map, old_zone, old_period = @map_id, @zone_id, @period
      old_weather, old_outdoor, old_tjn = @weather, @outdoor, @tjn_enabled
      @map_id = map.map_id
      @zone_id = $env.current_zone
      @weather = $env.current_weather_db_symbol
      switches = $game_switches
      @outdoor = switches[Yuki::Sw::Env_CanFly]
      @tjn_enabled = switches[Yuki::Sw::TJN_Enabled]
      @period = if !switches[Yuki::Sw::TJN_Enabled]
                  :day
                elsif switches[Yuki::Sw::TJN_MorningTime]
                  :morning
                elsif switches[Yuki::Sw::TJN_DayTime]
                  :day
                elsif switches[Yuki::Sw::TJN_SunsetTime]
                  :sunset
                elsif switches[Yuki::Sw::TJN_NightTime]
                  :night
                else
                  :day
                end
      if old_map != @map_id || old_zone != @zone_id || old_period != @period ||
         old_weather != @weather || old_outdoor != @outdoor || old_tjn != @tjn_enabled
        @revision += 1
      end
      self
    end
  end

  # A borrowed native Plane, never stored or disposed by this effect.
  module NativeClouds
    # Native map coordinates: 128 units/tile. FogFix divides camera units by 4.
    # Thus 32 texture pixels/tile (16 screen pixels at the existing 0.5 zoom).
    TEXTURE_PIXELS_PER_TILE = 128 / 4

    def self.apply(plane, map, state, _context)
      plane.set_origin(map.display_x / 4 + state.phase_x + state.anchor_x * TEXTURE_PIXELS_PER_TILE,
                       map.display_y / 4 + state.phase_y + state.anchor_y * TEXTURE_PIXELS_PER_TILE)
      # Plane's existing shader performs texture wrapping. Do not round/modulo
      # here: preserve exactly the native fractional origin on the initial map.
    end
  end

  class Manager
    attr_reader :state, :context, :light_plan, :settings, :rays_plan, :rays_emitters

    def initialize
      @state = SessionState.new
      @context = Context.new
      @event_overrides = {}
      @configuration_revision = 0
    end

    def attach(map)
      return if @state.map_id == map.map_id

      @state.seed(map.fog_ox, map.fog_oy) if @state.map_id.zero?
      @state.enter(map.map_id, @state.destination(map.map_id), map.fog_ox, map.fog_oy)
    end

    def before_setup(map, target_id)
      # A loaded save still has its previous map_id/offsets, and MapLinker can
      # still contain another party's maps. Neither belongs to the new session.
      return @state.destination(target_id) if @state.map_id.zero?

      attach(map) unless map.map_id.zero?
      observe(map) unless map.map_id.zero?
      map_datas = Yuki::MapLinker.map_datas
      if !$game_switches[Yuki::Sw::MapLinkerDisabled] && map_datas.first&.map_id == map.map_id
        target = map_datas.find { |data| data.map_id == target_id }
        if target && @state.map_id == map.map_id && !map.map_id.zero?
          return @state.destination(target_id, target.offset_x, target.offset_y)
        end
      end
      @state.destination(target_id)
    end

    def after_setup(map, anchor)
      @state.enter(map.map_id, anchor, map.fog_ox, map.fog_oy)
    end

    def observe(map)
      attach(map)
      @state.observe(map.fog_ox, map.fog_oy, Configuration.clouds?(map))
    end

    def render(plane, map)
      attach(map)
      sync_context(map)
      return unless Configuration.clouds?(map)

      BombanceAmbiance.effect(:map, :clouds).apply(plane, map, @state, @context)
      plane.opacity = 0 if @settings[:clouds] == false
    end

    def sync_context(map)
      @context.refresh(map)
      if @settings_map != map.map_id || @resolved_configuration != @configuration_revision
        @settings = Configuration.resolve(map.map_id, @event_overrides[map.map_id])
        @settings_map = map.map_id
        @resolved_configuration = @configuration_revision
        @resolved_context = nil
      end
      if @resolved_context == @context.revision
        sync_rays_clock
        return
      end

      @light_plan = Configuration.light_plan(@context, @settings)
      @rays_plan = Configuration.rays_plan(@context, @settings)
      @rays_minute = Configuration.rays_minute
      @rays_timeset = Configuration.rays_timeset
      resolve_rays_emitters
      @resolved_context = @context.revision
    end

    # Clock-only changes never rebuild the V2 light plan or the placement pool.
    def sync_rays_clock
      return unless @rays_plan.enabled

      minute = Configuration.rays_minute
      timeset = Configuration.rays_timeset
      return if minute == @rays_minute && timeset == @rays_timeset

      @rays_minute, @rays_timeset = minute, timeset
      @rays_plan = Configuration.rays_plan(@context, @settings)
    end

    def advance_light(map)
      sync_context(map)
      @state.step_light if @light_plan.enabled
      @state.step_rays if @rays_plan.enabled
    end

    # Resolve only on a context/configuration change, never during stable frames.
    # Neighbour placements enter the SAME world reference as V1/V2. Stable keys
    # keep the same sprites across a linked transfer, including a fresh load on
    # either side. No random field, inferred tree detection or saved placement.
    def resolve_rays_emitters
      @rays_emitters = Configuration::NO_RAYS
      return unless @rays_plan.enabled

      result = []
      Configuration.append_emitters(result, @context.map_id, @settings,
                                    @state.anchor_x, @state.anchor_y, @rays_plan.profile)
      maps = Yuki::MapLinker.map_datas
      if !$game_switches[Yuki::Sw::MapLinkerDisabled] && maps.first&.map_id == @context.map_id
        maps.each do |data|
          next if data.map_id == @context.map_id

          settings = Configuration.resolve(data.map_id, @event_overrides[data.map_id])
          next unless settings[:rays] == true && settings[:rays_profile] == @rays_plan.name
          next if settings[:outdoor] == false

          Configuration.append_emitters(result, data.map_id, settings,
                                        @state.anchor_x - data.offset_x, @state.anchor_y - data.offset_y,
                                        @rays_plan.profile)
        end
      end
      @rays_emitters = result.freeze
    end

    # Explicit, map-scoped event overrides. Not saved and never writes weather.
    # outdoor/profile remain configuration decisions; weather attenuation wins.
    def override_effects(map_id, **effects)
      unknown = effects.keys - %i[clouds diffuse_light rays atmospherics fireflies]
      raise ArgumentError, "Unknown effects: #{unknown}" unless unknown.empty?
      raise ArgumentError, 'Expected true/false/:native' unless effects.values.all? { |v| v == true || v == false || v == :native }

      @event_overrides[map_id] = (@event_overrides[map_id] || {}).merge(effects).freeze
      @configuration_revision += 1
    end

    def clear_overrides(map_id)
      @event_overrides.delete(map_id)
      @configuration_revision += 1
    end
  end

  class << self
    # Extension contract: apply(target, source, session_state, context).
    # Registration does not create resources or start an effect. A future battle
    # adapter must supply its own source/context and lifecycle; V1 never calls it.
    def register_effect(scene, name, effect)
      raise ArgumentError, 'Effect must implement apply' unless effect.respond_to?(:apply)

      (@effects ||= {}).fetch(scene) { @effects[scene] = {} }[name] = effect
    end

    def effect(scene, name)
      @effects.fetch(scene).fetch(name)
    end

    def manager
      @manager ||= Manager.new
    end

    def reset_session
      @manager = Manager.new
    end

    def override_effects(map_id = $game_map.map_id, **effects)
      manager.override_effects(map_id, **effects)
    end

    def clear_overrides(map_id = $game_map.map_id)
      manager.clear_overrides(map_id)
    end
  end

  register_effect(:map, :clouds, NativeClouds)
end
