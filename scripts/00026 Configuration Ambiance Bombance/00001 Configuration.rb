# frozen_string_literal: true

module BombanceAmbiance
  # Resolver only. User-editable values live in 00000 AmbiancesConfig.rb.
  module Configuration
    CLOUD_TEXTURE = 'clouds'
    def self.clouds?(map)
      map.fog_name == CLOUD_TEXTURE
    end

    def self.resolve(map_id, overrides = nil, groups: Settings::GROUPS, maps: Settings::MAPS)
      result = Settings::DEFAULTS.dup
      groups.each_value do |group|
        result.merge!(group.fetch(:effects)) if group.fetch(:maps).include?(map_id)
      end
      result.merge!(maps.fetch(map_id, {}))
      result.merge!(overrides) if overrides
      result.freeze
    end

    LightPlan = Struct.new(:enabled, :rgb, :opacity)
    DARK = [0, 0, 0].freeze

    def self.light_plan(context, settings)
      outdoor = settings[:outdoor] == :native ? context.outdoor : settings[:outdoor]
      period = context.tjn_enabled ? context.period : Settings::LIGHT[:disabled_tjn_period]
      enabled = settings[:diffuse_light] == true && outdoor == true && !period.nil?
      return LightPlan.new(false, DARK, 0).freeze unless enabled

      profile = Settings::PROFILES.fetch(settings[:light_profile]).fetch(period)
      factor = Settings::WEATHER_LIGHT.fetch(context.weather, Settings::UNKNOWN_WEATHER_LIGHT)
      LightPlan.new(true, profile[:rgb], profile[:opacity] * factor).freeze
    end

    RaysPlan = Struct.new(:enabled, :name, :profile, :rgb, :opacity, :angle, :period, :weather, :density)
    RayEmitter = Struct.new(:key, :world_x, :world_y, :width, :length, :angle, :opacity, :phase, :rank, :moon)
    NO_RAYS = [].freeze

    def self.rays_plan(context, settings)
      outdoor = settings[:outdoor] == :native ? context.outdoor : settings[:outdoor]
      period = context.tjn_enabled ? context.period : Settings::RAYS[:disabled_tjn_period]
      enabled = settings[:rays] == true && outdoor == true && !period.nil?
      return RaysPlan.new(false, nil, nil, DARK, 0, 0, period, context.weather).freeze unless enabled

      name = settings[:rays_profile]
      profile = Settings::RAYS_PROFILES.fetch(name)
      palette = profile.fetch(:periods).fetch(period)
      factor = profile[:weather].fetch(context.weather, profile[:unknown_weather])
      factor = 0 if context.weather == :fog || (period == :night && !settings[:lunar_rays])
      RaysPlan.new(true, name, profile, palette[:rgb], palette[:opacity] * factor,
                   palette[:angle], period, context.weather, rays_density(period, palette)).freeze
    end

    # The same TJN variables drive virtual AND real time. Never advance them here.
    def self.rays_minute
      $game_variables[Yuki::Var::TJN_Hour] * 60 + $game_variables[Yuki::Var::TJN_Min]
    end

    def self.rays_timeset
      Yuki::TJN.send(:current_time_set)
    end

    def self.rays_density(period, palette)
      night, evening, day, morning = rays_timeset
      start_hour, end_hour = case period
                             when :morning then [morning, day]
                             when :day then [day, evening]
                             when :sunset then [evening, night]
                             else [night, morning + 24]
                             end
      hour = rays_minute / 60.0
      hour += 24 if period == :night && hour < start_hour
      peak = palette[:peak_hour] || (start_hour + end_hour) / 2.0
      peak += 24 if period == :night && peak < start_hour
      peak = peak.clamp(start_hour + 0.001, end_hour - 0.001)
      distance = hour <= peak ? (peak - hour) / (peak - start_hour) : (hour - peak) / (end_hour - peak)
      strength = 1 - distance.clamp(0.0, 1.0)
      strength *= strength * (3 - 2 * strength)
      palette[:minimum] + (palette[:count] - palette[:minimum]) * strength
    end

    def self.append_emitters(result, map_id, settings, anchor_x, anchor_y, profile)
      settings[:rays_positions].first(settings[:rays_max] || profile[:count]).each_with_index do |position, index|
        result << RayEmitter.new(
          "#{map_id}:#{index}".freeze,
          (anchor_x + position.fetch(:x)) * 16, (anchor_y + position.fetch(:y)) * 16,
          position.fetch(:width, 1.0), position.fetch(:length, 1.0),
          position.fetch(:angle, 0.0), position.fetch(:opacity, 1.0),
          (map_id * 37 + index * 101) % 997 * Math::PI * 2 / 997,
          index, settings[:lunar_rays]
        ).freeze
      end
    end
  end
end
