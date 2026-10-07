# BBBB : Bring Back Battle Bases
#
# Author : Raty
# License : MIT
#
# GitHub Repo :
# https://github.com/RatyHub/BBBB

module Configs
  module Project
    class BattleBases
      FILENAME = File.join('plugins', 'battle_bases_config')

      attr_accessor :default_base_folder
      attr_accessor :player_base_asset
      attr_accessor :enemy_base_asset
      attr_accessor :player_base_double_asset
      attr_accessor :enemy_base_double_asset
      attr_accessor :above_battle_base_screen_z_offset

      def initialize
        @default_base_folder = 'default_bases'
        @player_base_asset = 'player_base'
        @enemy_base_asset = 'enemy_base'
        @player_base_double_asset = 'player_base_double'
        @enemy_base_double_asset = 'enemy_base_double'
        @above_battle_base_screen_z_offset = 1
      end

      def to_h
        return {
          default_base_folder: @default_base_folder,
          player_base_asset: @player_base_asset,
          enemy_base_asset: @enemy_base_asset,
          player_base_double_asset: @player_base_double_asset,
          enemy_base_double_asset: @enemy_base_double_asset,
          above_battle_base_screen_z_offset: @above_battle_base_screen_z_offset
        }
      end
    end
  end

  register(:battle_bases, Project::BattleBases::FILENAME, :json, true, Project::BattleBases)
end

