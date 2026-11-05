module ElementZ
  module QuestDexSync
    # Keep the native end-of-battle updates, then account for a captured
    # battler only when the native loop would have skipped it.
    module CapturedPokemonSeeObjective
      def handle_quest_update(players_creatures)
        caught_pokemon = logic.battle_info.caught_pokemon
        native_update_will_see_caught = caught_pokemon &&
          !caught_pokemon.from_party? &&
          caught_pokemon.last_sent_turn != -1 &&
          logic.all_battlers.any? { |battler| battler.equal?(caught_pokemon) }

        result = super
        $quests.see_pokemon(caught_pokemon.db_symbol) if caught_pokemon && !native_update_will_see_caught
        result
      end
    end
  end
end

Battle::Logic::BattleEndHandler.prepend(ElementZ::QuestDexSync::CapturedPokemonSeeObjective)
