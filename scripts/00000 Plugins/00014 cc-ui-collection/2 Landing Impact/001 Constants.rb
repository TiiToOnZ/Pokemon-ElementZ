module UI
  # Impact of a Pokemon hitting the ground when it is sent out, graded by its weight
  #
  # The dust cloud it raises is transcribed from Elite Battle DX, written as a list of steps, so the
  # numbers below count steps and the tempo they are played at turns them into seconds.
  module LandingImpact
    # Number of steps the transcribed animation plays per second
    STEP_RATE = 40
    # Path of the dust particle inside the animation cache
    DUST_IMAGE = 'cc-ui-collection/landing-impact/dust'
    # Sound of a Pokemon landing, pitched by its tier
    DROP_SE = 'audio/se/cc-ui-collection/landing-impact/drop'
    # Sound of a heavy Pokemon landing
    DROP_HEAVY_SE = 'audio/se/cc-ui-collection/landing-impact/drop_heavy'
    # Volume every landing sound is played at
    SE_VOLUME = 100

    # Weight, in kilograms, a Pokemon reaches to leave the light tier
    MEDIUM_MIN_WEIGHT = 50
    # Weight, in kilograms, a Pokemon reaches to raise dust
    HEAVY_MIN_WEIGHT = 150

    # Species that land silently, the hardcoded exemptions of the fifth generation
    # @note A form does not change the db_symbol of its species, so Mega Gengar is covered by gengar
    SILENT_SPECIES = %i[diglett dugtrio gengar]

    # Properties of each weight tier, the shake being the amplitude the battle camera moves by
    TIERS = {
      light: { shake: 3, se: DROP_SE, pitch: 120, dust: false },
      medium: { shake: 5, se: DROP_SE, pitch: 80, dust: false },
      heavy: { shake: 8, se: DROP_HEAVY_SE, pitch: 100, dust: true }
    }

    # Number of steps the dust takes to reach full opacity
    DUST_FADE_IN_STEPS = 10
    # Source frame the dust starts fading out at
    DUST_FADE_OUT_FRAME = 14
    # Number of steps the whole dust animation lasts
    DUST_STEPS = 24
    # Opacity the dust gains, then loses, on each step
    DUST_OPACITY_STEP = 255.0 / DUST_FADE_IN_STEPS
    # Number of pixels a dust particle drifts away from the Pokemon on each step
    DUST_DRIFT_PER_STEP = 2
    # Number of degrees a dust particle turns on each step
    DUST_ROTATION_PER_STEP = 4
    # Number of dust particles a Pokemon of no width would raise
    DUST_BASE_COUNT = 16
    # Number of pixels of Pokemon width each additional dust particle is worth
    DUST_WIDTH_PER_PARTICLE = 16
    # Number of pixels of Pokemon width the dust never spreads over, on each side
    DUST_SPREAD_MARGIN = 16
    # Height, in pixels, the dust particles are scattered over, centered on the feet
    DUST_VERTICAL_SPREAD = 32
    # Zoom values a dust particle picks from
    DUST_ZOOMS = [1, 0.8, 0.9, 0.7]

    module_function

    # Get the duration in seconds of a number of steps
    # @param step_count [Numeric]
    # @return [Float]
    def step_duration(step_count)
      return step_count / STEP_RATE.to_f
    end

    # Get the weight tier a Pokemon lands with
    # @param pokemon [PFM::PokemonBattler, nil]
    # @return [Symbol, nil] nil when the Pokemon lands without making a sound
    def tier_of(pokemon)
      return unless CCUICollection::Settings.landing_impact
      return unless pokemon&.grounded?
      return if SILENT_SPECIES.include?(pokemon.db_symbol)

      weight = pokemon.weight
      return :heavy if weight >= HEAVY_MIN_WEIGHT
      return :medium if weight >= MEDIUM_MIN_WEIGHT

      return :light
    end

    # Get the amplitude the battle camera shakes by on a tier
    # @param tier [Symbol]
    # @return [Integer]
    def shake_amplitude(tier)
      return TIERS[tier][:shake]
    end

    # Play the sound a tier lands with
    # @param tier [Symbol]
    def play_landing_se(tier)
      properties = TIERS[tier]
      Audio.se_play(properties[:se], SE_VOLUME, properties[:pitch])
    end

    # Tell if a tier raises dust
    # @param tier [Symbol]
    # @return [Boolean]
    def dust?(tier)
      return TIERS[tier][:dust]
    end

    # Get half the width the dust of a Pokemon is scattered over, in unzoomed pixels
    # @param bitmap_width [Integer]
    # @return [Integer]
    def dust_spread(bitmap_width)
      return [bitmap_width / 2 - DUST_SPREAD_MARGIN, 0].max
    end

    # Get the number of dust particles the width of a Pokemon is worth
    # @param bitmap_width [Integer]
    # @return [Integer]
    def dust_count(bitmap_width)
      return DUST_BASE_COUNT + dust_spread(bitmap_width) / DUST_WIDTH_PER_PARTICLE
    end
  end
end
