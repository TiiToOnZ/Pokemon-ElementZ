Battle::Scene.register_event(:logic_init) do |scene|
  scene.logic.all_alive_battlers.each do |battler|
    next unless battler.boss?

    battler.effects.add(Battle::Effects::Boss.new(scene.logic, battler))
  end
end
