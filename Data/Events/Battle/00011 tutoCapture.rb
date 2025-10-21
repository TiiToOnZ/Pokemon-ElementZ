# Register init logic event
# This kind of event will be called before the scene actually transition,
# the goal if that event is to setup the logic the way you want.
#
# In this example, we will setup light screen & reflect on AI side with infinite amount of turns
Battle::Scene.register_event(:logic_init) do |scene|
  scene.logic.bank_effects[1].add(Battle::Effects::LightScreen.new(scene.logic, 1, 0, Float::INFINITY))
  scene.logic.bank_effects[1].add(Battle::Effects::Reflect.new(scene.logic, 1, 0, Float::INFINITY))

  # Here we will define utility function on the visual because we call something that does not exist quite often
  # It's highly recommanded that you make a script that add this function to Battle::Scene instead of doing it here
  # We can't just add this to PSDK by default because all games are different!
  def scene.show_event_message(*messages)
    visual.lock do
      # => Show all messages
      messages.each do |message|
        # Tell message box to let player read
        message_window.blocking = true
        message_window.wait_input = true
        # Actually show the message
        display_message_and_wait(message)
      end
    end
  end
end

# Register battle begin event
# This kind of event will be called right after everyone sent out their Pokémon and
# just before the player makes the first choice.
# In this kind of event, you can show some pre-battle dialogs or anything else you want.
# Don't forget to call scene.visual.lock otherwise you might get some troubles!
#
# In this example we'll show the 1st AI and make it says something
Battle::Scene.register_event(:battle_begin) do |scene|
  scene.show_event_message("Tu as plus de chance d'attraper le Pokémon s'il est affaibli !")
end

Battle::Scene.register_event(:trainer_dialog) do |scene|
  messages = case $game_temp.battle_turn
             when 1
               ["Plus la vie du Pokémon est basse, plus tu auras de chance de le capturer !\nQuand sa vie est dans le rouge, tu as le maximum de chance."]
             when 2
               ["Quand tu te sens prêt, envoie ta Poké Ball !"]
             else
               []
             end
  scene.show_event_message(*messages) unless messages.empty?
end
