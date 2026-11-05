# frozen_string_literal: true

module ElementZ
  module PokemonForms
    # Add a sex marker to the currently displayed Pokédex form when it has
    # distinct male and female resources.
    module DexGenderIndicator
      def initialize(viewport, form_name_symbol = :form_name_upper)
        super
        @gender_indicator = add_text(150, 4, 28, 16, '', 1, color: 10)
      end

      def data=(view)
        super
        marker = ElementZ::PokemonForms.gender_indicator(view.pokemon)
        @gender_indicator.multiline_text = marker
        @gender_indicator.visible = view.seen && !marker.empty?
      end
    end

    # Return the sex marker for the form and rendered sex on the displayed
    # Pokémon. Fixed-sex, genderless, and non-dimorphic forms have no marker.
    def self.gender_indicator(pokemon)
      form = data_creature_form(pokemon.db_symbol, pokemon.form)
      return '' unless form.resources.has_female && form.female_rate.between?(1, 99)

      return pokemon.female? ? '♀' : '♂'
    end
  end
end

UI::Dex::InfoPanel.prepend(ElementZ::PokemonForms::DexGenderIndicator)
