# Affiche la description de l'objet :enigmatic_card ("Message Mystère")
# avec la police Zarbi déclarée dans Pokémon Studio.
#
# PSDK 26.57 crée les objets Text avec leur police définitive : il n'existe
# pas de méthode Text#font_id=. La zone native est donc recréée seulement
# lorsqu'on entre ou sort de la sélection du Message Mystère.
class UI::Bag::InfoWide < UI::SpriteStack
  UNOWN_FONT_ID = 5 unless const_defined?(:UNOWN_FONT_ID)
  UNOWN_MESSAGE_ITEM = :enigmatic_card unless const_defined?(:UNOWN_MESSAGE_ITEM)

  alias_method :unown_font_show_item, :show_item

  def show_item(id)
    item = id && data_item(id)
    is_unown_message = item && item.db_symbol == UNOWN_MESSAGE_ITEM

    replace_description_text(is_unown_message) if @unown_font_active != is_unown_message

    unown_font_show_item(id)
  end

  private

  def replace_description_text(use_unown_font)
    @stack.delete(@descr)
    @descr.dispose

    font_id = use_unown_font ? UNOWN_FONT_ID : 0
    @descr = with_font(font_id) { add_text(3, 37, 151, 16, nil.to_s) }
    @descr.z = 5
    @unown_font_active = use_unown_font
  end
end
