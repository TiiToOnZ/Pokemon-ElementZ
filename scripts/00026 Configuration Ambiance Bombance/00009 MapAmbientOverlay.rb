# frozen_string_literal: true

module BombanceAmbiance
  # Complete map image, never a repeating Plane. Native fog stays independent.
  class MapAmbientOverlay
    Source = Struct.new(:key, :map_id, :texture, :profile, :x, :y, :width, :height)
    attr_reader :sprites

    # Periodic interpolation, driven only by the TJN hour/minute variables.
    # No startup fade: a recreated map immediately has the current intensity.
    def self.opacity(profile, minute)
      points = profile.fetch(:time_points)
      minute %= 1440
      index = points.index { |point| point[0] > minute }
      right = index ? points[index] : [points.first[0] + 1440, points.first[1]]
      left = index == 0 ? [points.last[0] - 1440, points.last[1]] : points[(index || points.size) - 1]
      fraction = (minute - left[0]).to_f / (right[0] - left[0])
      percent = left[1] + (right[1] - left[1]) * fraction
      profile.fetch(:max_opacity) * percent.clamp(0, 100) / 100.0
    end

    def initialize(viewport)
      @viewport, @sprites, @sources = viewport, {}, {}
    end

    def update(manager)
      camera_x = $game_map.display_x / 8.0 + manager.state.anchor_x * 16
      camera_y = $game_map.display_y / 8.0 + manager.state.anchor_y * 16
      minute = Configuration.rays_minute
      active = []

      manager.ambient_sources.each do |source|
        opacity = if manager.context.tjn_enabled
                    self.class.opacity(source.profile, minute).round.clamp(0, 255)
                  else
                    0
                  end

        x, y = source.x - camera_x, source.y - camera_y

        next if opacity.zero? || x >= Graphics.width || y >= Graphics.height ||
                x + source.width <= 0 || y + source.height <= 0

        key = source.key
        active << key

        if @sources[key] != source
          @sprites.delete(key)&.dispose
          @sources[key] = source
        end

        sprite = @sprites[key] ||= create_sprite(source)
        sprite.set_position(x, y)
        sprite.opacity = opacity
      end

      (@sprites.keys - active).each do |key|
        @sprites.delete(key).dispose
        @sources.delete(key)
      end
    end

    def dispose
      @sprites.each_value { |sprite| sprite.dispose unless sprite.disposed? }
      @sprites.clear
      @sources.clear
    end

    private

    def create_sprite(source)
      sprite = Sprite::WithColor.new(@viewport)
      # Borrowed cache texture: do not free a texture shared with native PSDK.
      sprite.bitmap = RPG::Cache.fog(source.texture)
      sprite.zoom_x = sprite.zoom_y = 16.0 / source.profile.fetch(:pixels_per_tile) * source.profile.fetch(:scale)
      sprite.z = source.profile.fetch(:z)
      sprite.shader.blend_type = source.profile.fetch(:blend_type)
      @viewport.sort_z
      sprite
    rescue StandardError
      sprite&.dispose
      raise
    end
  end

  module MapAmbientOverlayManager
    attr_reader :ambient_sources

    def override_effects(map_id, **effects)
      keys = %i[map_ambient_overlay map_ambient_windows]
      enabled_keys = keys.select { |key| effects.key?(key) }

      return super if enabled_keys.empty?

      overrides = {}

      enabled_keys.each do |key|
        enabled = effects.delete(key)

        unless enabled == true || enabled == false
          raise ArgumentError, "#{key} expects true/false"
        end

        overrides[key] = enabled
      end

      super(map_id, **effects)

      @event_overrides[map_id] =
        @event_overrides[map_id].merge(overrides).freeze
    end

    def sync_context(map)
      super
      maps = Yuki::MapLinker.map_datas
      signature = [map.map_id, @configuration_revision, maps.object_id, @state.anchor_x, @state.anchor_y,
                   $game_switches[Yuki::Sw::MapLinkerDisabled]]
      return if signature == @ambient_signature

      @ambient_signature = signature
      sources = []
      append_ambient_source(sources, map.map_id, @state.anchor_x, @state.anchor_y, map.width, map.height)
      if !signature.last && maps.first&.map_id == map.map_id
        maps.each do |data|
          next if data.map_id == map.map_id

          append_ambient_source(sources, data.map_id, @state.anchor_x - data.offset_x,
                                @state.anchor_y - data.offset_y, data.map.width, data.map.height)
        end
      end
      @ambient_sources = sources.freeze
    end

    private

    def append_ambient_source(sources, id, x, y, width, height)
      settings = Configuration.resolve(id, @event_overrides[id])

      if settings[:map_ambient_overlay] == true
        append_texture_source(
          sources, id, :ambience,
          settings[:map_ambient_overlay_texture],
          settings[:map_ambient_overlay_profile],
          x, y, width, height
        )
      end

      if settings[:map_ambient_windows] == true
        append_texture_source(
          sources, id, :windows,
          settings[:map_ambient_windows_texture],
          settings[:map_ambient_windows_profile],
          x, y, width, height
        )
      end
    end

    def append_texture_source(sources, id, layer, texture, profile_name,
                              x, y, width, height)
      profile = Settings::MAP_AMBIENT_OVERLAY_PROFILES.fetch(profile_name)

      if !texture || texture.empty?
        raise ArgumentError, "Missing ambient overlay texture for map #{id}"
      end

      zoom = 16.0 / profile.fetch(:pixels_per_tile) * profile.fetch(:scale)

      sources << MapAmbientOverlay::Source.new(
        [id, layer].freeze,
        id,
        texture,
        profile,
        x * 16 + profile[:offset_x] * zoom,
        y * 16 + profile[:offset_y] * zoom,
        width * 16 * profile[:scale],
        height * 16 * profile[:scale]
      ).freeze
    end
  end

  module MapAmbientOverlayAdapter
    private

    def update_sprites
      super
      manager = BombanceAmbiance.manager
      if !@ambient_overlay_manager.equal?(manager) || manager.ambient_sources.empty?
        @ambiance_overlay&.dispose
        @ambiance_overlay = nil
      end
      @ambient_overlay_manager = manager
      return if manager.ambient_sources.empty?

      @ambiance_overlay ||= MapAmbientOverlay.new(@viewport1)
      @ambiance_overlay.update(manager)
    end

    def dispose_sprites
      @ambiance_overlay&.dispose
      @ambiance_overlay = @ambient_overlay_manager = nil
      super
    end
  end
end

BombanceAmbiance::Manager.prepend(BombanceAmbiance::MapAmbientOverlayManager)
Spriteset_Map.prepend(BombanceAmbiance::MapAmbientOverlayAdapter)
