class Interpreter
  # Configure the SOS mechanic for the next battle only.
  # @param enabled [Boolean] whether wild creatures may call for help
  # @param species [Array<Symbol>, nil] fixed species answering the calls, in summoning order
  # @param trainers [Array<Array(Integer, Integer)>, nil] trainers that may join, with their rate in percent
  def sos_battle(enabled: true, species: nil, trainers: nil)
    $game_temp.sos_request = SOSBattles::Request.new(enabled: enabled, species: species, trainers: trainers)
  end
end
