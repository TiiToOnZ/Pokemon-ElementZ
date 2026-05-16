module CaptureChain
  module_function

  # Returns the plugin configuration object loaded from JSON.
  def config
    Configs.capture_chain
  end

  # Returns the save key used to persist the current chain state.
  def storage_key
    key = config.storage_key
    key.respond_to?(:to_sym) ? key.to_sym : :capture_chain
  end

  # Returns the number of IV stats managed by the plugin.
  def stat_count
    value = config.stat_count.to_i
    value.positive? ? value : 6
  end

  # Normalizes and sorts the configured bonus thresholds.
  def bonus_table
    tab = Array(config.bonus_table).map do |bonus|
      {
        min: config_value(bonus, :min).to_i,
        shiny_rate: config_value(bonus, :shiny_rate).to_i,
        perfect_ivs: config_value(bonus, :perfect_ivs).to_i
      }
    end
    
    return tab.sort_by { |bonus| -bonus[:min] }
  end

  # Tells if fleeing from the chained wild battle should reset the chain.
  def break_on_player_flee?
    config.break_on_player_flee == true
  end

  # Tells if ending the chained wild battle without capture should reset the chain.
  def break_on_failed_battle_against_chained_species?
    config.break_on_failed_battle_against_chained_species == true
  end

  # Returns the public status hash of the current chain.
  def status
    data = data_store
    {
      species: data[:species],
      count: data[:count] || 0,
      last_capture_map_id: data[:last_capture_map_id]
    }
  end

  # Returns the currently chained species.
  def species
    status[:species]
  end

  # Returns the current chain length.
  def count
    status[:count]
  end

  # Tells if a valid chain is currently active.
  def active?
    count.positive? && !species.nil?
  end

  # Fully clears the saved chain data.
  def reset!
    data_store.clear
  end

  # Clears temporary data stored only for the current battle lifecycle.
  def clear_battle_context!
    data_store.delete(:current_battle_species_list)
    data_store.delete(:current_battle_wild)
  end

  # Registers a successful capture and either extends or starts a chain.
  def register_capture!(pokemon, map_id = current_map_id)
    db_symbol = pokemon_db_symbol(pokemon)
    return unless db_symbol

    data = data_store
    data[:count] = data[:species] == db_symbol ? data.fetch(:count, 0) + 1 : 1
    data[:species] = db_symbol
    data[:last_capture_map_id] = map_id
    clear_battle_context!
  end

  # Applies the current chain bonus to a generated wild Pokemon of the chained species.
  def apply_bonus!(pokemon)
    db_symbol = pokemon_db_symbol(pokemon)
    return pokemon unless db_symbol && chained_species?(db_symbol)

    bonus = current_bonus
    return pokemon unless bonus

    apply_perfect_ivs!(pokemon, bonus[:perfect_ivs])
    return pokemon if pokemon_shiny?(pokemon)

    force_shiny!(pokemon) if shiny_roll_success?(bonus[:shiny_rate])
    
    pokemon
  end

  # Returns the matching bonus entry for the current chain length.
  def current_bonus
    bonus_table.find { |bonus| count >= bonus[:min] }
  end

  # Returns only the current shiny rate bonus.
  def shiny_rate
    current_bonus&.[](:shiny_rate)
  end

  # Returns only the current guaranteed perfect IV count.
  def perfect_ivs
    current_bonus&.[](:perfect_ivs).to_i
  end

  # Checks if the given species matches the active chain.
  def chained_species?(db_symbol)
    species == db_symbol && active?
  end

  # Stores battle metadata used to know if a chain should break when the battle ends.
  def register_battle_context!(battle_info)
    data = data_store
    data[:current_battle_wild] = wild_battle?(battle_info)
    species_list = extract_enemy_species(battle_info)
    data[:current_battle_species_list] = species_list
  end

  # Breaks the chain if the player flees from a relevant wild battle.
  def break_from_player_flee!
    return unless break_on_player_flee?
    return unless current_battle_wild?
    return unless current_battle_includes_chained_species?

    reset!
  end

  # Resolves battle-end chain breaking rules for wild battles only.
  def resolve_battle_end!(battle_info)
    register_battle_context!(battle_info) if battle_info
    return if caught_pokemon?(battle_info)
    return unless break_on_failed_battle_against_chained_species?
    return unless current_battle_wild?
    return unless current_battle_includes_chained_species?

    reset!
  ensure
    clear_battle_context!
  end

  # Returns the current map id when available.
  def current_map_id
    return $game_map.map_id if defined?($game_map) && $game_map

    0
  end

  # Returns the save sub-hash used by the plugin.
  def data_store
    PFM.game_state.user_data[storage_key] ||= {}
  end

  # Returns every enemy species involved in the current battle context.
  def current_battle_species_list
    Array(data_store[:current_battle_species_list])
  end

  # Checks if the currently chained species was present in the battle.
  def current_battle_includes_chained_species?
    return false unless active?

    current_battle_species_list.include?(species)
  end

  # Tells if the current stored battle context is a wild battle.
  def current_battle_wild?
    data_store[:current_battle_wild] == true
  end

  # Extracts a species symbol from a Pokemon-like object.
  def pokemon_db_symbol(pokemon)
    return pokemon.db_symbol if pokemon.respond_to?(:db_symbol)
    return pokemon.original.db_symbol if pokemon.respond_to?(:original)

    nil
  end

  # Tells if the Pokemon is already shiny.
  def pokemon_shiny?(pokemon)
    return pokemon.shiny? if pokemon.respond_to?(:shiny?)
    return pokemon.original.shiny? if pokemon.respond_to?(:original)

    false
  end

  # Forces a generated Pokemon to become shiny.
  def force_shiny!(pokemon)
    if pokemon.respond_to?(:shiny=)
      pokemon.shiny = true
    elsif pokemon.respond_to?(:original)
      pokemon.original.shiny = true
    else
      pokemon.instance_variable_set(:@shiny, true)
    end
  end

  # Upgrades random non-perfect IVs until the configured amount is reached.
  def apply_perfect_ivs!(pokemon, desired_count)
    return if desired_count <= 0

    target = pokemon.respond_to?(:original) ? pokemon.original : pokemon
    iv_writers = %i[iv_hp= iv_atk= iv_dfe= iv_spd= iv_ats= iv_dfs=].first(stat_count)
    current_values = iv_writers.map do |writer|
      reader = writer.to_s.delete('=').to_sym
      target.respond_to?(reader) ? target.public_send(reader) : 0
    end
    missing_indexes = []
    current_values.each_with_index do |value, index|
      missing_indexes << index if value.to_i < 31
    end
    need = [desired_count - current_values.count { |value| value.to_i >= 31 }, 0].max
    missing_indexes.sample(need).each do |index|
      target.public_send(iv_writers[index], 31) if target.respond_to?(iv_writers[index])
    end
  end

  # Performs the random shiny roll from a configured denominator.
  def shiny_roll_success?(rate)
    rate.to_i.positive? && rand(rate.to_i).zero?
  end

  # Reads a config value whether the source hash uses string or symbol keys.
  def config_value(data, key)
    data[key] || data[key.to_s]
  end

  # Detects if the provided battle info describes a wild battle.
  def wild_battle?(battle_info)
    return false unless battle_info

    !battle_info.trainer_battle?
  end

  # Tells if the battle ended with a successful capture.
  def caught_pokemon?(battle_info)
    battle_info && !battle_info.caught_pokemon.nil?
  end

  # Collects every enemy species from the enemy bank, including double and multi wild battles.
  def extract_enemy_species(battle_info)
    return [] unless battle_info

    parties = battle_info.parties
    return [] unless parties && parties[1]

    enemy_parties = parties[1]
    enemy_parties.flat_map do |enemy_party|
      Array(enemy_party).map { |pokemon| pokemon_db_symbol(pokemon) }
    end.compact.uniq
  end
end
