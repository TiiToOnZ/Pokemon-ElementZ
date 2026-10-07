module BombanceTripleBattlePosition
  # Ajustements visuels des slots de chaque côté en formation simple, double ou triple.
  #
  # X négatif = gauche / X positif = droite
  # Y négatif = haut    / Y positif = bas
  #
  # S'applique aux rendus 2D et 3D.

  # ---------------------------------------------------------------------------
  # SIMPLE
  # ---------------------------------------------------------------------------

  ENEMY_SINGLE_OFFSETS = {
    0 => [0, 0] # Pokémon ennemi
  }.freeze

  PLAYER_SINGLE_OFFSETS = {
    0 => [-2, 6] # Pokémon joueur
  }.freeze

  # ---------------------------------------------------------------------------
  # DOUBLE
  # ---------------------------------------------------------------------------

  ENEMY_DOUBLE_OFFSETS = {
    0 => [-4, 9], # Premier Pokémon
    1 => [0, 3]   # Deuxième Pokémon
  }.freeze

  PLAYER_DOUBLE_OFFSETS = {
    0 => [-5, 0], # Premier Pokémon
    1 => [0, 6]   # Deuxième Pokémon
  }.freeze

  # ---------------------------------------------------------------------------
  # TRIPLE
  # ---------------------------------------------------------------------------

  ENEMY_TRIPLE_OFFSETS = {
    0 => [-2, 16], # Premier Pokémon
    1 => [0, 4],   # Deuxième Pokémon
    2 => [0, 0]    # Troisième Pokémon
  }.freeze

  PLAYER_TRIPLE_OFFSETS = {
    0 => [-5, 10],  # Premier Pokémon
    1 => [-16, 9],  # Deuxième Pokémon
    2 => [0, 0]     # Troisième Pokémon
  }.freeze

  def self.visual_offset_for(sprite)
    return [0, 0] unless sprite.is_a?(BattleUI::PokemonSprite)

    pokemon = sprite.pokemon
    return [0, 0] unless pokemon

    bank = pokemon.bank
    position = pokemon.position

    return [0, 0] unless [0, 1].include?(bank)
    return [0, 0] unless position.is_a?(Integer) && (0...3).include?(position)
    return [0, 0] unless sprite.bank == bank && sprite.position == position

    scene = sprite.scene
    field_size = scene&.battle_info&.vs_type

    return [0, 0] unless field_size.is_a?(Integer) && [1, 2, 3].include?(field_size)
    return [0, 0] unless position < field_size

    logic = scene.logic
    return [0, 0] unless logic
    return [0, 0] unless logic.battler(bank, position).equal?(pokemon)

    # -------------------------------------------------------------------------
    # SIMPLE
    # -------------------------------------------------------------------------

    if field_size == 1
      offsets = bank == 0 ? PLAYER_SINGLE_OFFSETS : ENEMY_SINGLE_OFFSETS
      return offsets.fetch(position, [0, 0])
    end

    # -------------------------------------------------------------------------
    # DOUBLE / TRIPLE
    #
    # vs_type délimite le terrain ; les occupants valident CETTE banque.
    # Les réserves (position -1) et les slots SOS vides ne comptent pas.
    # -------------------------------------------------------------------------

    occupied = (0...field_size).map do |slot|
      occupant = logic.battler(bank, slot)
      occupant && occupant.bank == bank && occupant.position == slot
    end

    return [0, 0] unless occupied[0]

    # Triple uniquement si les trois emplacements de cette banque sont occupés.
    if field_size == 3 && occupied[1] && occupied[2]
      offsets = bank == 0 ? PLAYER_TRIPLE_OFFSETS : ENEMY_TRIPLE_OFFSETS
      return offsets.fetch(position, [0, 0])
    end

    # Double si les deux premiers emplacements de cette banque sont occupés.
    if occupied[1]
      offsets = bank == 0 ? PLAYER_DOUBLE_OFFSETS : ENEMY_DOUBLE_OFFSETS
      return offsets.fetch(position, [0, 0])
    end

    [0, 0]
  end

  private

  def sprite_position
    info = scene&.battle_info
    return [x, y] unless info &&
                             [1, 2, 3].include?(info.vs_type) &&
                             position.is_a?(Integer)

    coordinates = super

    dx, dy = BombanceTripleBattlePosition.visual_offset_for(self)

    return coordinates if dx == 0 && dy == 0

    [coordinates[0] + dx, coordinates[1] + dy]
  end
end

BattleUI::PokemonSprite.prepend(BombanceTripleBattlePosition)