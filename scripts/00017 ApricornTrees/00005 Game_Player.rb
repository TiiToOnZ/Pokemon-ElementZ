# frozen_string_literal: true

Game_Player::STATE_APPEARANCE_SUFFIX[:apricorn] = '_shake'
Game_Player::STATE_MOVEMENT_INFO[:apricorn] = [4, 4]

module ApricornTrees
  module PlayerAnimation
    def apricorn_state?
      @state == :apricorn
    end

    def enter_in_apricorn_state
      leave_cycling_state if cycling?
      @apricorn_previous_graphic = @character_name
      @apricorn_started_at = ApricornTrees.monotonic
      @state = :apricorn
      update_move_parameter(:apricorn)
      @update_callback = :update_enter_apricorn_state
      update_appearance(0)
    end

    def update_enter_apricorn_state
      update_apricorn_state
      @update_callback = :update_apricorn_state if apricorn_state?
    end

    def update_apricorn_state
      token = ApricornTrees.session
      unless token && ApricornTrees.session_valid?(token)
        ApricornTrees.cancel_session
        leave_apricorn_state
        return
      end
      @pattern = [((ApricornTrees.monotonic - @apricorn_started_at) / 0.10).floor, 3].min
    end

    def leave_apricorn_state
      return unless apricorn_state?
      @update_callback = nil
      @apricorn_started_at = nil
      enter_in_walking_state
      set_appearance(@apricorn_previous_graphic) if !@charset_base && @apricorn_previous_graphic
      @apricorn_previous_graphic = nil
    end
  end
end
Game_Player.prepend(ApricornTrees::PlayerAnimation)
