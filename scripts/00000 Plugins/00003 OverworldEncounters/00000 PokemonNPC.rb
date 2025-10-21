# Script by CrypticSky
# v0.2.6.2
# Documentation:
# EN
# https://pokemonworkshop.com/en/sdk/plugins/overworld-encounters
# FR
# https://pokemonworkshop.com/fr/sdk/plugins/overworld-encounters

module PFM
  class Wild_Battle
    # Return an array containining a single creature based on wild encounter groups based on event's location
    # @param event [Game_Character]
    # @return Array<PFM::Pokemon>
    def generate_wild_creature(event)
      # Store zone group data for parsing
      groups = $wild_battle.groups
      # Find a group corresponding to the event's location
      system_tag = event.system_tag_db_symbol
      terrain_tag = event.terrain_tag
      group = groups.find { |g| g.tool.nil? && g.system_tag == system_tag && g.terrain_tag == terrain_tag }
      # If no group has been set for this location, return nothing
      return [] if group.nil? || group.encounters.empty?

      # Select one pokemon in the group according to the normal procedure
      maxed = MAX_POKEMON_LEVEL_ABILITY.include?(creature_ability) && rand(100) < 50
      all_creatures = group.encounters.map do |encounter|
        encounter.to_creature(maxed ? encounter.level_setup.range.end : nil)
      end
      return [] if all_creatures.nil?

      creature_to_select = configure_creature(all_creatures)
      selected_creature = select_creature(group, creature_to_select)
      return selected_creature
    end
  end
end

class Interpreter < Interpreter_RMXP
  # Set sprite of an event to a creature
  # @param id [db_symbol] db_symbol of the creature
  # @param form [Integer] form index of the creature
  # @param female [Boolean] if the creature is a female
  # @param shiny [Boolean] shiny state
  # @param event_id [Integer] event ID
  def set_sprite_to_creature(id, form = 0, female = false, shiny = false, event_id = @event_id)
    if id.is_a?(String)
      log_error('Argument Error : Creature ID cannot be string')
      return
    end
    creature = data_creature_form(id, form)
    if creature.db_symbol != id || creature.form != form
      log_error("Database Error: The Form \##{form} of the Creature \##{id} doesn't exist.")
      return
    end
    resources = creature.resources
    return missing_resources_error(id) unless resources

    filename = resources.character.empty? ? '000' : resources.character
    if resources.has_female && female
      if shiny && !resources.character_shiny_f.empty?
        filename = resources.character_shiny_f
      else
        filename = resources.character_f unless resources.character_f.empty?
      end
    elsif shiny && !resources.character_shiny.empty?
      filename = resources.character_shiny
    end
    $game_map.events[event_id].set_appearance(filename)
  end

  # Return a wild creature according to the current zone of the event
  # @param event_id [Integer]
  # @return PFM::Pokemon
  def pick_creature_encounter(event_id = @event_id)
    pokemons = $wild_battle.generate_wild_creature($game_map.events[event_id])
    if pokemons.empty? || data_creature(pokemons[0].id) == :__undef__
      log_info("No encounterable pokemon for event #{event_id}")
      return nil
    end
    ::Scheduler.add_message(:on_warp_process, Scene_Map, 'Cleanup Self Switch A', 99, self, :cleanup_a_switch)
    $user_data[:scheduled_for_cleanup] = [] if $user_data[:scheduled_for_cleanup].nil?
    $user_data[:scheduled_for_cleanup] += [[event_id, @map_id]]
    return pokemons[0]
  end

  # Reset our events' A self-switches on map change
  # This assumes your are using an Autorun that switches to the event touch page on self-switch A
  # See the documentation for template eventing
  def cleanup_a_switch
    return if $user_data[:scheduled_for_cleanup].nil?

    $user_data[:scheduled_for_cleanup].each do |i|
      set_self_switch(false, 'A', i[0], i[1])
    end
    $user_data[:scheduled_for_cleanup] = []
    ::Scheduler.__remove_task(:on_warp_process, Scene_Map, 'Cleanup Self Switch A', 99)
  end
end
