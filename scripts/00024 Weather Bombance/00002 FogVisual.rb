# frozen_string_literal: true

module BombanceWeather
  MIST_TEXTURE = 'bombance_weather/mist_wisps'
  # Screen pixels/second and pixels. Both sheets stay below bases/Pokemon.
  MIST_LAYERS = [
    { opacity: 52, speed: 6.0, x: 0, y: -8, wave: 2.0, period: 13.0 }.freeze,
    { opacity: 36, speed: 9.0, x: 160, y: -34, wave: 3.0, period: 17.0 }.freeze
  ].freeze

  # Graphics only: no saved object, no weather flag, no gameplay decision.
  class FogLayer
    attr_reader :plane, :mist_planes

    def initialize(viewport)
      @mist_planes = []
      @plane = Plane.new(viewport)
      @plane.bitmap = RPG::Cache.animation('fog')
      @plane.z = FOG_Z
      @plane.opacity = FOG_OPACITY
      texture = RPG::Cache.animation(MIST_TEXTURE)
      @mist_scale_x = 320.0 / texture.width
      @mist_scale_y = 240.0 / texture.height
      @mist_phases = [0.0, Math::PI]
      MIST_LAYERS.each_with_index do |settings, index|
        mist = Plane.new(viewport)
        @mist_planes << mist
        mist.bitmap = texture
        mist.zoom_x = @mist_scale_x
        mist.zoom_y = @mist_scale_y
        mist.z = FOG_Z + index + 1
        mist.opacity = settings[:opacity]
        mist.set_origin(settings[:x] / @mist_scale_x, settings[:y] / @mist_scale_y)
      end
      @last_time = Graphics.current_time
      viewport.sort_z
    rescue StandardError
      dispose
      raise
    end

    def opacity=(value)
      return if @plane.disposed?

      @plane.opacity = value.round.clamp(0, 255)
      # Same finite fade as the existing veil, including animation interruption.
      factor = FOG_OPACITY.positive? ? (value.to_f / FOG_OPACITY).clamp(0, 1) : 1.0
      @mist_planes.each_with_index do |mist, index|
        mist.opacity = (MIST_LAYERS[index][:opacity] * factor).round
      end
    end

    def update
      return if @plane.disposed?

      now = Graphics.current_time
      delta = now > @last_time ? now - @last_time : 0
      @last_time = now
      @plane.ox = (@plane.ox + delta * FOG_SCROLL_SPEED) % @plane.bitmap.width
      @mist_planes.each_with_index do |mist, index|
        settings = MIST_LAYERS[index]
        @mist_phases[index] = (@mist_phases[index] + delta * 2 * Math::PI / settings[:period]) % (2 * Math::PI)
        mist.ox = (mist.ox + delta * settings[:speed] / @mist_scale_x) % mist.bitmap.width
        mist.oy = (settings[:y] + Math.sin(@mist_phases[index]) * settings[:wave]) / @mist_scale_y
      end
    end

    def dispose
      @mist_planes.each { |mist| mist.dispose unless mist.disposed? }
      @plane.dispose if @plane && !@plane.disposed?
      # Both shared bitmaps belong to RPG::Cache. Only the three planes are ours.
    end
  end

  class FogAppearance < UI::WeatherSprite
    def initialize(viewport, scene, weather)
      super(viewport, scene)
      @db_symbol = weather
    end

    def weather_animation(_weather)
      layer = @scene.visual.bombance_enable_weather_ambience
      return unless layer

      layer.opacity = 0
      animation = Yuki::Animation.scalar(FOG_APPEARANCE_DURATION, layer, :opacity=, 0, FOG_OPACITY)
      @animation_handler[:fog] = animation.start
    end
  end

  module VisualAmbience
    # Lifecycle gate, not a second weather state: wait for the initial message.
    # Once enabled, only Logic#raw_weather_effect determines layer existence.
    def bombance_enable_weather_ambience
      @bombance_weather_ambience_started = true
      bombance_sync_weather_ambience
      @bombance_fog_layer
    end

    def update
      bombance_sync_weather_ambience
      @bombance_fog_layer&.update
      super
    end

    # Native handlers call this immediately after Environment#apply_weather,
    # including :none and with animations disabled. Direct script changes are
    # caught by the lightweight update above.
    def show_weather_animation(weather)
      bombance_sync_weather_ambience
      super
    end

    def dispose
      bombance_dispose_fog
      @bombance_weather_ambience_started = false
      super
    end

    private

    def bombance_sync_weather_ambience
      return unless @bombance_weather_ambience_started && @viewport && !@viewport.disposed?

      if @scene.logic.raw_weather_effect.fog?
        @bombance_fog_layer ||= FogLayer.new(@viewport)
      else
        bombance_dispose_fog
      end
    end

    def bombance_dispose_fog
      @bombance_fog_layer&.dispose
      @bombance_fog_layer = nil
    end
  end
end

UI::WeatherSprite.register(:fog, BombanceWeather::FogAppearance)
Battle::Visual.prepend(BombanceWeather::VisualAmbience)
