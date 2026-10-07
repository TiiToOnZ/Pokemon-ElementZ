# Kit scenery adapter for PSDK 26.60. Only Visual3D is extended.
# Assets remain untouched. No camera, battler, formation or base configuration.
module BombanceBattlebacks3DKit
  PERIODS = %w[morning day sunset night].freeze
  # Explicit sizes also detect a failed RPG::Cache load (its placeholder texture).
  # Cloud is a wide image, not a two-frame spritesheet. Keep it static for now.
  BATTLEBACKS = {
    'back_grass' => {
      folder: 'battleback3dkit/grass/',
      layers: [
        { name: 'sky', width: 448, height: 360, screen_z: 1 }.freeze,
        { name: 'cloud', width: 896, height: 360, screen_z: 2 }.freeze,
        { name: 'back', width: 448, height: 360, screen_z: 3 }.freeze
      ].freeze
    }.freeze,

    'back_tall_grass' => {
      folder: 'battleback3dkit/tall_grass/',
      layers: [
        { name: 'sky', width: 448, height: 360, screen_z: 1 }.freeze,
        { name: 'cloud', width: 896, height: 360, screen_z: 2 }.freeze,
        { name: 'back', width: 448, height: 360, screen_z: 3 }.freeze
      ].freeze
    }.freeze
  }.freeze

  module_function

  # Strip only PSDK's known time suffix. Custom/trainer names keep native behavior.
  def environment_key(background_name)
    background_name.to_s.sub(/_(morning|day|sunset|night)\z/, '')
  end

  # Same time gates and switch precedence as PSDK. No second clock.
  def period
    return 'day' unless $game_switches[Yuki::Sw::TJN_Enabled] && $game_switches[Yuki::Sw::Env_CanFly]

    switches = [Yuki::Sw::TJN_MorningTime, Yuki::Sw::TJN_DayTime,
                Yuki::Sw::TJN_SunsetTime, Yuki::Sw::TJN_NightTime]
    index = switches.index { |id| $game_switches[id] }
    index ? PERIODS[index] : 'day'
  end

  def report(message)
    log_debug("[Battlebacks3DKit] #{message}")
  rescue StandardError
    warn("[Battlebacks3DKit] #{message}")
  end

  # Select a COMPLETE set: never combine a night sky with a day ground.
  # Reuse the 2D suffix table (morning -> day, sunset -> night).
  # There is no unsuffixed Grass asset; an incomplete set falls back to native 3D.
  def resolve(background_name, registry = BATTLEBACKS)
    # Creation-only diagnostics: report through PSDK's debug console, never update.
    key = environment_key(background_name)
    config = registry[key]
    report("requested background: #{background_name.inspect}")
    report("normalized background: #{key.inspect}")
    report("environment: #{config ? key : '(not registered)'}")
    unless config
      report("FALLBACK: no Kit environment registered for #{key.inspect}")
      return nil
    end
    validate_config(config)
    requested = period
    report("period: #{requested}")
    candidates = Battle::Logic::BattleInfo::TIMED_BACKGROUND_SUFFIXES.fetch(PERIODS.index(requested))
    candidates.each do |candidate|
      paths = config[:layers].map { |layer| "#{config[:folder]}#{layer[:name]}_#{candidate}" }
      config[:layers].zip(paths).each do |layer, path|
        report("#{layer[:name]} path (#{candidate}): #{path} -> graphics/battlebacks/#{path}.png")
      end
      missing = paths.reject { |path| RPG::Cache.battleback_exist?(path) }
      unless missing.empty?
        report("Incomplete #{candidate} set: #{missing.join(', ')}")
        next
      end
      report("Using #{candidate} instead of #{requested}") if candidate != requested
      return { config: config, period: candidate, paths: paths }
    end
    report("FALLBACK: no complete #{requested} set for #{background_name.inspect}")
    nil
  rescue StandardError => e
    report("FALLBACK: resolving #{background_name.inspect}: #{e.class}: #{e.message} (#{e.backtrace&.first})")
    nil
  end

  def validate_config(config)
    raise ArgumentError, 'Kit configuration must be a Hash' unless config.is_a?(Hash)
    folder = config[:folder]
    unless folder.is_a?(String) && folder.match?(%r{\A[a-z0-9_ /-]+/\z}) && !folder.start_with?('/')
      raise ArgumentError, 'Invalid Kit resource folder'
    end
    layers = config[:layers]
    raise ArgumentError, 'Kit layers must not be empty' unless layers.is_a?(Array) && !layers.empty?

    layers.each do |layer|
      valid = layer.is_a?(Hash) && layer[:name].is_a?(String) && layer[:name].match?(/\A[a-z0-9_]+\z/)
      valid &&= %i[width height].all? { |key| layer[key].is_a?(Integer) && layer[key] > 0 }
      valid &&= layer[:screen_z].is_a?(Integer) && (1...30).cover?(layer[:screen_z])
      raise ArgumentError, 'Invalid Kit layer (must stay below terrain z=30)' unless valid
    end
    names = layers.map { |layer| layer[:name] }
    raise ArgumentError, 'Kit scenery requires its back layer' unless names.include?('back')
    raise ArgumentError, 'Duplicate Kit layer name' unless names.uniq.size == layers.size
    raise ArgumentError, 'Duplicate Kit layer depth' unless layers.map { |layer| layer[:screen_z] }.uniq.size == layers.size
  end

  class Background < BattleUI::Battleback3D
    attr_reader :kit_period

    def initialize(viewport, scene, selection)
      @kit_selection = selection
      @kit_period = selection.fetch(:period)
      super(viewport, scene)
    rescue StandardError
      dispose
      raise
    end

    # Preserve BBBB's old local-base lookup before named/default bases.
    # Kit's back/cloud/sky are scenery, never base resources.
    def battle_base_resource_path
      'animated_camera/BattleBack Forest/'
    end

    # Native Battleback3D stores its sprites outside SpriteStack#stack. Own both
    # collections here, including partial construction, without disposing textures
    # shared by RPG::Cache. Visual can dispose a background more than once.
    def dispose
      return if @kit_disposed

      @kit_disposed = true
      if @terrain_animation
        @terrain_animation.current_terrain_animation&.animation_handler&.clear
        @terrain_animation.animation_handler.clear
        @terrain_animation.stop_current_animation
      end
      @animations&.clear
      sprites = [*@battleback_list, *@stack, @terrain_sprite, @move_plane_background, @move_background].compact.uniq
      sprites.each { |sprite| sprite.dispose unless sprite.disposed? }
      @battleback_list&.clear
      @stack&.clear
      @terrain_sprite = @move_plane_background = @move_background = @terrain_animation = nil
      @kit_selection = @scene = @viewport = nil
    end

    private

    def resource_path
      @kit_selection.fetch(:config).fetch(:folder)
    end

    def create_graphics
      @kit_selection[:config][:layers].zip(@kit_selection[:paths]).each do |layer, path|
        sprite = BattleUI::Sprite3D.new(@viewport)
        # Register before loading: a failure must also dispose this partial sprite.
        @battleback_list << sprite
        sprite.set_bitmap(path, :battleback)
        unless sprite.width == layer[:width] && sprite.height == layer[:height]
          raise ArgumentError, "Invalid texture #{path}: #{sprite.width}x#{sprite.height}"
        end
        # 448x360 matches the native field. At 320x240 this is (-224, -188),
        # leaving 64px horizontally, 68px above and 52px below the neutral view.
        # All layers share that origin; cloud extends 448px further to the right.
        sprite.set_origin(0, 0)
        sprite.set_position(-(Graphics.width / 2 + MARGIN_X), -(Graphics.height / 2 + MARGIN_Y))
        sprite.zoom = 1
        sprite.z = layer[:screen_z]
        # Rendering order MUST NOT become projection depth.
        sprite.shader.set_float_uniform('z', 1)
      end
      # Preserve PSDK's terrain z=30, attack Plane3D/background z=50 and manager.
      super
      # SpriteStack movement (e.g. Boss shakes) requires position readers/writers.
      # Plane3D deliberately has no x/y: ox/oy scroll its texture instead. Keep
      # that attack plane in battleback_list for camera/disposal, outside stack.
      @stack.concat(@battleback_list.select do |sprite|
        %i[x x= y y=].all? { |method| sprite.respond_to?(method) }
      end)
    end
  end

  module Visual3DPatch
    private

    def create_background
      selection = BombanceBattlebacks3DKit.resolve(background_name)
      return super unless selection

      begin
        @background = Background.new(@viewport, @scene, selection)
        BombanceBattlebacks3DKit.report("Kit background selected: #{@background.class}, period: #{selection[:period]}")
      rescue StandardError => e
        BombanceBattlebacks3DKit.report("FALLBACK: creation failed: #{e.class}: #{e.message} (#{e.backtrace&.first})")
        return super
      end
    end
  end
end

Battle::Visual3D.prepend(BombanceBattlebacks3DKit::Visual3DPatch)
