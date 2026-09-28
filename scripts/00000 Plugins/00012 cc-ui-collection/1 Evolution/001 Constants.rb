module UI
  # Cinematic evolution sequence
  #
  # Every duration below is in seconds, read from the source animation at the forty steps per second
  # it was written at. UI::Cinematic holds the space the coordinates live in.
  module EvolveCinematic
    include Cinematic

    # Prefix of the migrated assets inside the interface cache
    IMAGE_PATH = 'cc-ui-collection/evolution/'

    # Number of seconds the main evolution loop lasts
    MAIN_LOOP_DURATION = 6.4
    # Number of seconds the white flash lasts
    FLASH_DURATION = 1.6
    # Number of seconds the white flash lasts when the evolution was cancelled
    CANCELLED_FLASH_DURATION = 0.8
    # Number of seconds the rising sparkles last
    SPARKLE_DURATION = 1.6

    # Sound played when the Pokemon starts to glow
    GLOW_SE = 'audio/se/cc-ui-collection/evolution/glow'
    # Sound played when both forms start trading places
    LOOP_SE = 'audio/se/cc-ui-collection/evolution/loop'
    # Sound played on the flash revealing the Pokemon the scene ends on
    FLASH_SE = 'audio/se/cc-ui-collection/evolution/flash'
    # Volume of the flash sound, which is loud enough to cover the rest at full volume
    FLASH_SE_VOLUME = 80
    # Sound played on the rising sparkles
    SPARKLE_SE = 'audio/se/cc-ui-collection/evolution/sparkle'

    # z superiority of the particles and the rays, the two families being shot at the same depth
    EFFECT_Z = 60

    # Number of particles orbiting around the evolving Pokemon
    PARTICLE_COUNT = 16
    # Number of light rays shot during the main loop
    RAY_COUNT = 8
    # Number of sparkles rising once the evolution is done
    SPARKLE_COUNT = 64
  end
end
