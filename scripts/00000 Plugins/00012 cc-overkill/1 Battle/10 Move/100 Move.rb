module Battle
  class Move
    # Exposes the damage a move wanted to deal, before it was capped to what the target could take.
    module UncappedDamage
      # Damage the move computed before it was capped to what the target could take
      # @return [Integer, nil]
      attr_reader :uncapped_damage

      # Damage the move would still have dealt to a target it is about to knock out
      # @param _user [PFM::PokemonBattler] user of the move
      # @param _target [PFM::PokemonBattler] target about to go down
      # @return [Integer]
      # @note Only moves that stop early on a knockout have anything to add here.
      def overkill_pending_damage(_user, _target)
        return 0
      end

      # Function starting the move procedure
      # @param user [PFM::PokemonBattler] user of the move
      # @param target_bank [Integer] bank of the target
      # @param target_position [Integer]
      def proceed(user, target_bank, target_position)
        @uncapped_damage = nil
        return super
      end
    end

    prepend UncappedDamage
  end
end