module Battle
  module BattleBases
    module_function

    # @param bank [Integer]
    # @return [Symbol]
    def side_key(bank)
      bank == 0 ? :player : :enemy
    end

    # @param bank [Integer]
    # @param vs_type [Integer, nil]
    # @return [String]
    def base_asset(bank, vs_type = nil)
      if vs_type == 2
        return side_key(bank) == :player ? config[:player_base_double_asset] : config[:enemy_base_double_asset]
      end

      return side_key(bank) == :player ? config[:player_base_asset] : config[:enemy_base_asset]
    end

    # @param bank [Integer]
    # @return [Integer]
    def base_screen_z(bank)
      side_key(bank) == :player ? 500 : 100
    end

    # @param offset [Integer]
    # @return [Integer]
    def above_battle_base_screen_z(offset = config[:above_battle_base_screen_z_offset])
      500 + offset
    end

    # @param bank [Integer]
    # @return [Boolean]
    def hidden_in_current_battle?(bank)
      return false unless side_key(bank) == :player

      $game_variables[Yuki::Var::BT_Mode] == 5
    end

    # @param background [BattleUI::Battleback3D, Sprite]
    # @param bank [Integer]
    # @param background_name [String, nil]
    # @param vs_type [Integer, nil]
    # @return [String, nil]
    def base_filename(background, bank, background_name = nil, vs_type = nil)
      asset = base_asset(bank, vs_type)
      tested_filenames = []

      local_filename = "#{background.battle_base_resource_path}#{asset}" if background.respond_to?(:battle_base_resource_path)
      tested_filenames << local_filename if local_filename
      if local_filename && RPG::Cache.battleback_exist?(local_filename)
        log("using battleback base side=#{side_key(bank).inspect}, asset=#{local_filename.inspect}")
        return local_filename
      end

      background_filename = "#{background_name}_#{asset}" if background_name && !background_name.empty?
      tested_filenames << background_filename if background_filename
      if background_filename && RPG::Cache.battleback_exist?(background_filename)
        log("using named battleback base side=#{side_key(bank).inspect}, asset=#{background_filename.inspect}")
        return background_filename
      end

      default_filename = default_base_filename(asset)
      if RPG::Cache.battleback_exist?(default_filename)
        log("using default base side=#{side_key(bank).inspect}, tested=#{tested_filenames.inspect}, asset=#{default_filename.inspect}")
        return default_filename
      end

      log("missing base side=#{side_key(bank).inspect}, tested=#{tested_filenames.inspect}, fallback=#{default_filename.inspect}")
      return nil
    end

    # @param asset [String]
    # @return [String]
    def default_base_filename(asset)
      folder = config[:default_base_folder]
      return asset if folder.empty?

      return "#{folder}/#{asset}"
    end

    # @return [Hash]
    def config
      @config ||= load_config
    end

    # Reload the JSON config and regenerate its release-ready RXDATA in development.
    # @return [Boolean]
    def reload_config
      unless PSDK_CONFIG.release?
        Configs.register(:battle_bases, Configs::Project::BattleBases::FILENAME, :json, true, Configs::Project::BattleBases)
      end
      @config = load_config
      return true
    end

    # @return [Hash]
    def load_config
      return build_config(read_config_file)
    rescue StandardError => e
      log_error("Failed to load config file #{config_filename}: #{e.class}: #{e.message}")
      return default_config
    end

    # @return [Hash]
    def read_config_file
      data = Configs.battle_bases.to_h
      return data if data.is_a?(Hash)

      log_error("Compiled config #{config_filename} should contain an object; using defaults")
      return {}
    end

    # @param data [Hash]
    # @return [Hash]
    def build_config(data)
      defaults = default_config
      return {
        default_base_folder: parse_folder(data[:default_base_folder], defaults[:default_base_folder], :default_base_folder),
        player_base_asset: parse_asset(data[:player_base_asset], defaults[:player_base_asset], :player_base_asset),
        enemy_base_asset: parse_asset(data[:enemy_base_asset], defaults[:enemy_base_asset], :enemy_base_asset),
        player_base_double_asset: parse_asset(
          data[:player_base_double_asset],
          defaults[:player_base_double_asset],
          :player_base_double_asset
        ),
        enemy_base_double_asset: parse_asset(
          data[:enemy_base_double_asset],
          defaults[:enemy_base_double_asset],
          :enemy_base_double_asset
        ),
        above_battle_base_screen_z_offset: parse_integer(
          data[:above_battle_base_screen_z_offset],
          defaults[:above_battle_base_screen_z_offset],
          :above_battle_base_screen_z_offset
        )
      }
    end

    # @return [Hash]
    def default_config
      return {
        default_base_folder: 'default_bases',
        player_base_asset: 'player_base',
        enemy_base_asset: 'enemy_base',
        player_base_double_asset: 'player_base_double',
        enemy_base_double_asset: 'enemy_base_double',
        above_battle_base_screen_z_offset: 1
      }
    end

    # @return [String]
    def config_filename
      return File.join('Data', 'configs', 'plugins', 'battle_bases_config.json')
    end

    # @param value [Object]
    # @param fallback [String]
    # @param key [Symbol]
    # @return [String]
    def parse_folder(value, fallback, key)
      return fallback if value.nil?

      folder = value.to_s.strip.gsub('\\', '/').gsub(%r{\A/+|/+\z}, '')
      return folder
    rescue StandardError
      log_error("Invalid #{key}: #{value.inspect}; using default")
      return fallback
    end

    # @param value [Object]
    # @param fallback [String]
    # @param key [Symbol]
    # @return [String]
    def parse_asset(value, fallback, key)
      return fallback if value.nil?

      asset = value.to_s.strip.gsub('\\', '/').gsub(%r{\A/+|/+\z}, '')
      return asset unless asset.empty?

      log_error("Invalid #{key}: empty value; using default")
      return fallback
    rescue StandardError
      log_error("Invalid #{key}: #{value.inspect}; using default")
      return fallback
    end

    # @param value [Object]
    # @param fallback [Integer]
    # @param key [Symbol]
    # @return [Integer]
    def parse_integer(value, fallback, key)
      return fallback if value.nil?

      return Integer(value)
    rescue ArgumentError, TypeError
      log_error("Invalid #{key}: #{value.inspect}; using default")
      return fallback
    end

    # @param message [String]
    def log(message)
      log_info(message)
    rescue StandardError
      nil
    end

    # @param positions [Array<Array<Integer>>]
    # @return [Array<Float>]
    def group_center(positions)
      return positions.first if positions.size == 1

      first = positions.first
      last = positions.last
      [(first[0] + last[0]) / 2.0, (first[1] + last[1]) / 2.0]
    end

    # @param sprite [BattleUI::PokemonSprite3D]
    # @return [Numeric, nil]
    def sprite_fake_z(sprite)
      return sprite.shader_z_position if sprite.respond_to?(:shader_z_position)
    rescue StandardError
      nil
    end

    # @param sprites [Array<BattleUI::PokemonSprite3D>]
    # @return [Numeric]
    def group_fake_z(sprites)
      fake_z_values = sprites.filter_map { |sprite| sprite_fake_z(sprite) }
      return 1 if fake_z_values.empty?
      return fake_z_values.first if fake_z_values.size == 1

      (fake_z_values.first + fake_z_values.last) / 2.0
    end
  end

  class Visual
    module BattleBasesVisual2DPatch
      def create_battlers
        super
        create_battle_bases_2d
      end

      private

      def create_battle_bases_2d
        return if defined?(Battle::Visual3D) && is_a?(Battle::Visual3D)

        @battle_base_sprites = []
        [1, 0].each { |bank| create_battle_base_2d(bank) }
        @viewport&.sort_z
      end

      # @param bank [Integer]
      def create_battle_base_2d(bank)
        if BattleBases.hidden_in_current_battle?(bank)
          BattleBases.log('skip player base in safari battle')
          return
        end

        positions = active_battle_base_positions(bank)
        return if positions.empty?

        x, y = BattleBases.group_center(positions)

        filename = BattleBases.base_filename(@background, bank, background_name, @scene.battle_info.vs_type)
        return unless filename

        sprite = BattleUI::BattleBase2D.new(@viewport, filename)
        sprite.set_position(x, y)
        sprite.z = BattleBases.base_screen_z(bank)
        @battle_base_sprites << sprite
      end

      # @param bank [Integer]
      # @return [Array<Array<Integer>>]
      def active_battle_base_positions(bank)
        vs_type = @scene.battle_info.vs_type
        (0...vs_type).filter_map do |position|
          sprite = battler_sprite(bank, position)
          [sprite.x, sprite.y] if sprite && !sprite.disposed? && sprite.pokemon
        end
      end
    end

    prepend BattleBasesVisual2DPatch
  end

  class Visual3D
    module BattleBasesVisual3DPatch
      def create_battlers
        super
        create_battle_bases_3d
      end

      private

      def create_battle_bases_3d
        @battle_base_sprites = []
        [1, 0].each { |bank| create_battle_base_3d(bank) }
        Graphics.sort_z
      end

      # @param bank [Integer]
      def create_battle_base_3d(bank)
        if BattleBases.hidden_in_current_battle?(bank)
          BattleBases.log('skip player base in safari battle')
          return
        end

        pokemon_sprites = active_battle_base_sprites(bank)
        return if pokemon_sprites.empty?

        positions = pokemon_sprites.map { |sprite| [sprite.x, sprite.y] }
        x, y = BattleBases.group_center(positions)
        fake_z = BattleBases.group_fake_z(pokemon_sprites)

        filename = BattleBases.base_filename(@background, bank, background_name, @scene.battle_info.vs_type)
        return unless filename

        sprite = BattleUI::BattleBase3D.new(@viewport, filename)
        sprite.set_position(x, y, fake_z)
        sprite.z = BattleBases.base_screen_z(bank)
        @sprites3D << sprite
        @battle_base_sprites << sprite
      end

      # @param bank [Integer]
      # @return [Array<BattleUI::PokemonSprite3D>]
      def active_battle_base_sprites(bank)
        vs_type = @scene.battle_info.vs_type
        (0...vs_type).filter_map do |position|
          sprite = battler_sprite(bank, position)
          sprite if sprite && !sprite.disposed? && sprite.pokemon
        end
      end
    end

    prepend BattleBasesVisual3DPatch
  end
