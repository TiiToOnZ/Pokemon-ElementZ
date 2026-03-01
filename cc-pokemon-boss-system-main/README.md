# Pokemon Boss System

A PSDK plugin that adds multi-HP bar boss battles with aura effects, custom AI, and boss-specific immunities.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Creating a Boss Pokemon](#creating-a-boss-pokemon)
- [Starting a Boss Battle](#starting-a-boss-battle)
- [Battle Formats](#battle-formats)
- [Boss Aura (Halo)](#boss-aura-halo)
- [Capture Rules](#capture-rules)
- [AI Allies](#ai-allies)
- [Boss Immunities & Effects](#boss-immunities--effects)
- [Scripted Boss Events](#scripted-boss-events)
- [Customization](#customization)
- [File Structure](#file-structure)
- [Support](#support)
- [Credits](#credits)

---

## Installation

1. Place `cc-pokemon-boss-system.psdkplug` in your project's `scripts/` folder
2. Load the plugin:

```bash
psdk --util=plugin load
```

### Updating

Replace the `.psdkplug` file and re-run the load command.

> **Warning** — Never edit files directly in `scripts/000000 Plugins/`. Your changes will be overwritten on the next update. Use monkey-patching instead.

---

## Quick Start

```ruby
# Create a boss with 3 HP bars and a fire aura
@boss = PFM::Pokemon.generate_from_hash(
  id: :charizard, level: 70,
  boss: true, nb_bars_hp: 3, boss_halo: :fire
)

# Start the battle
call_battle_boss(@boss)
```

---

## Creating a Boss Pokemon

Use `generate_from_hash` with the boss-specific parameters:

```ruby
@pokemon = PFM::Pokemon.generate_from_hash(
  id: :dialga,
  level: 70,
  boss: true,         # Marks as boss (required)
  nb_bars_hp: 3,      # HP bars: 0 to 5 (default: 0)
  boss_halo: :dragon  # Aura type (optional, see below)
)
```

| Parameter    | Type      | Description                                                                                                                         |
| ------------ | --------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `boss`       | `Boolean` | Marks the Pokemon as a boss. Required for boss mechanics to apply.                                                                  |
| `nb_bars_hp` | `Integer` | Number of HP bars (0–5). Each bar represents a full HP pool. When one bar is depleted, the boss heals to full HP and loses one bar. |
| `boss_halo`  | `Symbol`  | Aura displayed behind the boss sprite. See [Boss Aura](#boss-aura-halo).                                                            |

All standard `generate_from_hash` parameters (shiny, moves, item, etc.) work as usual.
See the [PSDK documentation](https://psdk.pokemonworkshop.fr/yard/PFM/Pokemon.html#generate_from_hash-class_method).

---

## Starting a Boss Battle

From an RMXP script command:

```ruby
call_battle_boss(@pokemon)
```

Accepts 1 to 3 Pokemon. You can mix boss and non-boss Pokemon:

```ruby
# Boss with a regular wild ally
@boss = PFM::Pokemon.generate_from_hash(id: :dialga, level: 70, boss: true, nb_bars_hp: 3)
@minion = PFM::Pokemon.generate_from_hash(id: :bronzong, level: 50)
call_battle_boss(@boss, @minion)
```

### Optional: Scripted battle events

Use `battle_id` to link a scripted event file:

```ruby
call_battle_boss(@boss, battle_id: 99999)
```

This loads `Data/Events/Battle/99999 AddBossEffectExample.rb`.

---

## Battle Formats

### Automatic (based on opponent count)

| Call                           | Format |
| ------------------------------ | ------ |
| `call_battle_boss(@a)`         | 1v1    |
| `call_battle_boss(@a, @b)`     | 2v2    |
| `call_battle_boss(@a, @b, @c)` | 3v3    |

### Forced multi-battle (player sends multiple Pokemon)

```ruby
# 2vX — Player sends 2 Pokemon against 1 boss
$game_switches[901] = true  # Yuki::Sw::FORCE_2V_BATTLE
$game_switches[902] = false # Yuki::Sw::FORCE_3V_BATTLE
call_battle_boss(@boss)
```

```ruby
# 3vX — Player sends 3 Pokemon against 1 or 2 bosses
$game_switches[901] = false # Yuki::Sw::FORCE_2V_BATTLE
$game_switches[902] = true  # Yuki::Sw::FORCE_3V_BATTLE
call_battle_boss(@boss)
call_battle_boss(@boss, @minion)
```

| Switch            | ID  | Effect           |
| ----------------- | --- | ---------------- |
| `FORCE_2V_BATTLE` | 901 | Forces 2v format |
| `FORCE_3V_BATTLE` | 902 | Forces 3v format |

---

## Boss Aura (Halo)

The `boss_halo` parameter displays an animated aura behind the boss sprite. One halo per Pokemon type is available, with a glow/bloom shader effect. Compatible with both 2D and 3D battle cameras.

```ruby
PFM::Pokemon.generate_from_hash(
  id: :palkia, level: 70,
  boss: true, nb_bars_hp: 5, boss_halo: :water
)
```

### Available types

|             |           |             |           |
| ----------- | --------- | ----------- | --------- |
| `:normal`   | `:fire`   | `:water`    | `:grass`  |
| `:electric` | `:ice`    | `:fighting` | `:poison` |
| `:ground`   | `:flying` | `:psychic`  | `:bug`    |
| `:rock`     | `:ghost`  | `:dragon`   | `:dark`   |
| `:steel`    | `:fairy`  |             |           |

---

## Capture Rules

By default, a boss can only be captured when it is down to its **last HP bar**.

To completely prevent capture:

```ruby
$game_switches[903] = true  # Yuki::Sw::NO_CATCH_BOSS
```

To re-allow capture:

```ruby
$game_switches[903] = false
```

| Switch          | ID  | Effect                            |
| --------------- | --- | --------------------------------- |
| `NO_CATCH_BOSS` | 903 | Prevents capture even on last bar |

When capture is blocked, the Pokeball is deflected and returned to the bag.

After capture, `boss` and `nb_bars_hp` are automatically reset on the caught Pokemon.

---

## AI Allies

Add NPC trainers that fight alongside the player:

```ruby
# 2vX with an ally trainer
$game_variables[Yuki::Var::Allied_Trainer_ID] = trainer_id
call_battle_boss(@boss)

# 3vX with two ally trainers
$game_variables[Yuki::Var::Allied_Trainer_ID] = trainer_id_1
$game_variables[Yuki::Var::Second_Allied_Trainer_ID] = trainer_id_2
call_battle_boss(@boss)
```

Boss battles automatically use AI level 5 for the enemy side.

---

## Boss Immunities & Effects

Bosses automatically receive these immunities via the `Boss` effect (applied at battle start):

| Immunity           | Description                                                         |
| ------------------ | ------------------------------------------------------------------- |
| Stat decreases     | Cannot have stats lowered by opponents                              |
| Status conditions  | Immune to poison, burn, sleep, freeze, paralysis, confusion, flinch |
| Target redirection | Ignores Follow Me, Rage Powder, etc.                                |
| Two-turn moves     | Charges Solar Beam, Sky Attack, etc. in one turn                    |
| Mental moves       | Immune to moves with the `mental` flag                              |
| Drain prevention   | Opponents cannot drain HP from the boss                             |

These immunities are defined in `Data/Events/Battle/99999 AddBossEffectExample.rb` and can be customized per battle via the `battle_id` parameter.

---

## Scripted Boss Events

Boss effects are applied through event files in `Data/Events/Battle/`. The default example:

```ruby
# Data/Events/Battle/99999 AddBossEffectExample.rb
Battle::Scene.register_event(:logic_init) do |scene|
  scene.logic.all_alive_battlers.each do |battler|
    next unless battler.boss?

    battler.effects.add(Battle::Effects::Boss.new(scene.logic, battler))
  end
end
```

Create your own event files with different `battle_id` values to customize boss behavior per encounter.

---

## Customization

### Graphics

All boss graphics are in `graphics/interface/battle/boss/`:

| File                     | Description                                  |
| ------------------------ | -------------------------------------------- |
| `battlebar_boss.png`     | Boss info bar background (1v1, 2v2)          |
| `battlebar_boss_3v3.png` | Boss info bar background (3v3)               |
| `hp_bar_filled.png`      | Filled reserve HP bar pip                    |
| `hp_bar_empty.png`       | Empty reserve HP bar pip                     |
| `halo_*.png`             | Aura spritesheets (8x4 frames, one per type) |

### Shader

The aura uses a glow/bloom fragment shader: `graphics/shaders/boss_halo_glow.frag`

Adjust intensity in `003 BossHalo.rb`:

```ruby
HALO_GLOW_INTENSITY = 1.5  # Default value, increase for stronger bloom
```

### Texts

Battle messages are in CSV format (columns: `en`, `fr`):

| File                           | Content                                                 |
| ------------------------------ | ------------------------------------------------------- |
| `Data/Text/Dialogs/110000.csv` | Bar lost/gained messages, Pokeball blocked message      |
| `Data/Text/Dialogs/110001.csv` | Battle appearance messages (all boss/wild combinations) |

### Info Bar

The boss HP bar display is in:

```
scripts/000000 Plugins/XXXXXX cc-pokemon-boss-system/3 Battle/01 Scene/0 BattleUI/002 InfoBar.rb
```

---

## File Structure

```
cc-pokemon-boss-system/
  config.yml                           # Plugin metadata
  psdk.rb                              # PSDK compatibility check
  scripts/
    0 Dependencies/
      001 Console Commands.rb          # z_log helper
      180 Switch IDs.rb                # Switch constants (901, 902, 903)
    1 PSDK Event Interpreter/
      001 Interpreter_Pokemon.rb       # call_battle_boss command
    2 Systems/
      000 General/1 PFM/2 Pokemon/
        001 Initialize.rb              # Boss props in Pokemon constructor
        002 Properties.rb              # boss, nb_bars_hp, boss_halo accessors
      999 Wild/
        001 Wild Battle (configuration).rb  # VS type & AI configuration
        001 Wild Battle (manager).rb        # start_boss_battle entry point
    3 Battle/
      01 Scene/
        0 BattleUI/
          001 MultiplePosition.rb      # enemy_boss? helper
          002 InfoBar.rb               # Boss HP bar UI (reserve bars)
          003 BossHalo.rb              # Aura sprite + glow shader
        101 Scene Choice.rb            # Post-capture boss cleanup
      02 Visual/
        001 Visual.rb                  # Bar add/clear visual methods
        2 Transition/
          001 BattleStart.rb           # Boss appearance messages
      03 PokemonBattler/
        001 PokemonBattler.rb          # boss?, boss_halo on battler
      04 Logic/1 Handlers/
        000 DamageHandler.rb           # Boss damage/drain/heal routing
        010 CatchHandler.rb            # Ball block logic
        010 DamageHandlerBoss.rb       # Multi-bar damage & knockout
        010 HealHandler.rb             # Bar add/lose/heal logic
      06 Effects/99 Boss Effects/
        001 Boss.rb                    # Boss immunities & effects
  graphics/                            # Backup of all graphic assets
    interface/battle/boss/             # UI sprites & halo spritesheets
    shaders/                           # boss_halo_glow.frag
  Data/
    Events/Battle/
      99999 AddBossEffectExample.rb    # Default boss effect registration
    Text/Dialogs/
      110000.csv                       # In-battle boss messages
      110001.csv                       # Appearance messages
```

---

## Support

Report bugs or suggest improvements on GitLab:
https://gitlab.com/Zodiarche/cc-pokemon-boss-system/-/issues

No support is provided on Discord.

---

## Credits

**Zozo** — Creator and maintainer
