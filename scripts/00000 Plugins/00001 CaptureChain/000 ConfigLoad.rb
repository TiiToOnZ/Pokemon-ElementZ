module Configs  
  module Project
    class CaptureChain
      # Storage key used in the save user data hash.
      # @return [String, Symbol]
      attr_accessor :storage_key

      # Number of IV stats handled by the chain bonus logic.
      # @return [Integer]
      attr_accessor :stat_count

      # Chain bonus thresholds.
      # @return [Array<Hash>]
      attr_accessor :bonus_table

      # Whether fleeing from the player breaks the current chain.
      # @return [Boolean]
      attr_accessor :break_on_player_flee

      # Whether losing or ending a battle without capture breaks the chain
      # when fighting the chained species.
      # @return [Boolean]
      attr_accessor :break_on_failed_battle_against_chained_species
    end
  end
  
  # Register CaptureChain configuration file.
  register(:capture_chain, 'capturechain_config', :json, false, Project::CaptureChain)
end
