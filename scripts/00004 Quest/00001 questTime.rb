module UI
  class QuestInformer < SpriteStack
    # Supprimer la constante existante si elle est déjà définie
    remove_const(:TEXT_REMAIN_LENGHT) if defined?(TEXT_REMAIN_LENGHT)

    # Redéfinir la constante
    TEXT_REMAIN_LENGHT = 300
  end
end

