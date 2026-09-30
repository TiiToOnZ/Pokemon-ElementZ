module Battle
  class Visual
    # Slots the overkill gauge behind the HP drain, in the handler show_hp_animations waits on.
    module OverkillFeedback
      # Row of the overkill message in the plugin text file
      OVERKILL_MESSAGE_ID = 0

      # Get the info bar of a creature
      # @param pokemon [PFM::PokemonBattler]
      # @return [BattleUI::InfoBar, nil]
      def overkill_info_bar(pokemon)
        return @info_bars.dig(pokemon.bank, pokemon.position)
      end

      # Build the overkill gauge animation of a creature, or nothing when there is none to show
      # @param target [PFM::PokemonBattler]
      # @return [OverkillBarAnimation, nil]
      # @note Public: BossHPAnimation asks for this leg itself.
      def overkill_bar_animation_for(target)
        return if target.overkill_pending_excess <= 0

        info_bar = overkill_info_bar(target)
        return unless info_bar

        return OverkillBarAnimation.new(info_bar, target)
      end

      # Show KO animations
      # @param targets [Array<PFM::PokemonBattler>]
      def show_kos(targets)
        # The overkill line has to land before super shows the knockout one.
        targets.select(&:dead?).each { |target| show_overkill_message(target) }
        super
      end

      private

      # Announce an overkill in the battle log
      # @param target [PFM::PokemonBattler] creature that just went down
      def show_overkill_message(target)
        return unless target.overkill_reached?

        @scene.display_message_and_wait(parse_text_with_pokemon(Overkill::Settings.text_file_id, OVERKILL_MESSAGE_ID, target))
      end

      # Create a handler for HP-related animations regarding a battler
      # @param target [PFM::PokemonBattler]
      # @param hp [Integer]
      # @param effectiveness [Float, nil]
      # @return [Yuki::Animation::Handler]
      def create_hp_animation_handler(target, hp, effectiveness)
        handler = super
        return handler if handler[:hp].nil?

        animation = overkill_bar_animation_for(target)
        return handler unless animation

        # Sequential: a separate key would move both gauges at once, on the same spot.
        handler[:hp] = Yuki::Animation.player(handler[:hp], animation)
        return handler
      end
    end

    prepend OverkillFeedback
  end
end
