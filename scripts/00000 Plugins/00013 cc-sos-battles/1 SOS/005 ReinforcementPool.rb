module SOSBattles
  # Weighted draw in an encounter group, and lookup in the family of the caller.
  module ReinforcementPool
    # Lowest form index reserved for mega, second mega and gigantamax forms
    SPECIAL_FORM_INDEX = 30

    class << self
      # Pick one encounter of a group, weighted by its encounter rate.
      # @param encounters [Array<Studio::Group::Encounter>] encounters of the current group
      # @param roll [Float] value in [0, 1) driving the draw
      # @return [Studio::Group::Encounter, nil]
      def pick_encounter(encounters, roll)
        total = encounters.sum(&:encounter_rate)
        return if total <= 0

        target = roll * total
        cumulated = 0
        encounters.each do |encounter|
          cumulated += encounter.encounter_rate
          return encounter if target < cumulated
        end

        return encounters.last
      end

      # Family member the caller may summon.
      # @param form [Studio::CreatureForm] form of the caller
      # @param allow_evolution [Boolean] whether an evolution may answer
      # @return [Array(Symbol, Integer), nil] db_symbol and form of the answering creature
      def family_member(form, allow_evolution)
        baby = form.baby_db_symbol
        return [baby, form.baby_form] if baby && baby != :__undef__ && regular_form?(form.baby_form)

        return unless allow_evolution

        evolution = form.evolutions.select { |candidate| regular_form?(candidate.form) }.sample
        return unless evolution

        return [evolution.db_symbol, evolution.form]
      end

      private

      # Whether a form index is a regular form rather than a mega, a second mega or a gigantamax one.
      # @note Mirrors what Studio::Group::Encounter#generic_form_generation rejects.
      # @param form [Integer, nil] form index
      # @return [Boolean]
      def regular_form?(form)
        return true if form.nil?

        return form < SPECIAL_FORM_INDEX
      end
    end
  end
end
