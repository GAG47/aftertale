# Phase 53: Status Effects On Units

## Status

Complete.

## Goal

Connect battle tile states and elemental skill hits to unit HP, AP, statuses, and movement cost through explicit timing hooks.

The rule flow is:

```text
BattleSystem timing point
-> BattleState timing API
-> BattleTileUnitEffectSystem
-> BattleUnitState and ActionResult
```

Presentation code does not own or apply these rules.

## Timing Points

The implemented timing APIs are:

```text
on_unit_enters_cell
on_unit_starts_turn_on_cell
on_unit_ends_turn_on_cell
on_unit_hit_by_skill
```

### Enter Cell

The destination surface is synchronized to the unit immediately.

| Surface | Effect |
| --- | --- |
| Burning | Apply `burning`; deal `1 * intensity` damage |
| Wet | Apply `wet` |
| Frozen | Apply surface `chilled` |
| Electrified | Apply `shocked`; deal `1 * intensity` damage |

### Turn Start

Pending skill statuses resolve first, followed by the current surface.

| Cause | Effect |
| --- | --- |
| Skill `burning` | Deal 1 damage |
| Skill `frozen` | Reduce current AP to 0, then consume `frozen` |
| Skill `shocked` | Reduce current AP by 1, then consume `shocked` |
| Burning surface | Deal `2 * intensity` damage |
| Frozen surface | Reduce AP by 1 |
| Electrified surface | Deal `2 * intensity` damage and reduce AP by 1 |
| Wet surface | Maintain `wet` |

Automatic damage can defeat a unit and records the source character when available.

### Turn End

Statuses with `expires: turn_end` are removed through recorded status-removal events. The unit is then synchronized with its current surface, so a unit still standing on Wet ground remains Wet after temporary skill statuses expire.

### Skill Hit

Elemental skill reactions use the target's tile state from immediately before the skill effect pipeline changes the surface.

| Element | Unit result |
| --- | --- |
| Fire | Dry targets gain `burning`; Wet targets lose `wet` instead |
| Water | Remove `burning`; apply `wet` |
| Ice | Wet targets gain `frozen`; other targets gain `chilled` |
| Lightning | Apply `shocked`; Wet targets take `2 * element intensity` extra damage |

This snapshot prevents a Water, Ice, Fire, or Lightning surface transformation from erasing the condition needed to calculate the unit reaction from the same hit.

## Status Vocabulary

```text
wet
chilled
frozen
burning
shocked
```

Statuses include a `source_kind`:

```text
tile_surface
skill_hit
```

Skill statuses take precedence over a same-id surface status until they expire or are consumed. Surface statuses are then restored from the authoritative tile state.

## Movement Cost

Movement uses:

```text
BattleState.get_battle_cell_move_cost(unit, from_cell, to_cell)
```

Base movement cost is 1 AP.

- entering a Frozen tile adds `max(1, intensity)` AP;
- skill-applied `chilled` adds 1 AP to each movement step;
- surface `chilled` is descriptive and does not duplicate the Frozen tile cost.

The reachable-cell calculation now uses a weighted shortest-path search rather than a fixed-cost breadth-first search. Direct player movement and enemy movement use the same cost API.

## ActionResult Events

Automatic rules emit ordinary battle events:

```text
battle_unit_damaged
battle_unit_defeated
battle_status_applied
battle_status_removed
battle_action_points_reduced
battle_turn_ended
```

Damage events identify whether the source was:

```text
tile_state
unit_status
unit_reaction
```

This keeps UI feedback, debugging, future combat logs, and Phase 54 AI inspection on the same authoritative result stream.

## Implemented Files

```text
scripts/systems/battle/battle_tile_unit_effect_system.gd
scripts/systems/battle/battle_state.gd
scripts/systems/battle/battle_system.gd
scripts/systems/battle/battle_unit_state.gd
doc/phase_53_status_effects_on_units.md
doc/development_todo_progress.md
```

## Verification

The behavior smoke test verified:

```text
entering Burning deals damage and applies burning
turn-start Burning deals its configured damage
Wet plus Ice applies frozen
frozen consumes the next turn's AP
Wet plus Lightning deals extra reaction damage
shocked reduces next-turn AP
Frozen and chilled modify movement cost
turn-end cleanup removes temporary statuses and restores surface status
```

The temporary smoke-test hook was removed after verification.

## Boundary

Phase 53 supplies deterministic combat facts and costs. Enemy intent and tactical scoring still belong to Phase 54.
