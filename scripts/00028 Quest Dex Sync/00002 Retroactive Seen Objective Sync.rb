# module ElementZ
#   module QuestDexSync
#     # A native "see Pokemon" objective stores a boolean by species. Seed that
#     # same value from the Dex when the quest or a hidden objective becomes active.
#     module RetroactiveSeenObjectiveSync
#       def start(quest_id)
#         started = super
#         synchronize_seen_objectives(active_quest(quest_id)) if started
#         started
#       end

#       def show_goal(quest_id, goal_index)
#         result = super
#         synchronize_seen_objectives(active_quest(quest_id))
#         result
#       end

#       private

#       def synchronize_seen_objectives(quest)
#         return false unless quest && $pokedex

#         updated = false
#         data_quest(quest.quest_id).objectives.each do |objective|
#           next unless objective.objective_method_name == :objective_see_pokemon

#           species_symbol = objective.objective_method_args.first
#           next unless species_symbol.is_a?(Symbol)
#           next unless quest.objective?(:objective_see_pokemon, species_symbol)
#           next unless $pokedex.creature_seen?(species_symbol)
#           next if quest.objective_see_pokemon(species_symbol)

#           quest.data_set(:pokemon_seen, species_symbol, true)
#           updated = true
#         end

#         check_quest(quest.quest_id) if updated
#         updated
#       end
#     end
#   end
# end

# PFM::Quests.prepend(ElementZ::QuestDexSync::RetroactiveSeenObjectiveSync)
