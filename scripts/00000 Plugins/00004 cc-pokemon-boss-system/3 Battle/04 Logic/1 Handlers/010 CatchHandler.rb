Hooks.register(Battle::Logic::CatchHandler, :ball_blocked, 'Check if catching is forbidden in this battle') do |hook_binding|
  # @type [PFM::PokemonBattler]
  target = hook_binding[:target]
  next unless target&.boss?
  next if target.nb_bars_hp == 1 && !$game_switches[Yuki::Sw::NO_CATCH_BOSS]

  $bag.add_item(hook_binding[:ball].db_symbol)
  # TODO: Add the corresponding animation (Pokeball deflect animation)
  @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 19, target))
  force_return(false)
end
