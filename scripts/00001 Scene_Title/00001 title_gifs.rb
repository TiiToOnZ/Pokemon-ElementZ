class Scene_Title < GamePlay::BaseCleanUpdate

  # TO STOP SE
  # Update the input of the scene
  def update_inputs
    return false unless !@splash_animation || @splash_animation.done?
    return false unless !@title_controls || @title_controls.done?
    if @current_state != :title_animation
      send(@current_state)
      return false
    else
      if @bgm_duration && Audio.bgm_position >= @bgm_duration
        @exit_background_sound_thread = true
        Audio.se_stop
        @running = false
        $scene = Scene_Title.new
        return false
      end
    end
    if Input.trigger?(:A)
      action_a
    else
      if Input.trigger?(:UP)
        action_up
      else
        if Input.trigger?(:DOWN)
          action_down
        else
          return true
        end
      end
    end
    return false
  end
  def action_play_game
    Yuki::MapLinker.reset
    Audio.bgm_stop
    $scene = GamePlay::Load.new
    if $scene.should_make_new_game?
      self.visible = false
      $scene.create_new_game
    end
    @exit_background_sound_thread = true
    Audio.se_stop
    @running = false
  end

  def action_show_credits
    $scene = GamePlay::CreditScene.new
    @exit_background_sound_thread = true
    Audio.se_stop
    @running = false
  end
  
  # Function to create title graphics
  def create_title_graphics
    create_title_background
    create_background_down_gif  
    create_title_title
    create_title_controls
    create_title_gif
  end

  def create_title_background
    gif_name = "background"
    return unless Yuki::GifReader.exist?("#{gif_name}.gif", :title)

    # Play the sound once
    Audio.se_play('Audio/SE/061-thunderclap01', 120)

    # Then play the sound in a loop every 5 seconds, unless action_play_game is triggered
    @background_sound_thread = Thread.new do
      loop do
        sleep 5
        break if @exit_background_sound_thread
        Audio.se_play('Audio/SE/061-thunderclap01', 120)
      end
    end

    @background_gif_container = Yuki::GifReader.create("#{gif_name}.gif", :title)
    @background_gif_texture = Texture.new(@background_gif_container.width, @background_gif_container.height)
    @background_gif_container.update(@background_gif_texture)
    @background_gif_sprite = Sprite.new(@viewport)
    @background_gif_sprite.bitmap = @background_gif_texture

    # Adjust position of title_background
    @background_gif_sprite.x = 0
    @background_gif_sprite.y = 0
    @background_gif_sprite.z = 0
    @background_gif_sprite.visible = true
  end

  def create_background_down_gif
    gif_name = "background_down"
    return unless Yuki::GifReader.exist?("#{gif_name}.gif", :title)
    @background_down_gif_container = Yuki::GifReader.create("#{gif_name}.gif", :title)
    @background_down_gif_texture = Texture.new(@background_down_gif_container.width, @background_down_gif_container.height)
    @background_down_gif_container.update(@background_down_gif_texture)
    @background_down_gif_sprite = Sprite.new(@viewport)
    @background_down_gif_sprite.bitmap = @background_down_gif_texture

    # Position du GIF (à ajuster selon ton besoin)
    @background_down_gif_sprite.x = 0
    @background_down_gif_sprite.y = 0  # par exemple en bas de l’écran
    @background_down_gif_sprite.z = 100  # en dessous du GIF évoli
    @background_down_gif_sprite.visible = true
  end


  # Function to create title_gif
  def create_title_gif
    gif_name = "evoli"
    return unless Yuki::GifReader.exist?("#{gif_name}.gif", :title)
    @evoli_gif_container = Yuki::GifReader.create("#{gif_name}.gif", :title)
    @evoli_gif_texture = Texture.new(@evoli_gif_container.width, @evoli_gif_container.height)
    @evoli_gif_container.update(@evoli_gif_texture)
    @evoli_gif_sprite = Sprite.new(@viewport)
    @evoli_gif_sprite.bitmap = @evoli_gif_texture

    # Adjust position of title_gif1
    @evoli_gif_sprite.x = 142
    @evoli_gif_sprite.y = 166
    @evoli_gif_sprite.z = 300
    @evoli_gif_sprite.visible = true
  end

  def update_graphics
    @splash_animation&.update
    @title_controls&.update
    update_background_gif if @background_gif_container
    update_evoli_gif if @evoli_gif_container
    update_background_down_gif if @background_down_gif_container
  end

  def update_background_gif
    @background_gif_container.update(@background_gif_texture)
  end
  
  def update_evoli_gif
    @evoli_gif_container.update(@evoli_gif_texture)
  end

  def update_background_down_gif
    @background_down_gif_container.update(@background_down_gif_texture)
  end

end
