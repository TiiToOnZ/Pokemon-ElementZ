# frozen_string_literal: true

module BombanceAmbiance
  module MapLifecycle
    def setup(map_id)
      return super unless equal?($game_map)

      manager = BombanceAmbiance.manager
      anchor = manager.before_setup(self, map_id)
      result = super
      manager.after_setup(self, anchor)
      result
    end

    def update
      result = super
      if equal?($game_map)
        BombanceAmbiance.manager.observe(self)
        BombanceAmbiance.manager.advance_light(self)
      end
      result
    end
  end

  module NativeFogAdapter
    private

    def update_fog_sprite_parameters
      super
      BombanceAmbiance.manager.render(@fog, $game_map)
    end
  end
end

Game_Map.prepend(BombanceAmbiance::MapLifecycle)
Spriteset_Map.prepend(BombanceAmbiance::NativeFogAdapter)
# Expansion is PSDK's existing new-game/load hook. No field is added to a save.
PFM::GameState.on_expand_global_variables(:bombance_ambiance_session) do
  BombanceAmbiance.reset_session
end
