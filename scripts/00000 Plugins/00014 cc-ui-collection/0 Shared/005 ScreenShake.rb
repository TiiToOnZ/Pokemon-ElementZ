module UI
  module Cinematic
    # Sideways shake of a viewport, the swing losing height as it goes
    #
    # The source animations shake the whole screen on an impact, which the engine has no helper for.
    # The viewport belongs to the scene, so this only moves its origin and puts it back.
    class ScreenShake
      include Cinematic

      # Widest offset the shake reaches, in source pixels
      AMPLITUDE = 8
      # Number of seconds the shake lasts
      DURATION = 0.3
      # Number of times it swings before it dies out
      SWINGS = 3

      # Take over the origin of a viewport
      # @param viewport [Viewport] viewport of the scene, which owns it
      def initialize(viewport)
        @viewport = viewport
      end

      # Animation of the shake, which is not started
      # @return [Yuki::Animation::TimedAnimation]
      def create_animation
        return Yuki::Animation.scalar(DURATION, self, :progress=, 0, 1)
      end

      # Put the viewport back where it stands when nothing shakes it
      def reset
        @viewport.ox = 0
      end

      private

      # Swing the viewport aside, the swing losing height as the animation goes
      # @note Private on purpose: create_animation drives it, and Yuki::Animation sends it
      # @param value [Float] progression of the shake, between 0 and 1
      def progress=(value)
        amplitude = AMPLITUDE * scale * (1 - value)
        @viewport.ox = amplitude * Math.sin(value * Math::PI * 2 * SWINGS)
      end
    end
  end
end
