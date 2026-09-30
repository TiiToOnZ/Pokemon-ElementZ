module Battle
  class Move
    class MultiHit < Basic
      # Rolls the hits a knockout cut short, for the overkill measure only, never for the engine.
      module OverkillPendingHits
        # Damage the move would still have dealt to a target it is about to knock out
        # @param user [PFM::PokemonBattler] user of the move
        # @param target [PFM::PokemonBattler] target about to go down
        # @return [Integer]
        def overkill_pending_damage(user, target)
          return 0 if overkill_remaining_hits <= 0

          # damages rewrites all three, still read afterwards for the hit that actually landed.
          saved = [@critical, @effectiveness, @uncapped_damage]
          pending = overkill_remaining_hits.times.sum { roll_one_pending_hit(user, target) }
          @critical, @effectiveness, @uncapped_damage = saved

          return pending
        end

        # Get the number of hits the move has left once the one landing is done
        # @return [Integer]
        def overkill_remaining_hits
          return @hit_amount - @nb_hit
        end

        private

        # Roll a single hit the move never got to deal
        # @param user [PFM::PokemonBattler] user of the move
        # @param target [PFM::PokemonBattler] target about to go down
        # @return [Integer]
        def roll_one_pending_hit(user, target)
          dealt = damages(user, target)
          return uncapped_damage || dealt
        end
      end

      prepend OverkillPendingHits
    end

    class TripleKick < MultiHit
      # Counts the hits left of a move that tallies the one landing only once it is over.
      module OverkillPendingHits
        # Get the number of hits the move has left once the one landing is done
        # @return [Integer]
        # @note TripleKick raises @nb_hit after the hit where MultiHit raises it before, so the blow
        #   currently landing is still counted in it here.
        def overkill_remaining_hits
          return super - 1
        end
      end

      prepend OverkillPendingHits
    end
  end
end
