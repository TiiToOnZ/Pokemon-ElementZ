module UI
  # Cinematic egg hatching sequence
  #
  # Every duration below is in seconds, read from the source animation at the forty steps per second
  # it was written at. UI::Cinematic holds the space the coordinates live in.
  module HatchCinematic
    include Cinematic

    # Prefix of the migrated assets inside the interface cache
    IMAGE_PATH = 'cc-ui-collection/hatching/'

    # Height of the middle of a creature above the bottom of its canvas, in canvas pixels
    # @note The engine anchors a creature by the bottom of its canvas, which rests its base on the
    #   middle of the screen rather than putting its body there. Lowering the egg and the hatchling by
    #   this much centers their body where the background, the burst and the shiny sparkle all sit.
    #   A game shipping a taller egg sets this along with its own cracks strip.
    BODY_HALF_HEIGHT = 15

    # Background of the hatching, by species, for a game that wants one of its own
    # @note Names are read from the interface cache, so an image of the game lives wherever it likes
    BACKGROUNDS = {}

    # Number of seconds the scene rests on the uncovered background before the egg moves
    OPENING_WAIT_DURATION = 0.8
    # Number of bounces the egg does before it starts shaking
    BOUNCE_COUNT = 2
    # Number of seconds the egg rests after a bounce, cracked one step further
    BOUNCE_REST_DURATION = 0.6
    # Number of seconds the burst throws its ring and its sparkles out over
    BURST_DURATION = 1.6
    # Number of seconds the white takes to uncover the Pokemon
    FLASH_OUT_DURATION = 0.4
    # Number of seconds the scene rests on the Pokemon before it cries
    BURST_REST_DURATION = 0.8
    # Number of seconds a cry lasts, which the engine does not tell
    CRY_DURATION = 1.0

    # Sound played when the egg bursts open
    BURST_SE = 'audio/se/cc-ui-collection/hatching/burst'

    # Number of sparkles thrown by the burst
    SPARKLE_COUNT = 16
  end
end
