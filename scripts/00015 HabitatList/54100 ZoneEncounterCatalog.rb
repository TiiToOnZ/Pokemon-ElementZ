# frozen_string_literal: true

# Read-only catalogue for the PSDK 26.60 encounter data. Nothing is saved here.
module ElementZ
  module Habitat
    GroupView = Struct.new(:key, :label, :status, :entries, :issues, keyword_init: true)
    Entry = Struct.new(:specie, :form, :seen, :caught, :habitats, keyword_init: true) do
      def revealed?
        seen || caught
      end

      def key
        [specie, form]
      end
    end
    Snapshot = Struct.new(:zone_key, :zone_name, :groups, :entries, :issues, keyword_init: true)

    TERRAIN_NAMES = {
      grass: 'Herbes', tall_grass: 'Hautes herbes', very_tall_grass: 'Herbes denses',
      cave: 'Grotte', mountain: 'Montagne', pond: 'Eau douce', ocean: 'Mer',
      sea: 'Mer', sand: 'Sable', regular_ground: 'Sol', head_butt: 'Arbres', headbutt: 'Arbres'
    }.freeze
    TOOL_NAMES = {old_rod: 'Canne', good_rod: 'Super Canne', super_rod: 'Méga Canne',
                  rock_smash: 'Éclate-Roc', headbutt: 'Coup de Boule', head_butt: 'Coup de Boule'}.freeze

    class Catalog
      # Optional adapters for custom FORM_GENERATION hooks. Return exact form IDs,
      # without constructing Pokemon or consuming the game's random generators.
      FORM_RESOLVERS = {}

      def snapshot
        zone = current_zone
        return Snapshot.new(zone_key: nil, zone_name: 'Zone inconnue', groups: [], entries: [], issues: []) unless zone

        selected_contexts = {}
        issues = []
        groups = zone.wild_groups.uniq.filter_map do |symbol|
          group = data_group(symbol)
          unless group && group.db_symbol == symbol && symbol != :__undef__
            issues << "Groupe introuvable : #{symbol}"
            next
          end
          context = [group.system_tag, group.terrain_tag, group.tool]
          enabled = group.custom_conditions.reduce(true) { |previous, condition| condition.reduce_evaluate(previous) }
          status = !enabled ? :inactive : (selected_contexts.key?(context) ? :shadowed : :active)
          # Even an empty first group masks the following groups in PSDK's #find.
          selected_contexts[context] = true if enabled
          group_issues = []
          label = group_label(group)
          entries = group.encounters.flat_map do |encounter|
            next [] unless encounter.encounter_rate > 0

            forms_for(encounter, group_issues).map do |form|
              Entry.new(specie: encounter.specie, form: form,
                        seen: $pokedex.creature_seen?(encounter.specie, form),
                        caught: $pokedex.creature_caught?(encounter.specie, form), habitats: [label])
            end
          end
          GroupView.new(key: symbol, label: label, status: status, entries: merge_entries(entries), issues: group_issues)
        end
        active = groups.select { |group| group.status == :active }
        Snapshot.new(zone_key: zone.db_symbol, zone_name: zone.name, groups: groups,
                     entries: merge_entries(active.flat_map(&:entries)),
                     issues: issues + active.flat_map(&:issues))
      end

      private

      def current_zone
        map_id = PFM.game_state.game_map.map_id
        zone = $env.get_current_zone_data
        return zone if zone && zone.db_symbol != :__undef__ && zone.maps.include?(map_id)

        # Environment#update_zone keeps its old zone on an unmapped map. Do not
        # accidentally display the previous area's encounters in that case.
        each_data_zone.find { |candidate| candidate && candidate.db_symbol != :__undef__ && candidate.maps.include?(map_id) }
      end

      def group_label(group)
        terrain = TERRAIN_NAMES.fetch(group.system_tag) { group.system_tag.to_s }
        tool = TOOL_NAMES.fetch(group.tool, group.tool&.to_s)
        label = tool ? "#{tool} / #{terrain}" : terrain
        return group.terrain_tag == 0 ? label : "#{label} (terrain #{group.terrain_tag})"
      end

      def forms_for(encounter, issues)
        creature = data_creature(encounter.specie)
        unless creature && creature.db_symbol == encounter.specie && creature.db_symbol != :__undef__
          issues << 'Espèce introuvable dans un groupe.'
          return []
        end
        forms = creature.forms.map(&:form)
        if encounter.form == -1
          if (resolver = FORM_RESOLVERS[encounter.specie])
            requested = Array(resolver.call(encounter))
          elsif !PFM::Pokemon::FORM_GENERATION[encounter.specie]
            # Same set as Encounter#generic_form_generation, without its reject!
            # (which modifies the database) or its random sample.
            requested = forms.select { |form| form < 30 }
          else
            issues << 'Forme automatique spéciale : résolution nécessaire.'
            return []
          end
        else
          requested = [encounter.form]
        end
        valid = requested.select { |form| form.is_a?(Integer) && form >= 0 && forms.include?(form) }.uniq
        issues << 'Forme absente des données Studio.' if valid.empty? || valid.size != requested.uniq.size
        return valid
      end

      def merge_entries(entries)
        result = {}
        entries.each do |entry|
          if (previous = result[entry.key])
            previous.habitats |= entry.habitats
          else
            result[entry.key] = entry.dup
            result[entry.key].habitats = entry.habitats.dup
          end
        end
        return result.values
      end
    end
  end
end
