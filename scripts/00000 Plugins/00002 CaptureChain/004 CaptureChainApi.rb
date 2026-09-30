class Interpreter
  # Returns the full chain status hash.
  def capture_chain_status
    CaptureChain.status
  end

  # Returns the current chain count.
  def capture_chain_count
    CaptureChain.count
  end

  # Returns the species currently associated with the chain.
  def capture_chain_species
    CaptureChain.species
  end

  # Returns the currently active bonus entry.
  def capture_chain_bonus
    CaptureChain.current_bonus
  end

  # Returns the current shiny rate bonus.
  def capture_chain_shiny_rate
    CaptureChain.shiny_rate
  end

  # Resets the current chain from an event or script call.
  def reset_capture_chain
    CaptureChain.reset!
  end
end
