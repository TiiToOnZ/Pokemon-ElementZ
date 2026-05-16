module Battle
  class Scene
    alias __capture_chain_initialize initialize

    # Stores the current battle context before the scene starts.
    def initialize(battle_info)
      CaptureChain.register_battle_context!(battle_info)
      __capture_chain_initialize(battle_info)
    end
  end

  class Logic
    class FleeHandler
      alias __capture_chain_attempt attempt

      # Breaks the chain when the player successfully flees from a relevant wild battle.
      def attempt(*args)
        result = __capture_chain_attempt(*args)
        CaptureChain.break_from_player_flee! if result == true || result == :success
        result
      end
    end

    class BattleEndHandler
      alias __capture_chain_process process

      # Evaluates chain reset rules once the battle has fully ended.
      def process(*args)
        result = __capture_chain_process(*args)
        CaptureChain.resolve_battle_end!(logic.battle_info)
        result
      end
    end
  end
end
