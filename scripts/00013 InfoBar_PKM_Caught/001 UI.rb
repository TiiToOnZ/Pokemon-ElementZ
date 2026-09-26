module UI
  class BattleType1Sprite < SpriteSheet
    private

    def load_texture
      filename = "types_#{$options.language}"
      load(RPG::Cache.interface_exist?(filename) ? filename : 'types', :interface)
    end
  end
end
