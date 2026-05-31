# Phase 11: Tactical Battle System

This phase adds a lightweight tactical battle loop that remains part of the world rules.

## Runtime Systems

- `BattleSystem` owns the active battle.
- `BattleState` owns turn order, round, grid, and units.
- `BattleUnitState` owns battle HP, action points, speed, team, and defeat/flee state.
- `CharacterEntity` stores current HP and defeated state so battle results write back to world characters.

## Entry

Face a combatable character and press `E`.

The current scene remains loaded. Battle uses:

- the current `LocationRoot`
- the current `LocationGrid`
- existing `CharacterEntity` instances
- existing faction and relation data

## Turn Order

Units are sorted by speed descending.

Speed reads from:

1. `attributes.speed`
2. fallback `attributes.agility`

Ties sort by `character_id` for deterministic behavior.

## Controls

In combat mode:

- `WASD` / arrow keys: move the active player unit by one grid cell
- `E` / Enter: basic attack in the facing direction
- `R`: wait and end the current unit's turn
- `Esc`: flee

## Action Points

Each unit starts its turn with `action_points`.

Default:

```text
2 AP
```

Costs:

- move: `1 AP`
- basic attack: `1 AP`
- flee: `1 AP`

## Attack

`basic_attack` started as the initial attack rule in this phase. Later phases move attacks into the data-driven skill system documented in `phase_20_basic_skill_system.md`.

## Enemy Turn

The first enemy behavior is deliberately simple:

- face the player
- attack if adjacent
- otherwise move one cell toward the player if possible
- attack after moving if now adjacent
- otherwise wait

This gives the battle loop a real opponent without introducing a full AI system yet.

## World Writeback

Battle results publish `ActionResult` records through `ActionSystem.publish_result()`.

Results include:

- `battle_started`
- `battle_turn_started`
- `battle_unit_moved`
- `battle_unit_damaged`
- `battle_unit_defeated`
- `battle_unit_fled`
- `battle_ended`
- `world_character_defeated`

Defeated enemies are removed from the current scene and its local spawn cache, so they stop blocking the map and do not immediately return from the schedule system.

If the player is defeated, `GameState` receives:

```text
player_defeated = true
```

## Relations

Starting battle and attacking emit `relation_delta` changes. The target becomes more hostile toward the attacker.

## Debug

The debug panel shows:

```text
Battle: R1 current=debug_player AP2 | debug_player player HP20/20 AP2 SPD5, debug_guard enemy HP24/24 AP2 SPD4
```

## Boundaries

This phase does not implement:

- equipment-derived combat stats
- area of effect
- pathfinding
- multiple enemies or party members

The system structure is ready for those, but this phase keeps the battle loop small and complete.
