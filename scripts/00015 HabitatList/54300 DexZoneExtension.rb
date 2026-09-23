# frozen_string_literal: true

module ElementZ
  module Habitat
    # Two narrow extensions of the actual 26.60 scene. Its initializer, states,
    # presenter, counters, map and normal controls stay owned by PSDK.
    module DexExtension
      private

      def button_texts
        texts = super.map(&:dup)
        texts[GamePlay::Dex::STATE_LIST][1] = 'Zone'
        return texts
      end

      def action_x
        return super unless list_state?

        play_decision_se
        call_scene(GamePlay::ZoneEncounters)
      end
    end
  end
end

GamePlay::Dex.prepend(ElementZ::Habitat::DexExtension)
