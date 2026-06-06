# Phase 52: Elemental Reactions

## Status

Complete.

## Goal

Centralize elemental rules so ordinary skills only declare elemental intent. Skills do not know which surface should be created, removed, refreshed, or transformed.

```text
skill effect: apply_element
-> BattleEffectResolver
-> BattleElementReactionSystem
-> BattleState tile-state operations
-> reaction_event in ActionResult
```

## Skill Interface

Elemental skills use this effect:

```json
{
  "type": "apply_element",
  "element": "fire",
  "intensity": 1
}
```

Supported elements are strict:

```text
fire
water
ice
lightning
```

`SkillSystem` rejects unsupported element names and intensity values below 1. Ordinary skill JSON does not write `reaction_event` and does not choose `burning`, `wet`, `frozen`, or `electrified`.

## Implemented Reaction Rules

| Applied element | Existing surface | Result |
| --- | --- | --- |
| Fire | none or neutral | Burning |
| Fire | Wet | Wet is evaporated |
| Fire | Frozen | Frozen becomes Wet |
| Fire | Burning | Burning is refreshed |
| Water | none or neutral | Wet |
| Water | Burning | Burning becomes Wet |
| Water | Electrified | Electrified is refreshed |
| Water | Frozen | Frozen remains |
| Ice | Wet | Wet becomes Frozen |
| Ice | Burning | Burning is removed |
| Ice | Frozen | Frozen is refreshed |
| Ice | dry ground | No surface change |
| Lightning | Wet | Wet becomes Electrified |
| Lightning | Electrified | Electrified is refreshed |
| Lightning | dry ground | No surface change |

## Lightning Spread

Lightning spreads from an electrified target through orthogonally connected Wet cells.

- maximum spread distance: 2 cells;
- each cell is processed once;
- map bounds are respected;
- only connected Wet cells conduct;
- every converted cell emits its own deterministic reaction event.

## Reaction Events

`BattleState.record_reaction()` stores the latest 24 reactions and writes a `reaction_event` world change into the current `ActionResult`.

Each event includes:

```text
reaction_id
element
cell
previous_state_id
result_state_id
source_character_id
source_skill_id
round
turn_index
feedback
```

`BattleState.get_summary()` exposes these records as `recent_reactions`, so future UI, debugging tools, and enemy AI can inspect the same authoritative facts.

## Test Skills

```text
debug_fire_patch: single-cell fire application
debug_fire_burst: radius fire plus unit damage
debug_meteor: radius fire with terrain-only path blocking
debug_water_splash: radius water application
debug_frost_field: radius ice application
debug_line_beam: straight-line lightning plus unit damage
```

All elemental test skills use `apply_element`. None directly creates or removes an elemental tile state.

Recommended manual chains:

```text
Water Splash -> Frost Field
Wet -> Frozen

Fire Patch -> Water Splash
Burning -> Wet

Water Splash -> Line Beam
Wet -> Electrified, with connected Wet spread

Frost Field on Wet -> Fire Patch
Frozen -> Wet
```

## Implemented Files

```text
scripts/systems/battle/battle_element_reaction_system.gd
scripts/systems/battle/battle_effect_resolver.gd
scripts/systems/battle/battle_state.gd
scripts/systems/skills/skill_system.gd
data/skills/debug_fire_patch.json
data/skills/debug_fire_burst.json
data/skills/debug_meteor.json
data/skills/debug_water_splash.json
data/skills/debug_frost_field.json
data/skills/debug_line_beam.json
data/characters/debug_player.json
```

## Boundary

Phase 52 owns element-to-surface reactions and reaction events. Unit statuses, damage from standing on surfaces, frozen units, and reaction timing on movement or turn start belong to Phase 53. Enemy planning around these facts belongs to Phase 54.
