# frozen_string_literal: true
# Historical test scenes ONLY. Never loaded by PSDK; no production file writes.
# User placements/profiles have evolved since the V1-V4 reference captures.
require_relative 'support'
require_relative 'rays_regression_config'
settings = BombanceAmbiance::Settings
route = settings::MAPS[27].merge(
  clouds: true, diffuse_light: true, outdoor: true, rays: true, rays_max: 10,
  lunar_rays: true, fireflies: true,
  fireflies_zones: [
    {x:39.5,y:24.3,width:3.5,height:1.6,count:7}.freeze,
    {x:42.0,y:18.7,width:4.0,height:2.8,count:6,intensity:0.9}.freeze,
    {x:47.5,y:24.0,width:3.2,height:2.0,count:8}.freeze
  ].freeze
).freeze
RaysRegressionConfig.set(:MAPS, {27=>route,36=>settings::MAPS[36],80=>settings::MAPS[80]}.freeze)
old = settings::FIREFLIES_PROFILES[:natural_fireflies]
profile = old.merge(scale:1.0,halo_strength:0.65,rgb:[250,255,150].freeze,
  drift_x:4.0,drift_y:3.0,pulse_steps:260.0,pulse_min:0.25,intensity_variation:0.15,
  periods:{
    morning:{density:[0.45,0.0].freeze,opacity:[115,0].freeze}.freeze,
    day:{density:[0.0,0.0].freeze,opacity:[0,0].freeze}.freeze,
    sunset:{density:[0.25,0.50].freeze,opacity:[100,155].freeze}.freeze,
    night:{density:[1.0,1.0].freeze,opacity:[220,220].freeze}.freeze
  }.freeze).freeze
RaysRegressionConfig.set(:FIREFLIES_PROFILES, {natural_fireflies:profile}.freeze)
target = ARGV.shift || 'v4'
raise 'Unknown regression suite' unless %w[v4 native_visual native_v2 native_v3 native_v4].include?(target)
require_relative target
