# Pokemon Boss System

Un plugin PSDK qui ajoute des combats boss avec barres de vie multiples, auras animees, IA avancee et immunites specifiques.

## Table des matieres

- [Installation](#installation)
- [Demarrage rapide](#demarrage-rapide)
- [Creer un Pokemon Boss](#creer-un-pokemon-boss)
- [Lancer un combat boss](#lancer-un-combat-boss)
- [Formats de combat](#formats-de-combat)
- [Aura du Boss (Halo)](#aura-du-boss-halo)
- [Regles de capture](#regles-de-capture)
- [Allies IA](#allies-ia)
- [Immunites & effets du Boss](#immunites--effets-du-boss)
- [Evenements de combat scriptes](#evenements-de-combat-scriptes)
- [Personnalisation](#personnalisation)
- [Arborescence](#arborescence)
- [Support](#support)
- [Credits](#credits)

---

## Installation

1. Placez `cc-pokemon-boss-system.psdkplug` dans le dossier `scripts/` de votre projet
2. Chargez le plugin :

```bash
psdk --util=plugin load
```

### Mise a jour

Remplacez le fichier `.psdkplug` et relancez la commande de chargement.

> **Attention** — Ne modifiez jamais les fichiers dans `scripts/000000 Plugins/`. Vos modifications seraient ecrasees a la prochaine mise a jour. Utilisez le monkey-patching.

---

## Demarrage rapide

```ruby
# Creer un boss avec 3 barres de vie et une aura feu
@boss = PFM::Pokemon.generate_from_hash(
  id: :charizard, level: 70,
  boss: true, nb_bars_hp: 3, boss_halo: :fire
)

# Lancer le combat
call_battle_boss(@boss)
```

---

## Creer un Pokemon Boss

Utilisez `generate_from_hash` avec les parametres boss :

```ruby
@pokemon = PFM::Pokemon.generate_from_hash(
  id: :dialga,
  level: 70,
  boss: true,         # Marque comme boss (obligatoire)
  nb_bars_hp: 3,      # Barres de vie : 0 a 5 (defaut : 0)
  boss_halo: :dragon  # Type d'aura (optionnel, voir ci-dessous)
)
```

| Parametre    | Type      | Description                                                                                                                                                 |
| ------------ | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `boss`       | `Boolean` | Marque le Pokemon comme boss. Obligatoire pour activer les mecaniques boss.                                                                                 |
| `nb_bars_hp` | `Integer` | Nombre de barres de vie (0-5). Chaque barre represente un pool de PV complet. Quand une barre est epuisee, le boss se soigne entierement et perd une barre. |
| `boss_halo`  | `Symbol`  | Aura affichee derriere le sprite du boss. Voir [Aura du Boss](#aura-du-boss-halo).                                                                          |

Tous les parametres standards de `generate_from_hash` (shiny, moves, item, etc.) fonctionnent normalement.
Voir la [documentation PSDK](https://psdk.pokemonworkshop.fr/yard/PFM/Pokemon.html#generate_from_hash-class_method).

---

## Lancer un combat boss

Depuis une commande de script RMXP :

```ruby
call_battle_boss(@pokemon)
```

Accepte 1 a 3 Pokemon. Vous pouvez mixer boss et non-boss :

```ruby
# Boss avec un allie sauvage
@boss = PFM::Pokemon.generate_from_hash(id: :dialga, level: 70, boss: true, nb_bars_hp: 3)
@sbire = PFM::Pokemon.generate_from_hash(id: :bronzong, level: 50)
call_battle_boss(@boss, @sbire)
```

### Optionnel : evenements de combat scriptes

Utilisez `battle_id` pour lier un fichier d'evenement :

```ruby
call_battle_boss(@boss, battle_id: 99999)
```

Cela charge `Data/Events/Battle/99999 AddBossEffectExample.rb`.

---

## Formats de combat

### Automatique (selon le nombre d'adversaires)

| Appel                          | Format |
| ------------------------------ | ------ |
| `call_battle_boss(@a)`         | 1v1    |
| `call_battle_boss(@a, @b)`     | 2v2    |
| `call_battle_boss(@a, @b, @c)` | 3v3    |

### Multi-combat force (le joueur envoie plusieurs Pokemon)

```ruby
# 2vX — Le joueur envoie 2 Pokemon contre 1 boss
$game_switches[901] = true  # Yuki::Sw::FORCE_2V_BATTLE
call_battle_boss(@boss)
```

```ruby
# 3vX — Le joueur envoie 3 Pokemon contre 1 ou 2 boss
$game_switches[902] = true  # Yuki::Sw::FORCE_3V_BATTLE
call_battle_boss(@boss)
call_battle_boss(@boss, @sbire)
```

| Switch            | ID  | Effet              |
| ----------------- | --- | ------------------ |
| `FORCE_2V_BATTLE` | 901 | Force le format 2v |
| `FORCE_3V_BATTLE` | 902 | Force le format 3v |

---

## Aura du Boss (Halo)

Le parametre `boss_halo` affiche une aura animee derriere le sprite du boss. Un halo par type de Pokemon est disponible, avec un effet shader glow/bloom. Compatible avec les cameras de combat 2D et 3D.

```ruby
PFM::Pokemon.generate_from_hash(
  id: :palkia, level: 70,
  boss: true, nb_bars_hp: 5, boss_halo: :water
)
```

### Types disponibles

|             |           |             |           |
| ----------- | --------- | ----------- | --------- |
| `:normal`   | `:fire`   | `:water`    | `:grass`  |
| `:electric` | `:ice`    | `:fighting` | `:poison` |
| `:ground`   | `:flying` | `:psychic`  | `:bug`    |
| `:rock`     | `:ghost`  | `:dragon`   | `:dark`   |
| `:steel`    | `:fairy`  |             |           |

---

## Regles de capture

Par defaut, un boss ne peut etre capture que lorsqu'il est a sa **derniere barre de vie**.

Pour empecher completement la capture :

```ruby
$game_switches[903] = true  # Yuki::Sw::NO_CATCH_BOSS
```

Pour re-autoriser la capture :

```ruby
$game_switches[903] = false
```

| Switch          | ID  | Effet                                         |
| --------------- | --- | --------------------------------------------- |
| `NO_CATCH_BOSS` | 903 | Empeche la capture meme sur la derniere barre |

Quand la capture est bloquee, la Pokeball est deviee et rendue au sac.

Apres capture, `boss` et `nb_bars_hp` sont automatiquement reinitialises sur le Pokemon capture.

---

## Allies IA

Ajoutez des dresseurs PNJ qui combattent aux cotes du joueur :

```ruby
# 2vX avec un dresseur allie
$game_variables[Yuki::Var::Allied_Trainer_ID] = trainer_id
call_battle_boss(@boss)

# 3vX avec deux dresseurs allies
$game_variables[Yuki::Var::Allied_Trainer_ID] = trainer_id_1
$game_variables[Yuki::Var::Second_Allied_Trainer_ID] = trainer_id_2
call_battle_boss(@boss)
```

Les combats boss utilisent automatiquement le niveau d'IA 5 pour le camp ennemi.

---

## Immunites & effets du Boss

Les boss recoivent automatiquement ces immunites via l'effet `Boss` (applique au debut du combat) :

| Immunite              | Description                                                           |
| --------------------- | --------------------------------------------------------------------- |
| Baisses de stats      | Les stats ne peuvent pas etre reduites par les adversaires            |
| Alterations de statut | Immunise au poison, brulure, sommeil, gel, paralysie, confusion, peur |
| Redirection de cible  | Ignore Poudre Dodo, Moi d'Abord, etc.                                 |
| Attaques a deux tours | Charge Lance-Soleil, Pique, etc. en un seul tour                      |
| Attaques mentales     | Immunise aux attaques avec le flag `mental`                           |
| Prevention du drain   | Les adversaires ne peuvent pas drainer les PV du boss                 |

Ces immunites sont definies dans `Data/Events/Battle/99999 AddBossEffectExample.rb` et peuvent etre personnalisees par combat via le parametre `battle_id`.

---

## Evenements de combat scriptes

Les effets boss sont appliques via des fichiers d'evenements dans `Data/Events/Battle/`. L'exemple par defaut :

```ruby
# Data/Events/Battle/99999 AddBossEffectExample.rb
Battle::Scene.register_event(:logic_init) do |scene|
  scene.logic.all_alive_battlers.each do |battler|
    next unless battler.boss?

    battler.effects.add(Battle::Effects::Boss.new(scene.logic, battler))
  end
end
```

Creez vos propres fichiers d'evenements avec differentes valeurs de `battle_id` pour personnaliser le comportement du boss par rencontre.

---

## Personnalisation

### Graphismes

Tous les graphismes boss sont dans `graphics/interface/battle/boss/` :

| Fichier                  | Description                                    |
| ------------------------ | ---------------------------------------------- |
| `battlebar_boss.png`     | Fond de la barre d'info boss (1v1, 2v2)        |
| `battlebar_boss_3v3.png` | Fond de la barre d'info boss (3v3)             |
| `hp_bar_filled.png`      | Pastille de barre de reserve pleine            |
| `hp_bar_empty.png`       | Pastille de barre de reserve vide              |
| `halo_*.png`             | Spritesheets d'aura (8x4 frames, une par type) |

### Shader

L'aura utilise un fragment shader glow/bloom : `graphics/shaders/boss_halo_glow.frag`

Ajustez l'intensite dans `003 BossHalo.rb` :

```ruby
HALO_GLOW_INTENSITY = 1.5  # Valeur par defaut, augmentez pour un bloom plus fort
```

### Textes

Les messages de combat sont au format CSV (colonnes : `en`, `fr`) :

| Fichier                        | Contenu                                                      |
| ------------------------------ | ------------------------------------------------------------ |
| `Data/Text/Dialogs/110000.csv` | Messages barre perdue/gagnee, Pokeball bloquee               |
| `Data/Text/Dialogs/110001.csv` | Messages d'apparition (toutes les combinaisons boss/sauvage) |

### Barre d'info

L'affichage de la barre de PV boss est dans :

```
scripts/000000 Plugins/XXXXXX cc-pokemon-boss-system/3 Battle/01 Scene/0 BattleUI/002 InfoBar.rb
```

---

## Arborescence

```
cc-pokemon-boss-system/
  config.yml                           # Metadonnees du plugin
  psdk.rb                              # Verification compatibilite PSDK
  scripts/
    0 Dependencies/
      001 Console Commands.rb          # Helper z_log
      180 Switch IDs.rb                # Constantes switch (901, 902, 903)
    1 PSDK Event Interpreter/
      001 Interpreter_Pokemon.rb       # Commande call_battle_boss
    2 Systems/
      000 General/1 PFM/2 Pokemon/
        001 Initialize.rb              # Props boss dans le constructeur Pokemon
        002 Properties.rb              # Accesseurs boss, nb_bars_hp, boss_halo
      999 Wild/
        001 Wild Battle (configuration).rb  # Configuration VS type & IA
        001 Wild Battle (manager).rb        # Point d'entree start_boss_battle
    3 Battle/
      01 Scene/
        0 BattleUI/
          001 MultiplePosition.rb      # Helper enemy_boss?
          002 InfoBar.rb               # UI barre de PV boss (barres de reserve)
          003 BossHalo.rb              # Sprite aura + shader glow
        101 Scene Choice.rb            # Nettoyage post-capture
      02 Visual/
        001 Visual.rb                  # Methodes visuelles ajout/retrait barre
        2 Transition/
          001 BattleStart.rb           # Messages d'apparition boss
      03 PokemonBattler/
        001 PokemonBattler.rb          # boss?, boss_halo sur le battler
      04 Logic/1 Handlers/
        000 DamageHandler.rb           # Routage degats/drain/soin boss
        010 CatchHandler.rb            # Logique blocage Pokeball
        010 DamageHandlerBoss.rb       # Degats multi-barres & KO
        010 HealHandler.rb             # Logique ajout/perte/soin barre
      06 Effects/99 Boss Effects/
        001 Boss.rb                    # Immunites & effets boss
  graphics/                            # Backup de tous les assets graphiques
    interface/battle/boss/             # Sprites UI & spritesheets halo
    shaders/                           # boss_halo_glow.frag
  Data/
    Events/Battle/
      99999 AddBossEffectExample.rb    # Enregistrement effet boss par defaut
    Text/Dialogs/
      110000.csv                       # Messages boss en combat
      110001.csv                       # Messages d'apparition
```

---

## Support

Signalez les bugs ou proposez des ameliorations sur GitLab :
https://gitlab.com/Zodiarche/cc-pokemon-boss-system/-/issues

Aucun support n'est assure sur Discord.

---

## Credits

**Zozo** — Createur et mainteneur
