# frozen_string_literal: true
# Stable V3 regression scene. User-edited production ray settings stay intact.
module RaysRegressionConfig
  POSITIONS = [
    { x: 37.4, y: 20.2, width: 0.85, length: 0.90, angle: -3 },
    { x: 38.0, y: 26.6, width: 1.10, length: 0.80 },
    { x: 44.7, y: 27.3, width: 0.75, length: 1.00, opacity: 0.85 },
    { x: 50.2, y: 20.9, width: 0.90, length: 0.75, angle: 4 },
    { x: 44.5, y: 21.1, width: 0.80, length: 0.90 },
    { x: 48.4, y: 27.5, width: 0.85, length: 0.85, angle: 2 },
    { x: 37.8, y: 16.3, width: 0.75, length: 0.80 },
    { x: 40.7, y: 27.1, width: 0.75, length: 0.75, angle: -2 },
    { x: 47.0, y: 21.5, width: 0.70, length: 0.80 },
    { x: 50.5, y: 25.0, width: 0.75, length: 0.70 }
  ].map(&:freeze).freeze

  def self.set(name, value)
    BombanceAmbiance::Settings.send(:remove_const, name)
    BombanceAmbiance::Settings.const_set(name, value)
  end

  def self.install
    maps, profiles = BombanceAmbiance::Settings::MAPS, BombanceAmbiance::Settings::RAYS_PROFILES
    profile = profiles[:forest_sunlight]
    periods = profile[:periods].merge(
      morning: profile[:periods][:morning].merge(opacity: 92, count: 5, minimum: 2).freeze,
      day: profile[:periods][:day].merge(opacity: 110, count: 10, minimum: 5).freeze,
      sunset: profile[:periods][:sunset].merge(opacity: 80, count: 6, minimum: 3).freeze,
      night: profile[:periods][:night].merge(opacity: 58, count: 3, minimum: 1).freeze
    ).freeze
    set(:RAYS_PROFILES, profiles.merge(forest_sunlight: profile.merge(periods: periods).freeze).freeze)
    set(:MAPS, maps.merge(27 => maps[27].merge(rays_positions: POSITIONS).freeze).freeze)
    [maps, profiles]
  end

  def self.restore(original)
    set(:MAPS, original[0])
    set(:RAYS_PROFILES, original[1])
  end
end
