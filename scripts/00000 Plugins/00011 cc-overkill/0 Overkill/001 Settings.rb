# Namespace of the Overkill plugin.
module Overkill
  # Tunable settings of the plugin.
  module Settings
    class << self
      # Multiplier applied to the experience yielded by an overkilled knockout
      # @return [Numeric]
      attr_accessor :exp_multiplier

      # Number of times the base effort values are granted by an overkilled knockout
      # @return [Integer]
      attr_accessor :ev_multiplier

      # Divisor applied to the loyalty of a pulverised creature of the player party
      # @return [Numeric]
      # @note At one or less the loyalty is left alone, and the engine keeps applying its own knockout malus.
      attr_accessor :loyalty_divisor

      # Multiplier applied to the target max HP to get the overkill threshold
      # @return [Numeric]
      attr_accessor :threshold_multiplier

      # Whether the overkill mechanic applies to the creatures of the player party too
      # @return [Boolean]
      # @note Off, they are never marked at all: no gauge, no message, and no revival ban either.
      attr_accessor :applies_to_player_side

      # Name of the sound played when an overkill is reached, inside Audio/SE
      # @return [String]
      # @note No folder and no extension: the animation audio command prepends audio/se/ itself.
      attr_accessor :sound_filename

      # Id of the text file holding the plugin messages, as text_get and parse_text take it
      # @return [Integer]
      # @note Studio::Text.get adds CSV_BASE (100_000), so this reads Data/Text/Dialogs/110011.csv
      attr_accessor :text_file_id
    end

    self.exp_multiplier = 1.5
    self.ev_multiplier = 2
    self.loyalty_divisor = 2
    self.threshold_multiplier = 1.0
    self.applies_to_player_side = true
    self.sound_filename = 'hitplus'
    self.text_file_id = 10_011
  end
end
