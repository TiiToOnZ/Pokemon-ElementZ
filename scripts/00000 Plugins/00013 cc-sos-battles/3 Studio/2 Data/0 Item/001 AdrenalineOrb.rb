module SOSBattles
  # ID of the engine text file holding the official Adrenaline Orb line
  ADRENALINE_ORB_TEXT_FILE = 60

  # Index of "The Adrenaline Orb makes the wild Pokemon nervous!" in that file
  ADRENALINE_ORB_MESSAGE_INDEX = 345
end

module PFM
  module ItemDescriptor
    # Keyed by db_symbol and never by class, or every generic item of the project would answer here too.
    # @note The scene given here is the bag, not the battle, which is reached through __last_scene.
    define_bag_use(:adrenaline_orb, true) do |item, scene|
      battle = scene.__last_scene
      next :unused unless battle.is_a?(Battle::Scene)

      unless battle.logic.adrenaline_orb_usable?
        scene.display_message(parse_text(22, 108))
        next :unused
      end

      GamePlay.bag_mixin.from(scene).battle_item_wrapper = PFM::ItemDescriptor.actions(item.id)
      # Hands the scene back before the bag speaks, so the usage message belongs to the battle.
      $scene = battle
      scene.return_to_scene(Battle::Scene)
    end

    # Written straight onto the wrapper, since both engine helpers for this block demand a target first.
    EXTEND_DATAS[:adrenaline_orb].action_to_push = proc do |_item, _creature, scene|
      scene.logic.use_adrenaline_orb
      scene.display_message_and_wait(parse_text(SOSBattles::ADRENALINE_ORB_TEXT_FILE, SOSBattles::ADRENALINE_ORB_MESSAGE_INDEX))
    end
  end
end
