# frozen_string_literal: true

# Presentation and extensions of PSDK weather. Environment remains the only state.
module BombanceWeather
  FOG_ACCURACY_MULTIPLIER = 0.8
  # 0..255; a light veil behind bases/Pokemon, in the main battle viewport.
  FOG_OPACITY = 150
  FOG_SCROLL_SPEED = 4.0 # texture pixels per second, independent of frame rate
  FOG_Z = 60 # above the 2D background/terrain, below bases (100/500) and Pokemon
  FOG_APPEARANCE_DURATION = 0.6 # finite; never put ambience in @animatable

  module FogAccuracy
    def chance_of_hit_multiplier(user, target, move)
      multiplier = super
      return multiplier if @logic.weather_effects_disabled?

      multiplier * FOG_ACCURACY_MULTIPLIER
    end
  end

  module EnvironmentEntry
    # PSDK 6716 has no setter for the initial battle weather alone. Keep this
    # access to its existing fields here; do not write the outdoor @weather.
    # The shared duration may still contain the previous battle's countdown.
    def bombance_prepare_battle_weather
      return if @game_state.game_temp.in_battle

      @battle_weather = @weather
      @duration = Float::INFINITY
      ajust_weather_switches
    end
  end

  module SceneEntry
    def initialize(...)
      $env.bombance_prepare_battle_weather
      super
    end

    private

    # PSDK calls this AFTER sending animations, BEFORE entry abilities.
    def show_enter_event
      unless @bombance_initial_weather_presented
        @bombance_initial_weather_presented = true
        weather = @logic.raw_weather_effect.db_symbol
        message_id = Battle::Logic::WeatherChangeHandler::WEATHER_SYM_TO_MSG[weather]
        if message_id.is_a?(Integer)
          message = parse_text(18, message_id)
          # Missing Studio translations can be empty or contain [~ 287].
          if message.is_a?(String) && !message.strip.empty? && !message.match?(/\[~\s*\d+\s*\]/)
            display_message_and_wait(message)
          end
        end
        @visual.bombance_enable_weather_ambience
        @visual.show_weather_animation(weather) unless weather == :none
      end
      super
    end
  end

  module DefogMessage
    private

    # Native Defog clears fog, then incorrectly displays 18,98 (sandstorm).
    # Clear it with the native handler first. Super then skips only that branch
    # and still performs ALL native hazard/screen removal. 18,96 is emitted once.
    def deal_effect(user, actual_targets)
      handler = logic.weather_change_handler
      handler.weather_change(:none) if handler.current_weather?(weather_to_cancel)
      super
    end
  end
end

PFM::Environment.prepend(BombanceWeather::EnvironmentEntry)
Battle::Effects::Weather::Fog.prepend(BombanceWeather::FogAccuracy)
Battle::Scene.prepend(BombanceWeather::SceneEntry)
Battle::Move::Defog.prepend(BombanceWeather::DefogMessage)
