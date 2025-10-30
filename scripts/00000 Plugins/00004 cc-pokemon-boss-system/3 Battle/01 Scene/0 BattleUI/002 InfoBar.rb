module BattleUI
  class InfoBar < UI::SpriteStack
    module InfoBarBossPatch
      # Get the pokemon HP bars.
      # @return [Array<Sprite>]
      attr_reader :bars_hp

      # Create a new InfoBar.
      # @param viewport [Viewport]
      # @param scene [Battle::Scene]
      # @param pokemon [PFM::Pokemon]
      # @param bank [Integer]
      # @param position [Integer]
      def initialize(viewport, scene, pokemon, bank, position)
        @bars_hp = []
        super
      end

      private

      # Creates all the sprites used by the InfoBar.
      # If the Pokemon is a boss, it also creates reserve HP bars.
      def create_sprites
        super
        create_reserve_hp if enemy_boss?
      end

      # Creates additional HP bars if the Pokemon is a boss.
      def create_reserve_hp
        # @type [PFM::PokemonBattler]
        boss_pokemon = @scene.logic.battler(bank, position)
        return unless boss_pokemon

        total_bars  = 5
        filled_bars = boss_pokemon.nb_bars_hp
        x_start     = @is_triple_battle ? 42 : 57
        x_offset    = @is_triple_battle ? 11 : 14

        total_bars.times do |index|
          bar = add_sprite(x_start + index * x_offset, 22, self.class::NO_INITIAL_IMAGE, type: ReserveHP)
          bar.switch_state(filled: false) if index >= filled_bars
          @bars_hp << bar
        end
      end
    end

    prepend InfoBarBossPatch

    class Background < ShaderedSprite
      module BackgroundBossPatch
        # Gets the filename for the background image.
        # Uses a different background if the Pokemon is a boss.
        # @param pokemon [PFM::Pokemon] The Pokemon data.
        # @return [String] The filename of the background image.
        def background_filename(pokemon)
          return "battle/boss/battle_bar_boss#{suffix_3v3}" if pokemon.boss? && pokemon.bank == 1

          super
        end
      end

      prepend BackgroundBossPatch
    end

    class ReserveHP < ShaderedSprite
      # Create a new ReserveHP sprite.
      # @param viewport [Viewport]
      def initialize(viewport)
        super(viewport)
        set_bitmap(reserve_hp_filename, :interface)
      end

      # Switches the sprite to the filled or empty HP bar image.
      # @param filled [Boolean] whether the HP bar should be filled or empty.
      def switch_state(filled: true)
        set_bitmap(filled ? reserve_hp_filename : empty_hp_filename, :interface)
      end

      # Gets the filename for the filled reserve HP bar image.
      # @return [String]
      def reserve_hp_filename
        return "battle/boss/hp_bar_filled#{suffix_3v3}"
      end

      # Gets the filename for the empty reserve HP bar image.
      # @return [String]
      def empty_hp_filename
        return "battle/boss/hp_bar_empty#{suffix_3v3}"
      end

      # Return a suffix for 3v3 battle resources
      # @return [String]
      def suffix_3v3
        return $game_temp.vs_type == 3 ? '_3v3' : ''
      end
    end
  end
end
