module ZVBattleUI
  # Handle healing animation in battle scene
  class HealAnimator
    # @param viewport [Viewport]
    # @param scene [Battle::Scene]
    # @param target_sprite [BattleUI::PokemonSprite]
    def initialize(viewport, scene, target_sprite)
      @viewport = viewport
      @scene = scene
      @target_sprite = target_sprite
      create_spritesheet
    end

    # @return [Yuki::Animation::TimedAnimation]
    # @note This animation doesn't dispose
    def create_animation
      ya = Yuki::Animation
      sprite_anim = ya.opacity_change(0, @sheet, 0, 255)
      sprite_anim.play_before(ya::SpriteSheetAnimation.new(animation_duration, @sheet, sprite_cells))
                 .play_before(ya.opacity_change(0, @sheet, 255, 0))
      sound_anim = ya.se_play(sound_filename)

      tx = @target_sprite.x + x_offset
      ty = @target_sprite.y + y_offset
      anim = ya.move_discreet(0, @sheet, tx, ty, tx, ty)
      anim.play_before(sprite_anim).parallel_add(sound_anim)
      return anim
    end

    def dispose
      @sheet.dispose
    end

    private

    def spritesheet_dimensions = [5, 2]
    def spritesheet_filename = 'PRAS- Recovery'
    def sound_filename = 'Recovery'
    def animation_duration = 0.4

    # x-offset for the animation
    # @return [Integer]
    def x_offset
      return 0
    end

    # y-offset for the animation
    # @return [Integer]
    def y_offset
      return 0 if Battle::BATTLE_CAMERA_3D && @target_sprite.bank == 0

      return 8
    end

    # @return [Array<Array<Integer>>]
    def sprite_cells
      x = @sheet.nb_x
      y = @sheet.nb_y
      return (x * y - 3).times.map { |i| [i % x, i / x] }
    end

    def create_spritesheet
      @sheet = SpriteSheet.new(@viewport, *spritesheet_dimensions)
      @sheet.bitmap = RPG::Cache.animation(spritesheet_filename)
      @sheet.opacity = 0
      @sheet.set_origin(@sheet.width / 2, @sheet.height)
      apply_3d_battle_settings(@sheet)
    end

    # Apply the 3D settings to a sprite if the 3D camera is enabled
    # @param sprite [Sprite, Spritesheet]
    def apply_3d_battle_settings(sprite)
      return unless Battle::BATTLE_CAMERA_3D

      sprite.shader = Shader.create(:fake_3d)
      @scene.visual.sprites3D.append(sprite)
      sprite.shader.set_float_uniform('z', @target_sprite.shader_z_position)
    end
  end
end
