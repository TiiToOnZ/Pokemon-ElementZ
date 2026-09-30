module Battle
  class Scene
    # Routing of the Adrenaline Orb once the bag handed it back to the battle.
    module AdrenalineOrbChoice
      # db_symbol of the item this routing answers for
      ADRENALINE_ORB = :adrenaline_orb

      private

      # Method that test if the item_wrapper has different logic and execute is
      # @param item_wrapper [PFM::ItemDescriptor::Wrapper]
      # @return [Boolean] if the battle should not continue normally
      def special_item_choice_action(item_wrapper)
        return super unless item_wrapper.item.db_symbol == ADRENALINE_ORB

        # Left to item_choice, the wrapper would reach Actions::Item unbound, and the bag would pay twice.
        user = @logic.battler(0, @player_actions.size)
        item_wrapper.bind(self, user)
        @player_actions << Actions::Item.new(self, item_wrapper, user.bag, user)
        # Same condition the engine puts on that list: clean_action refunds from it blindly on cancel.
        @logic.player_processing_item << item_wrapper.item if item_wrapper.item.is_limited
        @next_update = can_player_make_another_action_choice? ? :player_action_choice : :trigger_all_AI
        $bag.last_battle_item_db_symbol = item_wrapper.item.db_symbol

        return true
      end
    end
    prepend AdrenalineOrbChoice
  end
end
