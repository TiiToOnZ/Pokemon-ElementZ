module Battle
  class Logic
    class DamageHandler < ChangeHandlerBase
      # Processes the damage dealt to a boss or another Pokémon.
      # @param hp [Integer] The amount of HP (damage) dealt.
      # @param target [PFM::PokemonBattler] The target Pokémon receiving the damage.
      # @param launcher [PFM::PokemonBattler, nil] The Pokémon that launched the move, if applicable.
      # @param skill [Battle::Move, nil] The move used, if applicable.
      # @param messages [Proc] The messages shown right before the post-processing.
      def damage_change_boss(hp, target, launcher = nil, skill = nil, &messages)
        hp = hp.clamp(1, Float::INFINITY)
        handle_damage(hp, target, launcher, skill, &messages)

        target.add_damage_to_history(hp, launcher, skill, target.dead?)
        log_data("# damage_change(#{hp}, #{target}, #{launcher}, #{skill}, #{target.dead?})")
      rescue Hooks::ForceReturn => e
        log_data("# FR: damage_change : #{e.data} from #{e.hook_name} (#{e.reason})")
        return e.data
      ensure
        @scene.visual.refresh_info_bar(target)
      end

      # Function that drains a certain quantity of HP from the target and gives it to the user.
      # @param hp_factor [Integer] The division factor of HP to drain.
      # @param target [PFM::PokemonBattler] The target that gets HP drained.
      # @param launcher [PFM::PokemonBattler] The launcher of a draining move/effect.
      # @param skill [Battle::Move, nil] The potential move used.
      # @param hp_overwrite [Integer, nil] The number of HP drained by the move, if provided.
      # @param drain_factor [Integer] The division factor of HP drained.
      # @param messages [Proc] The messages shown right before the post-processing.
      def drain_boss(hp_factor, target, launcher, skill = nil, hp_overwrite: nil, drain_factor: 1, &messages)
        hp = hp_overwrite || (target.max_hp / hp_factor).clamp(1, Float::INFINITY)
        handle_damage(hp, target, launcher, skill, drain_factor: drain_factor, source: :drain, &messages)

        target.add_damage_to_history(hp, launcher, skill, target.dead?)
        log_data("# drain_boss(#{hp}, #{target}, #{launcher}, #{skill}, #{target.dead?})")
      rescue Hooks::ForceReturn => e
        log_data("# FR: drain : #{e.data} from #{e.hook_name} (#{e.reason})")
        return e.data
      ensure
        @scene.visual.refresh_info_bar(target)
      end

      private

      # Calculates the damage dealt, checks for knockout, and updates the skill damage if applicable.
      # @param hp [Integer] The amount of HP (damage) dealt.
      # @param target [PFM::PokemonBattler] The target Pokémon receiving the damage.
      # @param launcher [PFM::PokemonBattler, nil] The Pokémon that launched the move, if applicable.
      # @param skill [Battle::Move, nil] The move used, if applicable.
      # @param drain_factor [Integer] The division factor of HP drained.
      # @param source [:default, :drain] The source of the damage calculation.
      # @param messages [Proc] The messages shown right before the post-processing.
      def handle_damage(hp, target, launcher, skill, drain_factor: 1, source: :default, &messages)
        update_skill_damage(hp, target, skill)

        if hp >= target.hp
          handle_knockout(hp, target, launcher, skill, drain_factor, source, &messages)
        else
          show_hp_animations(hp, target, skill, &messages)
          handle_drain_effects(hp, target, launcher, skill, drain_factor) if source == :drain
          exec_hooks(DamageHandler, :post_damage, binding)
        end
      end

      # Handles the specific logic for draining HP and transferring it to the launcher.
      # @param hp [Integer] The amount of HP (damage) dealt.
      # @param target [PFM::PokemonBattler] The target Pokémon receiving the damage.
      # @param launcher [PFM::PokemonBattler] The launcher of a draining move/effect.
      # @param skill [Battle::Move, nil] The move used, if applicable.
      # @param drain_factor [Integer] The division factor of HP drained.
      def handle_drain_effects(hp, target, launcher, skill, drain_factor)
        hp_multiplier = 1.0
        exec_hooks(DamageHandler, :pre_drain, binding)

        hp_healed = (hp * hp_multiplier / drain_factor).to_i.clamp(1, Float::INFINITY)
        exec_hooks(DamageHandler, :drain_prevention, binding)
        return if hp_healed.zero? || launcher.dead?

        @scene.display_message_and_wait(parse_text_with_pokemon(10_000, 12, target)) if heal(launcher, hp_healed)
      end

      # Handles the knockout of a Pokémon, considering special cases for bosses.
      # @param hp [Integer] The amount of HP (damage) dealt.
      # @param target [PFM::PokemonBattler] The target Pokémon receiving the damage.
      # @param launcher [PFM::PokemonBattler, nil] The Pokémon that launched the move, if applicable.
      # @param skill [Battle::Move, nil] The move used, if applicable.
      # @param drain_factor [Integer] The division factor of HP drained.
      # @param source [:default, :drain] The source of the damage calculation.
      # @param messages [Proc] The messages shown right before the post-processing.
      def handle_knockout(hp, target, launcher, skill, drain_factor, source, &messages)
        if target.nb_bars_hp > 1
          handle_boss_bar_removal(hp, target, launcher, skill, drain_factor, source, &messages)
        else
          show_hp_animations(hp, target, skill, &messages)
          handle_drain_effects(hp, target, launcher, skill, drain_factor) if source == :drain
          exec_hooks(DamageHandler, :post_damage_death, binding)
          target.ko_count += 1
        end
      end

      # Handles the removal of a health bar from a boss.
      # @param hp [Integer] The amount of HP (damage) dealt.
      # @param target [PFM::PokemonBattler] The target Pokémon receiving the damage.
      # @param launcher [PFM::PokemonBattler, nil] The Pokémon that launched the move, if applicable.
      # @param skill [Battle::Move, nil] The move used, if applicable.
      # @param drain_factor [Integer] The division factor of HP drained.
      # @param source [:default, :drain] The source of the damage calculation.
      # @param messages [Proc] The messages shown right before the post-processing.
      def handle_boss_bar_removal(hp, target, launcher, skill, drain_factor, source, &messages)
        show_hp_animations(target.hp - 1, target, skill, &messages)
        handle_drain_effects(hp, target, launcher, skill, drain_factor) if source == :drain
        heal_boss(target, target.max_hp, test_heal_block: false, bar_state: :losing)
        exec_hooks(DamageHandler, :post_damage_death, binding)
        target.ko_count += 1
      end
    end
  end
end
