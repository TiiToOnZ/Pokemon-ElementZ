module UI
  # Shiny sparkle of the engine, outside a battle
  #
  # The engine one assumes it lives in a battle, so it gives itself a 3D shader and reads it back in
  # its z setter. A screen with no battle camera cannot, hence the override. It knows nothing of a
  # source space, so any interface of this plugin may reach for it.
  class ShinySparkle < ShinyAnimation
    # Number of seconds the sparkle lasts, the duration the engine uses in battle
    DURATION = 1.5

    # Create a new ShinySparkle, centered on the screen and hidden until its animation plays
    # @param viewport [Viewport]
    # @param z [Integer]
    def initialize(viewport, z)
      super(viewport, z, 0, nil)
      set_position(Graphics.width / 2, Graphics.height / 2)
      self.visible = false
    end

    # Animation of the sparkle, which shows itself over the jingle then hides back
    # @note It never disposes: the sprite belongs to the stack it was pushed in, which disposes it
    # @return [Yuki::Animation::TimedAnimation]
    def create_animation
      ya = Yuki::Animation
      return ya.player(
        ya.send_command_to($game_system, :se_play, Configs.sounds.shiny_se),
        ya.send_command_to(self, :visible=, true),
        ya.scalar(DURATION, self, :animation_progression=, 0, 1),
        ya.send_command_to(self, :visible=, false)
      )
    end

    private

    # Tell which type of battle it is
    # @return [Boolean]
    def battle_3d?
      return false
    end
  end
end
