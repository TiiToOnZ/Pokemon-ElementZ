module SOSBattles
  # Species a creature may call for, declared by the game creator.
  module CallPools
    # Form a pool entry falls back on when it names a species alone
    DEFAULT_FORM = 0

    class << self
      # Declare the species a creature may summon, on top of what its area and its family offer.
      # @param caller_db_symbol [Symbol] species that calls
      # @param species [Array<Symbol, Array(Symbol, Integer)>] species that may answer, each entry being a db_symbol or a [db_symbol, form] couple
      # @yieldparam caller_battler [PFM::PokemonBattler] creature that called
      # @yieldreturn [Boolean] whether this pool answers that call
      # @return [self]
      def register(caller_db_symbol, species, &condition)
        raise ArgumentError, 'SOSBattles::CallPools.register expects the calling species as a Symbol' unless caller_db_symbol.is_a?(Symbol)

        (@pools[caller_db_symbol] ||= []) << [validated_species(caller_db_symbol, species), condition]
        return self
      end

      # Draw the species answering a call, in the first declared pool this creature satisfies.
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @return [Array(Symbol, Integer), nil] db_symbol and form of the answering creature
      def species_for(caller_battler)
        pools = @pools[caller_battler.db_symbol]
        return unless pools

        pool = pools.find { |_entries, condition| answers?(condition, caller_battler) }
        return pool&.first&.sample
      end

      private

      # Whether a pool answers this call, a pool declared without a condition answering every one of them.
      # @note A condition is creator code running mid-battle: one that raises loses its call rather than the battle.
      # @param condition [Proc, nil] condition the pool was declared with
      # @param caller_battler [PFM::PokemonBattler] creature that called
      # @return [Boolean] what the condition answered, anything but false and nil being an answer
      def answers?(condition, caller_battler)
        return true unless condition

        return condition.call(caller_battler)
      rescue StandardError => e
        log_error("SOS could not tell whether #{caller_battler.db_symbol} may call its pool: #{e.message}")
        return false
      end

      # Refuse a malformed pool where the game creator wrote it, rather than deep inside a battle.
      # @param caller_db_symbol [Symbol] species the pool was declared for, for the message
      # @param species [Object] value the game creator declared
      # @return [Array<Array(Symbol, Integer)>] entries brought down to db_symbol and form couples
      def validated_species(caller_db_symbol, species)
        entries = species.is_a?(Array) ? species.map { |entry| normalized_entry(entry) } : []
        valid = entries.any? && entries.all? { |db_symbol, form| db_symbol.is_a?(Symbol) && form.is_a?(Integer) }
        shape = 'a non empty Array of db_symbol or [db_symbol, form]'
        raise ArgumentError, "SOSBattles::CallPools.register(:#{caller_db_symbol}) expects #{shape}" unless valid

        return entries
      end

      # Bring a species named alone down to the couple the draw works with.
      # @param entry [Object] one entry of a declared pool
      # @return [Object] db_symbol and form couple, or the entry as it is for the validation to refuse it
      def normalized_entry(entry)
        return [entry, DEFAULT_FORM] if entry.is_a?(Symbol)

        return entry
      end
    end

    @pools = {}
  end
end
