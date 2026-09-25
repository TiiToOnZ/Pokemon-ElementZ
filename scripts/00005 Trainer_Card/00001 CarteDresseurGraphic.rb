class PFM::Trainer
  alias old_badge_obtained? badge_obtained?

  def badge_obtained?(badge_num, region = 1)
    # Support pour plus de 8 badges par région
    if badge_num > 8
      region += (badge_num - 1) / 8
      badge_num = ((badge_num - 1) % 8) + 1
    end
    old_badge_obtained?(badge_num, region)
  end
  alias has_badge? badge_obtained?
end

module GamePlay
  class TCard
    # Nombre total de badges
    BADGE_COUNT = 24
    attr_accessor :badge_page, :combat_mode, :combat_mode_text

    alias old_create_sub_background create_sub_background
    def create_sub_background
      old_create_sub_background
      # Élargir uniquement le cartouche, en conservant ses coins et sa transparence.
      source = Image.new(@sub_background.bitmap.to_png, true)
      background = Image.new(source.width, source.height)
      background.blt!(0, 0, source, source.rect)
      background.clear_rect(118, 99, 98, 18)
      background.blt!(102, 99, source, Rect.new(118, 99, 4, 18))
      background.stretch_blt!(Rect.new(106, 99, 108, 18), source, Rect.new(122, 99, 90, 18))
      background.blt!(214, 99, source, Rect.new(212, 99, 4, 18))
      texture = Texture.new(source.width, source.height)
      add_disposable(texture)
      background.copy_to_bitmap(texture)
      @sub_background.bitmap = texture
    ensure
      source&.dispose
      background&.dispose
    end

    alias old_create_badge_sprites create_badge_sprites
    def create_badge_sprites
      @badge_page = 0
      @badges = Array.new(BADGE_COUNT) do |index|
        sprite = Sprite.new(@viewport).set_bitmap('tcard/badges', :interface)
        local_index = index % 8
        sprite.set_position(
          BADGE_ORIGIN_COORDINATE.first + (local_index % 2) * BADGE_OFFSET.first,
          BADGE_ORIGIN_COORDINATE.last + (local_index / 2) * BADGE_OFFSET.last
        )
        sprite.src_rect.set(
          (local_index % 2) * BADGE_SIZE.first,
          (local_index / 8) * BADGE_SIZE.last,
          *BADGE_SIZE
        )
        sprite.visible = false
        sprite
      end
      update_badge_visibility
    end

    # Mise à jour des badges visibles selon la page
    def update_badge_visibility
      @badges.each_with_index do |sprite, i|
        begin
          sprite.visible = $trainer.has_badge?(i + 1) && (i / 8 == @badge_page)
        rescue
          sprite.visible = false
        end
      end
    end

    alias old_create_texts create_texts
    def create_texts
      old_create_texts
      # Garder le libellé centré et les flèches fixes pour les trois disciplines.
      @combat_mode ||= :solo
      total_width = 320 # largeur totale de la zone de la carte
      @combat_mode_text = @texts.add_text(0, 100, total_width, 16, combat_mode_display, 1, color: 9)
      # PokemonDS ne contient pas le caractère ◀ : réutiliser les flèches natives.
      @texts.add_sprite(108, 100, 'pc/arrow_frame_l')
      @texts.add_sprite(204, 100, 'pc/arrow_frame_r')
    end

    def create_badge
      @badge_count_text = @texts.add_text(122, 156, 190, 16, badge_count_display, color: 9)
    end

    def badge_count_display
      "Badges en #{combat_mode_display.downcase} : #{@badges.count(&:visible)} / 8"
    end

    def combat_mode_display
      case @badge_page
        when 0 then "Combat simple"
        when 1 then "Combat double"
        when 2 then "Combat triple"
      end
    end

    alias old_update_inputs update_inputs
    def update_inputs
      return false unless old_update_inputs

      # Un seul changement par pression, même si plusieurs touches sont déclenchées.
      if Input.trigger?(:LEFT)
        change_badge_page(-1)
      elsif Input.trigger?(:RIGHT) || Input.trigger?(:A) || Input.trigger?(:C)
        change_badge_page(1)
      end

      true
    end

    def change_badge_page(direction)
      @badge_page = (@badge_page + direction) % 3
      update_badge_visibility
      @combat_mode_text.text = combat_mode_display if @combat_mode_text
      @badge_count_text.text = badge_count_display if @badge_count_text
      play_cursor_se
    end
  end
end
