module Battle
  class Scene
    module SceneChoiceBossPatch
      # Begin the Pokemon giving procedure
      # @param battler [PFM::PokemonBattler] pokemon that was just caught
      # @param ball [Studio::BallItem]
      def give_pokemon_procedure(battler, ball)
        message_window.blocking = true
        message_window.wait_input = true
        Audio.bgm_play(*@battle_info.defeat_bgm)

        creature = battler.original
        $wild_battle.remove_roaming_pokemon(creature)
        update_pokemon_related_quests(creature)
        update_pokedex_related_infos(creature)

        display_message_and_wait(parse_text_with_pokemon(18, 67, creature))
        rename_sequence(creature) if $options.catch_rename

        battler.captured_with = ball.id
        battler.loyalty = 200 if ball&.db_symbol == :friend_ball
        battler.fully_heal if ball&.db_symbol == :heal_ball
        battler.copy_properties_back_to_original
        creature.boss = false
        creature.nb_bars_hp = 0

        $game_system.map_interpreter.add_pokemon(creature)

        # Stocked
        if $game_switches[Yuki::Sw::SYS_Stored]
          display_message_and_wait(parse_text_with_pokemon(30, 1, creature, '[VAR BOX(0001)]' => $storage.get_box_name($storage.current_box)))
        end
      end
    end

    prepend SceneChoiceBossPatch
  end
end
