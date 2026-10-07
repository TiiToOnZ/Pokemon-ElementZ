# Bombance extension for BBBB 1.0.1.0 / PSDK 26.60 and cc-sos-battles 1.2.0.0.
# Loaded after 00000 Plugins: observes the formation, never positions a Pokemon.
# Triple PNGs are optional. Existing BBBB configuration and sprite classes are reused.
module BombanceBattleBases
  TRIPLE_ASSETS = { player: 'player_base_triple', enemy: 'enemy_base_triple' }.freeze
  CONFIG_KEYS = %i[default_base_folder player_base_asset enemy_base_asset
                   player_base_double_asset enemy_base_double_asset].freeze

  module_function

  # Zero means no occupied formation; unexpected larger formats stop at three.
  def clamp_capacity(value)
    value.to_i.clamp(0, 3)
  end

  def candidate_capacities(capacity)
    clamp_capacity(capacity).downto(1).to_a
  end

  def asset_for(bank, capacity)
    return TRIPLE_ASSETS.fetch(Battle::BattleBases.side_key(bank)) if capacity == 3

    Battle::BattleBases.base_asset(bank, capacity)
  end

  # Anchors are sprite feet (x/y), not the centres of their image rectangles.
  def center(anchors)
    return nil if anchors.empty?

    [anchors.sum { |anchor| anchor[0] } / anchors.size.to_f,
     anchors.sum { |anchor| anchor[1] } / anchors.size.to_f]
  end

  def mean_depth(anchors)
    depths = anchors.map { |anchor| anchor[2] }.select { |z| z.is_a?(Numeric) && z.finite? && z > 0 }
    return 1 if depths.empty?

    depths.sum / depths.size.to_f
  end

  # Same path priority as BBBB, applied once for each candidate capacity.
  def asset_paths(asset, resource_path, background_name)
    paths = []
    paths << "#{resource_path}#{asset}" unless resource_path.nil?
    paths << "#{background_name}_#{asset}" if background_name && !background_name.empty?
    paths << Battle::BattleBases.default_base_filename(asset)
    paths.uniq
  end

  Side = Struct.new(:capacity, :anchors, :sprite, :filename, :placement)

  # One controller per Visual, two independent sides, no update/frame callback.
  class Controller
    def initialize(visual, scene, viewport, base_sprites, sprites_3d = nil, camera = nil)
      @visual = visual
      @scene = scene
      @viewport = viewport
      @base_sprites = base_sprites
      @sprites_3d = sprites_3d
      @camera = camera
      @sides = Array.new(2) { Side.new(0, {}, nil, nil, nil) }
      @asset_cache = {}
    end

    # Read-only diagnostic for event scripts / the console.
    def capacity(bank)
      @sides.fetch(bank).capacity
    end

    def refresh(background, background_name, formation_changed: false)
      return if @viewport.disposed?

      update_context(background, background_name)
      [1, 0].each { |bank| refresh_side(bank, formation_changed) }
    end

    def dispose
      @sides.each { |side| remove_sprite(side) }
      @asset_cache.clear
    end

    private

    # Compare values, including copies of strings, so an in-place config change
    # invalidates successes AND misses on the next explicit/event refresh.
    def update_context(background, background_name)
      resource_path = background.battle_base_resource_path if background.respond_to?(:battle_base_resource_path)
      values = [resource_path, background_name] + CONFIG_KEYS.map { |key| Battle::BattleBases.config[key] }
      context = [background] + values.map { |value| value.is_a?(String) ? value.dup : value }
      @asset_cache.clear if context != @context
      @context = context
      @resource_path = resource_path
      @background_name = background_name
    end

    def resolve_asset(bank, capacity)
      key = [bank, capacity]
      return @asset_cache[key] if @asset_cache.key?(key)

      @asset_cache[key] = BombanceBattleBases.candidate_capacities(capacity).lazy.flat_map do |candidate|
        asset = BombanceBattleBases.asset_for(bank, candidate)
        BombanceBattleBases.asset_paths(asset, @resource_path, @background_name)
      end.find { |path| RPG::Cache.battleback_exist?(path) }
    end

    # vs_type only bounds field slots: it NEVER supplies either side's capacity.
    # Logical identity + bank/position exclude reserves, trainers and empty SOS
    # preallocations. An entry not yet assigned to its sprite defers that side.
    def engaged_sprites(bank)
      sprites = {}
      BombanceBattleBases.clamp_capacity(@scene.battle_info.vs_type).times do |position|
        pokemon = @scene.logic.battler(bank, position)
        next unless pokemon && pokemon.bank == bank && pokemon.position == position

        sprite = @visual.battler_sprite(bank, position)
        return nil unless sprite && !sprite.disposed? && sprite.pokemon.equal?(pokemon)

        sprites[position] = sprite
      end
      sprites
    end

    # Never sample KO descent, ball entry or attack motion. Retain the last
    # stable slot anchor unless SOS has explicitly reset the whole formation.
    def stable_anchors(side, sprites, formation_changed)
      sprites.each_with_object({}) do |(position, sprite), anchors|
        moving = sprite.animation_handler && !sprite.done?
        if !formation_changed && (sprite.pokemon.dead? || moving)
          anchors[position] = side.anchors[position] if side.anchors.key?(position)
          next
        end

        x, y = sprite.x, sprite.y
        next unless [x, y].all? { |value| value.is_a?(Numeric) && value.finite? }

        # Capture formation geometry; artistic offsets stay on Pokemon/shadows.
        # Optional runtime lookup: 00021 is loaded after this extension.
        if defined?(BombanceTripleBattlePosition)
          dx, dy = BombanceTripleBattlePosition.visual_offset_for(sprite)
          x -= dx
          y -= dy
        end

        anchors[position] = [x, y, Battle::BattleBases.sprite_fake_z(sprite)]
      end
    end

    def refresh_side(bank, formation_changed)
      side = @sides.fetch(bank)
      return remove_sprite(side) if Battle::BattleBases.hidden_in_current_battle?(bank)

      sprites = engaged_sprites(bank)
      # A temporary empty/mismatched side keeps its last base and capacity.
      return if sprites.nil? || sprites.empty?

      anchors = stable_anchors(side, sprites, formation_changed)
      return if anchors.empty?

      side.capacity = [side.capacity, BombanceBattleBases.clamp_capacity(sprites.size)].max
      side.anchors = anchors
      filename = resolve_asset(bank, side.capacity)
      return remove_sprite(side) unless filename

      update_sprite(side, bank, filename)
      place_sprite(side)
    end

    def update_sprite(side, bank, filename)
      remove_sprite(side) if side.sprite&.disposed?
      unless side.sprite
        klass = @sprites_3d ? BattleUI::BattleBase3D : BattleUI::BattleBase2D
        side.sprite = klass.new(@viewport, filename)
        side.sprite.z = Battle::BattleBases.base_screen_z(bank)
        @base_sprites << side.sprite
        @sprites_3d << side.sprite if @sprites_3d
        @camera.apply_to(side.sprite) if @camera
        @viewport.sort_z
      end
      if side.filename && side.filename != filename
        side.sprite.set_bitmap(filename, :battleback)
        side.sprite.set_origin(side.sprite.width / 2, side.sprite.height / 2)
      end
      side.filename = filename
    end

    def place_sprite(side)
      placement = BombanceBattleBases.center(side.anchors.values)
      placement << BombanceBattleBases.mean_depth(side.anchors.values) if @sprites_3d
      return if placement == side.placement

      side.sprite.set_position(*placement)
      side.placement = placement
    end

    # Release only our sprites, never their shared cached bitmaps or battlers.
    def remove_sprite(side)
      if side.sprite
        @base_sprites.delete(side.sprite)
        @sprites_3d.delete(side.sprite) if @sprites_3d
        side.sprite.dispose unless side.sprite.disposed?
      end
      side.sprite = side.filename = side.placement = nil
    end
  end

  module VisualPatch
    attr_reader :bombance_battle_bases

    # This returns after PSDK, BBBB's wrapper, SOS preallocation and boss bars.
    # In 3D the enclosing Visual3D#create_graphics applies its camera afterwards.
    def create_graphics
      result = super
      @battle_base_sprites ||= []
      @bombance_battle_bases ||= Controller.new(self, @scene, @viewport, @battle_base_sprites, @sprites3D, @camera)
      refresh_bombance_battle_bases(formation_changed: true)
      result
    end

    # Public event API for future formation/background changes; call only after
    # placement settles. Set formation_changed when all slots were repositioned.
    # Repeated calls reuse both sprites and cached asset resolution (even nil).
    def refresh_bombance_battle_bases(formation_changed: false)
      return unless @bombance_battle_bases

      @bombance_battle_bases.refresh(@background, background_name, formation_changed: formation_changed)
    end

    def refresh_field_positions
      result = super
      refresh_bombance_battle_bases(formation_changed: true)
      result
    end

    # SOS waits for the entry animation before returning: now the extra slot
    # really has a Pokemon and the anchors are final (unlike the earlier reset).
    def show_incoming_battler(battler, from_ball: true)
      result = super
      refresh_bombance_battle_bases
      result
    end

    def reseat_battler(battler)
      result = super
      refresh_bombance_battle_bases(formation_changed: true)
      result
    end

    def background=(background)
      result = super
      refresh_bombance_battle_bases
      result
    end

    def dispose
      @bombance_battle_bases&.dispose
      @bombance_battle_bases = nil
      super
    end

    private

    # Deliberately no super: suppress ONLY BBBB's original base creation.
    # The original create_battlers chain (including SOS) remains untouched.
    def create_battle_bases_2d
      nil
    end
  end

  module Visual3DPatch
    private

    # Defined here because BBBB's 3D module precedes all Visual ancestors.
    def create_battle_bases_3d
      nil
    end
  end
end

Battle::Visual.prepend(BombanceBattleBases::VisualPatch)
Battle::Visual3D.prepend(BombanceBattleBases::Visual3DPatch)
