# frozen_string_literal: true

module BombanceAchievements
  module PokedexHook
    def mark_seen(db_symbol, form = 0, **kwargs)
      before = creature_seen?(db_symbol, form)
      result = super
      if !before && creature_seen?(db_symbol, form) && equal?(PFM.game_state.pokedex)
        BombanceAchievements.safely do
          BombanceAchievements.source_changed(:pokedex_forms)
          BombanceAchievements.source_changed(:completed_zones)
        end
      end
      result
    end

    def mark_captured(db_symbol, form = 0)
      before = creature_caught
      known = creature_caught?(db_symbol, form)
      result = super
      if creature_caught != before && equal?(PFM.game_state.pokedex)
        BombanceAchievements.safely { BombanceAchievements.source_changed(:pokedex_species) }
      end
      if !known && creature_caught?(db_symbol, form) && equal?(PFM.game_state.pokedex)
        BombanceAchievements.safely { BombanceAchievements.source_changed(:completed_zones) }
      end
      result
    end
  end

  module ProfessionHook
    def check_up_signal
      before = finished_quests.size
      result = super
      if finished_quests.size != before && equal?(PFM.game_state.quests)
        BombanceAchievements.safely { BombanceAchievements.source_changed(:secondary_quests_completed) }
      end
      result
    end

    def start(quest_id)
      result = super
      if result && equal?(PFM.game_state.quests)
        BombanceAchievements.safely { BombanceAchievements.quest_started(quest_id) }
      end
      result
    end
  end

  module AcquisitionHook
    def add_pokemon(pokemon)
      BombanceAchievements.safely { BombanceAchievements.baseline_acquisitions } if equal?(PFM.game_state)
      result = super
      BombanceAchievements.safely { BombanceAchievements.pokemon_acquired(pokemon) } if equal?(PFM.game_state)
      result
    end
  end

  module StorageAcquisitionHook
    def store(pokemon)
      active = equal?(PFM.game_state.storage)
      BombanceAchievements.safely { BombanceAchievements.baseline_acquisitions } if active
      result = super
      BombanceAchievements.safely { BombanceAchievements.pokemon_acquired(pokemon) } if active
      result
    end
  end

  module HatchHook
    def make_egg_hatch(pokemon)
      result = super
      # Native call_scene returns false on a scene replacement/soft reset.
      BombanceAchievements.safely { BombanceAchievements.egg_hatched(pokemon) } if result == true
      result
    end
  end

  module PokemonProgressHook
    def loyalty=(value)
      result = super
      BombanceAchievements.safely { BombanceAchievements.owned_pokemon_changed(self) } if loyalty >= 255
      result
    end

    def level=(value)
      result = super
      BombanceAchievements.safely { BombanceAchievements.owned_pokemon_changed(self) } if level >= 100
      result
    end

    def level_up_stat_refresh
      result = super
      BombanceAchievements.safely { BombanceAchievements.owned_pokemon_changed(self) } if level >= 100
      result
    end
  end

  module BattlerProgressHook
    def copy_properties_back_to_original
      result = super
      BombanceAchievements.safely { BombanceAchievements.owned_pokemon_changed(original) }
      result
    end
  end

  module BattleResultHook
    def process
      result = super
      info = @scene.battle_info
      if @logic.battle_result == 0 && info.trainer_battle? && !info.instance_variable_get(:@bombance_win_recorded)
        info.instance_variable_set(:@bombance_win_recorded, true)
        BombanceAchievements.safely { BombanceAchievements.increment(:trainer_battles_won) }
      end
      result
    end
  end

  module MapHook
    def update_graphics
      super
      Notifications.update(self)
    end

    def call_scene(*args, **kwargs, &block)
      Notifications.detach
      super
    end

    def dispose
      Notifications.detach
      super
    end
  end

  class MenuButton < UI::PSDKMenuButtonBase
    private

    def text
      'Succès'
    end

    def create_icon
      @icon = with_cache(:icon) { add_sprite(24, 11, '004', 1, 1, type: SpriteSheet) }
      @icon.set_origin(@icon.width / 2, @icon.height / 2)
      @icon.zoom = 22.0 / [@icon.width, @icon.height].max
    end
  end

  module QuestMenuLabel
    private

    def text
      'Quêtes'
    end
  end

  module MenuHook
    private

    def init_indexes
      super
      actions = GamePlay::Menu::ACTION_LIST
      index = actions.index(:open_bombance_achievements)
      return unless @image_indexes.delete(index)
      previous = @image_indexes.index(actions.index(:open_elementz_quests)) || @image_indexes.index(actions.index(:open_bag))
      @image_indexes.insert(previous ? previous + 1 : 0, index)
    end

    def open_bombance_achievements
      call_scene(GamePlay::BombanceAchievementsScene)
    end
  end
end

PFM::Pokedex.prepend(BombanceAchievements::PokedexHook)
PFM::Quests.prepend(BombanceAchievements::ProfessionHook)
PFM::GameState.prepend(BombanceAchievements::AcquisitionHook)
PFM::Storage.prepend(BombanceAchievements::StorageAcquisitionHook)
PFM::Pokemon.prepend(BombanceAchievements::PokemonProgressHook)
PFM::PokemonBattler.prepend(BombanceAchievements::BattlerProgressHook)
GamePlay.singleton_class.prepend(BombanceAchievements::HatchHook)
Battle::Logic::BattleEndHandler.prepend(BombanceAchievements::BattleResultHook)
PFM::GameState.on_expand_global_variables(:bombance_achievements) do
  bombance_achievements
  BombanceAchievements.reset_session
  BombanceAchievements.safely { BombanceAchievements.baseline_acquisitions }
end
Scheduler.add_proc(:on_init, Scene_Map, 'Bombance achievements: active save', 0) do
  BombanceAchievements.safely { BombanceAchievements.on_map_ready }
end
Scene_Map.prepend(BombanceAchievements::MapHook)
GamePlay::Menu.prepend(BombanceAchievements::MenuHook)
if defined?(ElementZ::QuestJournal::MenuButton)
  ElementZ::QuestJournal::MenuButton.prepend(BombanceAchievements::QuestMenuLabel)
end
unless GamePlay::Menu::ACTION_LIST.include?(:open_bombance_achievements)
  GamePlay::Menu.register_button(:open_bombance_achievements) { true }
end
GamePlay::Menu.register_button_overwrite(GamePlay::Menu::ACTION_LIST.index(:open_bombance_achievements)) do
  BombanceAchievements::MenuButton
end
