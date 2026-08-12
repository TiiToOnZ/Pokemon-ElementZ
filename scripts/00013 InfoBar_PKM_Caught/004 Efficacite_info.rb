module EffectivenessPreview
  remove_const(:DISPLAY_MODE)
  remove_const(:SHOW_WHEN_NEUTRAL)
  remove_const(:SHOW_FOR_CREATURES)
  remove_const(:TEXT_COLOR)
  remove_const(:VARIABLE_TEXT)
  remove_const(:BACKGROUND_IMAGE)
  remove_const(:BACKGROUND_POSITION)
  remove_const(:MODE_2_BACKGROUND_IMAGE)
  remove_const(:MODE_2_BACKGROUND_OFFSET)

  DISPLAY_MODE = 2
  SHOW_WHEN_NEUTRAL = true
  SHOW_FOR_CREATURES = :CAUGHT
  TEXT_COLOR = 9
  VARIABLE_TEXT = 'Variable'
  BACKGROUND_IMAGE = 'battle/button_effectiveness_fixed_preview'
  BACKGROUND_POSITION = [2, 188]
  MODE_2_BACKGROUND_IMAGE = 'battle/button_effectiveness_skill_preview'
  MODE_2_BACKGROUND_OFFSET = [-3, 2]
end