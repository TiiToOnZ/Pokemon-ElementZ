module Battle
  class Visual
    # The overkill gauge coming back full and draining by the damage that went past the knockout.
    # @note It never drives the creature HP, which would revive a fallen target under show_kos.
    class OverkillBarAnimation < Yuki::Animation::Player
      # Points the gauge drains per second, the very speed the engine moves a HP gauge at
      DRAIN_RATE = 60

      # Shortest and longest a gauge may take to move, as HPAnimation#main_duration bounds its own
      DURATION_RANGE = 0.2..1.0

      # Seconds the drained gauge is held, the beat HPAnimation leaves when a creature falls
      HOLD_DURATION = 0.1

      # Create the animation of an overkill gauge.
      # @param info_bar [BattleUI::InfoBar] info bar of the creature taking the hit
      # @param target [PFM::PokemonBattler] creature taking the hit
      def initialize(info_bar, target)
        @info_bar = info_bar
        @target = target
        @final_rate = [1 - target.overkill_pending_excess.to_f / target.overkill_threshold, 0].max
        @drain_duration = drain_duration_for([target.overkill_pending_excess, target.overkill_threshold].min)
        super(build_stack)
      end

      private

      # Build the stack, which leaves the gauge where it stopped so the creature falls showing it
      # @return [Array<Yuki::AnimationMixin>]
      # @note No loop: a Player ending on one is never done? and would freeze show_hp_animations.
      def build_stack
        return [
          Yuki::Animation.send_command_to(self, :open_gauge),
          Yuki::Animation.scalar(@drain_duration, self, :gauge_rate=, 1, @final_rate),
          Yuki::Animation.send_command_to(self, :play_overkill_sound),
          Yuki::Animation.wait(HOLD_DURATION)
        ]
      end

      # Time the gauge takes to drain, on the law the engine applies to a HP gauge
      # @param quantity [Integer] points the gauge visibly moves, a full bar at the most
      # @return [Float]
      def drain_duration_for(quantity)
        return (quantity.to_f / DRAIN_RATE).clamp(DURATION_RANGE)
      end

      # Show the gauge full, unless the engine saved the creature after the excess was measured
      # @note The excess is a prediction until super has run: Focus Sash, Sturdy and Endure all
      #   answer after it, so the gauge only opens for a creature that really went down.
      def open_gauge
        @open = @target.dead?
        self.gauge_rate = 1
      end

      # Drive the gauge, and say nothing at all when it never opened
      # @param value [Numeric] 0 ~ 1
      def gauge_rate=(value)
        return unless @open

        @info_bar.overkill_rate = value
      end

      # Sound the overkill, once the gauge has emptied on a creature that really fell
      def play_overkill_sound
        return unless @open && @target.overkill_reached?

        Audio.se_play("audio/se/#{Overkill::Settings.sound_filename}")
      end
    end
  end
end
