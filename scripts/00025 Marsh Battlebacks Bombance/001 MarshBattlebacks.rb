# Map-specific 2D scenery. Keep PSDK's time and trainer variant resolution.
module BombanceMarshBattlebacks
  MARSH_GRASS_MAP_IDS = [35, 36, 78, 80].freeze

  module BattleInfoPatch
    private

    def system_tag_background_name
      family = super
      return family if Battle::BATTLE_CAMERA_3D
      return family unless MARSH_GRASS_MAP_IDS.include?($game_map&.map_id)
      # PSDK calls the Grass tag (TGrass) "tall_grass" in its background API.
      # Its "grass?" predicate instead means untagged outdoor ground.
      return family unless $env.tall_grass? && family == 'back_tall_grass'
      # This pack has only timed Marsh files. Keep the native family when the
      # native time resolver is disabled rather than request a missing plain file.
      return family unless timed_background_names('back_marsh')

      'back_marsh'
    end
  end
end

Battle::Logic::BattleInfo.prepend(BombanceMarshBattlebacks::BattleInfoPatch)
