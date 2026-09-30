module Battle
  class Logic
    # Battler collections made to tolerate the empty place a wild 1v2 leaves on the player bank.
    # @note No-ops when no place is empty, since compacting an array without nil returns it as is.
    # rubocop:disable Style/OptionalBooleanParameter
    module NilTolerantCollections
      # Tell if the battle can continue
      # @return [Boolean]
      def can_battle_continue?
        # Hidden rather than restated: the engine scans a raw bank, but its victory rules are its own.
        original_battlers = @battlers
        @battlers = original_battlers.map(&:compact)
        return super
      ensure
        @battlers = original_battlers
      end

      # Return all the alive battler of a bank
      # @param bank [Integer]
      # @return [Array<PFM::PokemonBattler>]
      def alive_battlers(bank)
        return @battlers[bank].compact.select(&:can_fight?)
      end

      # Return all the alive battler of a bank but don't check can_fight?
      # @param bank [Integer]
      # @return [Array<PFM::PokemonBattler>]
      def alive_battlers_without_check(bank)
        return @battlers[bank].compact.select(&:alive?)
      end

      # Iterate through all battlers
      # @yieldparam battler [PFM::PokemonBattler]
      # @return [Enumerable<PFM::PokemonBattler>]
      def all_battlers(&block)
        return @battlers.flatten.compact.each(&block) if block

        return @battlers.flatten.compact.each
      end

      # List all the battlers of the trainer from a battler
      # @return [Array<PFM::PokemonBattler>]
      def retrieve_party_from_battler(battler)
        return @battlers[battler.bank].compact.select { |pokemon| battler.party_id == pokemon.party_id }
      end

      # Check active abilities on the field
      # @return [Array<PFM::PokemonBattler>]
      def any_field_ability_active?(db_symbol)
        return @battlers.any? { |battlers| battlers.compact.any? { |battler| battler.has_ability?(db_symbol) } }
      end

      # Return the foes
      # @param pokemon [PFM::PokemonBattler]
      # @param check_adjacent [Boolean]
      # @return [Array<PFM::PokemonBattler>]
      def foes_of(pokemon, check_adjacent = false)
        return [] if pokemon.position.nil? || pokemon.position >= @battle_info.vs_type

        position = pokemon.position
        return @battlers.flat_map.with_index do |battler_bank, bank|
          next nil.to_a if bank == pokemon.bank

          next battler_bank.select.with_index do |foe, foe_position|
            # Guarded instead of compacted, unlike its siblings: the index here is the field position.
            next false unless foe

            foe.can_fight? && (!check_adjacent || (foe_position - position).abs <= 1)
          end
        end
      end

      # Return the allies (excluding the pokemon)
      # @param pokemon [PFM::PokemonBattler]
      # @param check_adjacent [Boolean]
      # @return [Array<PFM::PokemonBattler>]
      def allies_of(pokemon, check_adjacent = false)
        return [] if pokemon.position.nil? || pokemon.position >= @battle_info.vs_type

        position = pokemon.position
        return @battlers[pokemon.bank].select.with_index do |ally, ally_position|
          # Guarded instead of compacted, unlike its siblings: the index here is the field position.
          next false unless ally

          next ally_position != position && ally.can_fight? && (!check_adjacent || (ally_position - position).abs <= 1)
        end
      end
    end
    # rubocop:enable Style/OptionalBooleanParameter
    prepend NilTolerantCollections
  end
end
