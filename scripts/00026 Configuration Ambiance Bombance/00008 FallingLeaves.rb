# frozen_string_literal: true

module BombanceAmbiance
  # V5 reads effective weather only. Its tick follows Game_Map's logical update,
  # through the existing manager lifecycle; UI redraws cannot advance it.
  module FallingLeavesManagerAdapter
    attr_reader :leaves_tick, :leaves_profile, :leaves_profile_name

    def initialize
      super
      @leaves_tick = 0
      @leaves_overrides = {}
    end

    def sync_context(map)
      super
      enabled = @leaves_overrides.fetch(map.map_id, @settings[:falling_leaves]) == true
      outdoor = @settings[:outdoor] == :native ? @context.outdoor : @settings[:outdoor]
      @leaves_profile_name = enabled && outdoor ? @settings[:falling_leaves_profile] : nil
      @leaves_profile = @leaves_profile_name && Settings::FALLING_LEAVES_PROFILES.fetch(@leaves_profile_name)
      if @leaves_battle && (@leaves_battle[:map] != map.map_id ||
                           !@leaves_battle[:profile].equal?(@leaves_profile))
        @leaves_battle = nil
      end
    end

    def advance_light(map)
      super
      @leaves_tick += 1 if @leaves_profile
    end

    def override_effects(map_id, **effects)
      return super unless effects.key?(:falling_leaves)

      leaves = effects.delete(:falling_leaves)
      raise ArgumentError, 'falling_leaves expects true/false' unless leaves == true || leaves == false

      super(map_id, **effects)
      @leaves_overrides[map_id] = leaves
    end

    def clear_overrides(map_id)
      super
      @leaves_overrides.delete(map_id)
    end

    # A single numeric snapshot, reserved by a real Scene_Map battle launch.
    # No Sprite, Color, Texture, viewport or battle scene is retained here.
    def suspend_leaves_for_battle(renderer, battle)
      @leaves_battle = nil
      return unless renderer && @leaves_profile

      @leaves_battle = { battle: battle.object_id, map: @context.map_id,
                        player: [$game_player.x, $game_player.y], profile: @leaves_profile,
                        snapshot: renderer.snapshot, ready: false }
    end

    def finish_leaves_battle(battle)
      return unless @leaves_battle

      if @leaves_battle[:battle] == battle.object_id && !$game_temp.in_battle &&
         @leaves_battle[:map] == $game_map.map_id &&
         @leaves_battle[:player] == [$game_player.x, $game_player.y]
        @leaves_battle[:ready] = true
      else
        @leaves_battle = nil
      end
    end

    def take_leaves_battle_snapshot
      @leaves_battle = nil if @leaves_battle && !@leaves_battle[:ready] && !$game_temp.in_battle
      return unless @leaves_battle && @leaves_battle[:ready]

      saved, @leaves_battle = @leaves_battle, nil
      return saved[:snapshot] if saved[:map] == $game_map.map_id &&
                                saved[:profile].equal?(@leaves_profile) &&
                                saved[:player] == [$game_player.x, $game_player.y]
    end
  end

  # World pixels use the existing V1/V3/V4 MapLinker reference. Only projection
  # depends on the camera; logical fall and sway never depend on the player.
  class FallingLeaves
    Particle = Struct.new(:x, :y, :phase, :speed, :drift, :sway, :period,
                          :scale, :opacity, :variant, :color_index, :wait, :alpha)
    attr_reader :sprites, :particles, :profile_name, :texture, :density, :tick

    def initialize(viewport, manager)
      @profile_name, @profile = manager.leaves_profile_name, manager.leaves_profile
      @texture = RPG::Cache.animation(@profile[:texture]) # Borrowed; cache owns it.
      @sprites, @particles = [], []
      @random = Random.new(@profile[:seed]) # Never consumes Kernel.rand.
      @tick, @density, @fall, @wind = manager.leaves_tick, 0.0, 1.0, 1.0
      locate_camera(manager)
      @step_camera_x, @step_camera_y = @camera_x, @camera_y
      saved = manager.take_leaves_battle_snapshot
      if saved
        @particles, @random = saved[:particles], saved[:random]
        @density, @fall, @wind = saved.values_at(:density, :fall, :wind)
      else
        seed_particles
      end
      @particles.each do |particle|
        sprite = Sprite::WithColor.new(viewport)
        @sprites << sprite
        size = @profile[:frame_size]
        sprite.bitmap = @texture
        sprite.src_rect.set(particle.variant * size, 0, size, size)
        sprite.set_origin(size / 2, size / 2)
        sprite.zoom_x = sprite.zoom_y = particle.scale
        sprite.color = Color.new(*@profile[:colors][particle.color_index], @profile[:tint])
        sprite.z, sprite.opacity, sprite.visible = @profile[:z], 0, false
        sprite.shader.blend_type = 0
      end
      viewport.sort_z
      draw
    rescue StandardError
      dispose
      raise
    end

    def snapshot
      { particles: @particles.map(&:dup), random: @random.dup,
        density: @density, fall: @fall, wind: @wind }
    end

    def update(manager)
      elapsed = [manager.leaves_tick - @tick, 0].max
      locate_camera(manager)
      @camera_dx = @camera_x - @step_camera_x
      @camera_dy = @camera_y - @step_camera_y
      factors = @profile[:weather].fetch(manager.context.weather, @profile[:unknown_weather])
      elapsed.times { step(factors) }
      @step_camera_x, @step_camera_y = @camera_x, @camera_y if elapsed.positive?
      @tick = manager.leaves_tick
      draw # Camera projection is necessary even when no logical tick elapsed.
    end

    def dispose
      @sprites&.each { |sprite| sprite.dispose unless sprite.disposed? }
      @sprites&.clear
      @particles&.clear
    end

    private

    def seed_particles
      @profile[:count].times do |index|
        particle = Particle.new
        particle.speed = 1 + signed * @profile[:speed_variation]
        particle.drift = 1 + signed * 0.35
        particle.sway = @profile[:sway_amplitude] * (0.7 + @random.rand * 0.6)
        particle.period = @profile[:sway_steps] * (0.8 + @random.rand * 0.4)
        particle.scale = @profile[:scale] * (1 + signed * @profile[:scale_variation])
        particle.opacity = @profile[:opacity] * (1 - @random.rand * @profile[:opacity_variation])
        particle.variant = @random.rand(@profile[:variants])
        particle.color_index = @random.rand(@profile[:colors].size)
        particle.alpha = 0.0
        respawn(particle)
        # All births are above the screen, staggered over one fall cycle.
        particle.y -= Graphics.height * index.to_f / @profile[:count]
        particle.wait = 0
        @particles << particle
      end
    end

    def locate_camera(manager)
      x = $game_map.display_x / 8.0 + manager.state.anchor_x * 16
      y = $game_map.display_y / 8.0 + manager.state.anchor_y * 16
      @camera_x, @camera_y = x, y
      @map_left = manager.state.anchor_x * 16
      @map_right = @map_left + $game_map.width * 16
    end

    def signed
      @random.rand * 2 - 1
    end

    def respawn(particle, scrolling = false)
      left, right = [@camera_x, @map_left].max, [@camera_x + Graphics.width, @map_right].min
      particle.x = left + @random.rand * [right - left, 0].max
      particle.y = @camera_y - @profile[:margin]
      # Renew only fully invisible particles at the entering edge of a scroll.
      # This maintains coverage without shifting any visible world trajectory.
      if scrolling && @camera_dx.abs > @camera_dy.abs
        particle.x = @camera_dx.positive? ? @camera_x + Graphics.width + @profile[:margin] + particle.sway :
                                          @camera_x - @profile[:margin] - particle.sway
        particle.y = @camera_y + @random.rand * Graphics.height
      elsif scrolling && @camera_dy.positive?
        particle.y = @camera_y + Graphics.height + @profile[:margin]
      end
      particle.phase = @random.rand * Math::PI * 2
      particle.wait = (@random.rand * @profile[:respawn_steps]).round
      particle.wait = 0 if scrolling # Enter from offscreen, never reveal a waiting leaf mid-screen.
    end

    def approach(value, target, amount)
      value + (target - value).clamp(-amount, amount)
    end

    def step(factors)
      duration = [@profile[:weather_transition_steps], 1].max
      @density = approach(@density, factors[:density], 1.0 / duration)
      @fall = approach(@fall, factors[:fall], 2.0 / duration)
      @wind = approach(@wind, factors[:wind], 3.0 / duration)
      fade = 1.0 / [@profile[:fade_steps], 1].max
      recycled = false
      @particles.each_with_index do |particle, index|
        target = (@density * @particles.size - index).clamp(0.0, 1.0)
        particle.alpha = approach(particle.alpha, target, fade)
        if particle.wait.positive?
          particle.wait -= 1
          next
        end
        particle.y += @profile[:fall_speed] * particle.speed * @fall
        particle.x += @profile[:drift_x] * particle.drift * @wind
        particle.phase += Math::PI * 2 / particle.period
        margin = @profile[:margin] + particle.sway
        x, y = particle.x - @camera_x, particle.y - @camera_y
        # Preserve the staggered entry above the screen while stationary.
        scrolling = !@camera_dx.zero? || !@camera_dy.zero?
        outside = y > Graphics.height + margin || x > Graphics.width + margin || x < -margin ||
                  (scrolling && y < -Graphics.height - margin)
        if outside && !recycled
          respawn(particle, scrolling)
          recycled = true # At most one renewal per logical step, never in draw.
        end
      end
    end

    def draw
      @particles.each_with_index do |particle, index|
        sprite = @sprites[index]
        wave = Math.sin(particle.phase)
        x = particle.x + wave * particle.sway - @camera_x
        y = particle.y - @camera_y
        sprite.set_position(x.round, y.round)
        sprite.angle = wave * @profile[:rotation]
        sprite.opacity = (particle.opacity * particle.alpha).round.clamp(0, 255)
        margin = @profile[:margin]
        sprite.visible = particle.wait.zero? && sprite.opacity.positive? &&
                         x >= -margin && x <= Graphics.width + margin &&
                         y >= -margin && y <= Graphics.height + margin
      end
    end
  end

  module FallingLeavesMapAdapter
    private

    def update_sprites
      super
      manager = BombanceAmbiance.manager
      if !manager.leaves_profile || !@leaves_manager.equal?(manager) ||
         (@ambiance_leaves && @ambiance_leaves.profile_name != manager.leaves_profile_name)
        @ambiance_leaves&.dispose
        @ambiance_leaves = nil
      end
      @leaves_manager = manager
      if manager.leaves_profile
        @ambiance_leaves ||= FallingLeaves.new(@viewport1, manager)
        @ambiance_leaves.update(manager)
      end
    end

    def dispose_sprites
      @ambiance_leaves&.dispose
      @ambiance_leaves = @leaves_manager = nil
      super
    end
  end

  module FallingLeavesBattleStart
    def setup_start_battle(klass, battle_info)
      result = super
      if battle_info && $game_temp.in_battle && $scene.is_a?(Battle::Scene)
        renderer = @spriteset&.instance_variable_get(:@ambiance_leaves)
        BombanceAmbiance.manager.suspend_leaves_for_battle(renderer, $scene)
      end
      result
    end
  end

  module FallingLeavesBattleReturn
    private

    def return_to_last_scene
      BombanceAmbiance.manager.finish_leaves_battle(self)
      super
    end
  end
end

BombanceAmbiance::Manager.prepend(BombanceAmbiance::FallingLeavesManagerAdapter)
Spriteset_Map.prepend(BombanceAmbiance::FallingLeavesMapAdapter)
Scene_Map.prepend(BombanceAmbiance::FallingLeavesBattleStart)
Battle::Scene.prepend(BombanceAmbiance::FallingLeavesBattleReturn) if defined?(Battle::Scene)
