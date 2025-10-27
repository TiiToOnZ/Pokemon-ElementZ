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

      # Get the base position of the Pokemon in 2v2+
      # @return [Array(Integer, Integer)]
      def base_position_v2
        return 20, 9 if enemy?

        return 2, 195
      end

      # Get the offset position of the Pokemon in 2v2+
      # @return [Array(Integer, Integer)]
      def offset_position_v2
        return 150, 3 if enemy?

        return 136, -3
      end

      # Creates all the sprites used by the InfoBar.
      # If the Pokemon is a boss, it also creates reserve HP bars.
      def create_sprites
        super
        create_reserve_hp if enemy_boss?
      end

      # Creates the background sprite for the InfoBar.
      # If the Pokemon is a boss, a different background is used.
      def create_background
        return (@background = add_sprite(-15, -5, self.class::NO_INITIAL_IMAGE, type: Background)) if enemy_boss?

        super
      end

      # Creates the experience bar sprite for the InfoBar.
      # The experience bar is not created if the Pokemon is a boss.
      def create_exp
        return if enemy_boss?

        super
      end

      # Calculates the coordinates of the HP background sprite.
      # Adjusts the position if the Pokemon is a boss.
      # @return [Array(Integer, Integer)] The coordinates for the HP background.
      def hp_background_coordinates
        return [0, 12] if enemy_boss?

        super
      end

      # Calculates the coordinates of the HP bar sprite.
      # Adjusts the position if the Pokemon is a boss.
      # @return [Array(Integer, Integer)] The coordinates for the HP bar.
      def hp_bar_coordinates
        return [x + 15, y + 13] if enemy_boss?

        super
      end

      # Creates the name text sprite for the InfoBar.
      # Adjusts the position if the Pokemon is a boss.
      def create_name
        if enemy_boss?
          return with_font(20) do
            @name = add_text(0, -4, 0, 16, :given_name, 0, 1, color: 10, type: self.class::SymText)
          end
        end

        super
      end

      # Creates the sprite indicating if the Pokemon has been caught.
      # Adjusts the position if the Pokemon is a boss.
      def create_catch_sprite
        return add_sprite(110, 10, 'battle/ball', type: PokemonCaughtSprite) if enemy_boss?

        super
      end

      # Creates the gender icon sprite for the InfoBar.
      # def create_gender_sprite
      #   super
      # end

      # Creates the level text sprite for the InfoBar.
      # Adjusts the position if the Pokemon is a boss.
      def create_level
        return add_text(91, -7, 0, 16, :level_pokemon_number, 0, 1, color: 10, type: self.class::SymText) if enemy_boss?

        super
      end

      # Creates the status effect icon sprite for the InfoBar.
      # Adjusts the position if the Pokemon is a boss.
      def create_status
        return add_sprite(0, 20, self.class::NO_INITIAL_IMAGE, type: self.class::StatusSprite) if enemy_boss?

        super
      end

      # Creates the shiny star icon sprite for the InfoBar.
      # Adjusts the position if the Pokemon is a boss.
      def create_star
        return push(122, -4, 'shiny') if enemy_boss?

        super
      end

      # Creates additional HP bars if the Pokemon is a boss.
      def create_reserve_hp
        # @type [PFM::PokemonBattler]
        boss_pokemon = @scene.logic.battler(bank, position)
        return unless boss_pokemon

        total_bars = 5
        filled_bars = boss_pokemon.nb_bars_hp
        position_x = 33

        total_bars.times do |index|
          bar = add_sprite(position_x, 22, self.class::NO_INITIAL_IMAGE, type: ReserveHP)
          bar.switch_state(filled: false) if index >= filled_bars
          @bars_hp << bar
          position_x += 18
        end
      end

      # Creates the go_in animation.
      # @return [Yuki::Animation::TimedAnimation]
      # def go_in_animation
      #   super
      # end

      # Creates the go_out animation.
      # @return [Yuki::Animation::TimedAnimation]
      # def go_out_animation
      #   super
      # end
    end

    prepend InfoBarBossPatch

    class PokemonCaughtSprite < ShaderedSprite
      module PokemonCaughtSpriteBossPatch
        # Set the Pokemon Data
        # @param pokemon [PFM::Pokemon]
        def data=(pokemon)
          return (self.visible = false) if pokemon.boss? && pokemon.bank == 1

          super
        end
      end

      prepend PokemonCaughtSpriteBossPatch
    end

    class Background < ShaderedSprite
      module BackgroundBossPatch
        # Gets the filename for the background image.
        # Uses a different background if the Pokemon is a boss.
        # @param pokemon [PFM::Pokemon] The Pokemon data.
        # @return [String] The filename of the background image.
        def background_filename(pokemon)
          return 'battle/boss/battle_bar_boss' if pokemon.boss? && pokemon.bank == 1

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
        return 'battle/boss/hp_bar_filled'
      end

      # Gets the filename for the empty reserve HP bar image.
      # @return [String]
      def empty_hp_filename
        return 'battle/boss/hp_bar_empty'
      end
    end
  end
end
