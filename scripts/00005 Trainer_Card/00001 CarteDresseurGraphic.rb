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
    BADGE_COUNT = 16
    attr_accessor :badge_page, :combat_mode, :combat_mode_text

    alias old_create_badge_sprites create_badge_sprites
    def create_badge_sprites
      @badge_page ||= 0
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
      # Créer le texte Combat solo/duo
      @combat_mode ||= :solo
      total_width = 320 # largeur totale de la zone de la carte
      @combat_mode_text = @texts.add_text(0, 100, total_width, 16, combat_mode_display, 1, color: 9)
    end

    def combat_mode_display
      @combat_mode == :solo ? "Combat solo" : "Combat duo"
    end

    alias old_update_inputs update_inputs
    def update_inputs
      old_update_inputs

      # Entrée ou C changent à la fois la page de badges et le mode combat
      if Input.trigger?(:A) || Input.trigger?(:C)
        # Page de badges
        @badge_page = (@badge_page + 1) % 2
        update_badge_visibility
        # Mode combat
        @combat_mode = (@combat_mode == :solo ? :duo : :solo)
        @combat_mode_text.text = combat_mode_display if @combat_mode_text
      end

      true
    end
  end
end
