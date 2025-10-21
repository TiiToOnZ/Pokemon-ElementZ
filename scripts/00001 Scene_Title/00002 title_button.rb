module UI   
 class TitleControls < SpriteStack
    def create_play_bg
      @play_bg = add_sprite(165, 205, 'shader_bg')
      @play_bg.ox = @play_bg.width / 2
      @play_bg.shader = @shader
    end
    def create_credits_bg
      @credit_bg = add_sprite(165, 220, 'shader_bg')
      @credit_bg.ox = @credit_bg.width / 2
      @credit_bg.shader = @shader
    end
    def create_play_text
      @font_id = 20
      add_text(165, 205, 0, 24, text_get(32, 77).capitalize, 1, 1, color: 9)
    end
    def create_credit_text
      @font_id = 20
      add_text(165, 220, 0, 24, 'Credits', 1, 1, color: 9)
    end
  end
end