end

module BattleUI
  class Battleback3D
    def battle_base_resource_path
      @path || resource_path
    end

    private

    # @param path [String]
    # @param name [String]
    # @param x [Numeric]
    # @param y [Numeric]
    # @param fake_z [Numeric]
    # @param zoom [Numeric]
    # @param screen_z_offset [Integer]
    # @return [BattleUI::BattlebackForeground3D]
    def add_battleback_element_above_battle_base(
      path,
      name,
      x = -(Graphics.width / 2 + MARGIN_X),
      y = -(Graphics.height / 2 + MARGIN_Y),
      fake_z = 1,
      zoom = 1,
      screen_z_offset = Battle::BattleBases.config[:above_battle_base_screen_z_offset]
    )
      filename = timed_background_names(path + name)
      screen_z = Battle::BattleBases.above_battle_base_screen_z(screen_z_offset)
      sprite = BattlebackForeground3D.new(@viewport, filename, screen_z, fake_z)
      sprite.set_position(x, y)
      sprite.zoom = zoom
      @battleback_list << sprite
      return sprite
    end
  end

  class BattlebackForeground3D < ShaderedSprite
    def initialize(viewport, filename, screen_z, fake_z = 1)
      super(viewport)
      self.shader = Shader.create(:fake_3d)
      set_bitmap(filename, :battleback)
      self.z = screen_z
      self.fake_z = fake_z
    end

    # @param x [Numeric]
    # @param y [Numeric]
    # @param fake_z [Numeric, nil]
    # @return [self]
    def set_position(x, y, fake_z = nil)
      super(x, y)
      self.fake_z = fake_z if fake_z
      self
    end

    # @param value [Numeric]
    def fake_z=(value)
      shader.set_float_uniform('z', value)
    end
  end

  class BattleBase2D < ShaderedSprite
    def initialize(viewport, filename)
      super(viewport)
      set_bitmap(filename, :battleback)
      set_origin(width / 2, height / 2)
    end

    # @param x [Numeric]
    # @param y [Numeric]
    # @return [self]
    def set_position(x, y)
      super
      self
    end
  end

  class BattleBase3D < ShaderedSprite
    def initialize(viewport, filename)
      super(viewport)
      self.shader = Shader.create(:fake_3d)
      set_bitmap(filename, :battleback)
      set_origin(width / 2, height / 2)
      self.fake_z = 1
    end

    # @param x [Numeric]
    # @param y [Numeric]
    # @param fake_z [Numeric, nil]
    # @return [self]
    def set_position(x, y, fake_z = nil)
      super(x, y)
      self.fake_z = fake_z if fake_z
      self
    end

    # @param value [Numeric]
    def fake_z=(value)
      shader.set_float_uniform('z', value)
    end
  end

end
