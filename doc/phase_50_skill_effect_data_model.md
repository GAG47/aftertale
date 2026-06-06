# Phase 50: Skill Effect Pipeline And Battle Resources

## Status

Complete.

## Goal

Turn the existing battle skill definitions into a stronger resource and effect pipeline that can support elemental skills, terrain interaction, and future content expansion without rewriting `BattleSystem` for every new skill.

The current skill foundation already exists:

- skill definitions live under `data/skills`;
- `SkillSystem` loads skill dictionaries;
- `UseSkillAction` sends skill use through the action system;
- battle execution already supported `damage`, `heal`, and `status` effects before this phase;
- enemy decisions already read the same skill data as the player.

Phase 50 extends this foundation rather than replacing it.

## Battle Resources

Battle units now expose these combat resources:

```text
HP: life and defeat.
MP: persistent battle resource for stronger skills.
AP: per-turn action resource.
Cooldown: per-skill pacing resource.
Status: rule modifiers such as guard, burning, frozen, shock, stun, and shields.
```

The current implementation adds `mp` and `max_mp` to `BattleUnitState` summaries. If a character does not define `max_mp`, battle units derive it from `intellect * 3`.

Skill costs now support:

```text
ap_cost
mp_cost
cooldown
ends_turn
```

Basic attacks and simple defensive actions can cost only AP. Stronger skills can cost AP, MP, and cooldown together.

## Why This Comes First

Elemental combat needs skills to express more than unit damage. A fire skill may damage a unit, mark a tile as burning, and trigger a reaction if the tile is wet. A water skill may heal, extinguish, or create a wet surface depending on the target.

If those rules are hard-coded per skill, later content becomes brittle. Phase 50 creates the vocabulary that later phases can consume.

## Skill Fields

Required skill interface fields:

```text
id
display_name
description
skill_type
target_type
range
area
radius
ap_cost
mp_cost
cooldown
ends_turn
effects
feedback
```

New optional fields:

```text
element: fire, water, ice, lightning, physical, healing, none
tags: projectile, melee, magic, surface, reaction, support
target_policy: unit_required, empty_required, cell
path_blocking: terrain_and_units, terrain_only
ai_hints: optional scoring hints for Phase 54
preview: optional player-facing summary fields
```

Target policy controls whether the selected cell is legal:

```text
unit_required: the cell must contain a unit matching target_type.
empty_required: the cell must be walkable and contain no blocking unit or object.
cell: any valid reachable cell may be selected, whether it contains an enemy, ally, or no unit.
```

`target_type` is separate from `target_policy`. For a `cell` skill, the selected center may contain any unit, while `target_type` still decides which units inside the effect area receive unit effects.

Skill definitions must use one of these three current values. Unknown or missing target policies fail definition validation and the skill is not loaded.

Path blocking controls how the skill reaches the selected cell:

```text
terrain_and_units: terrain, walls, structures, blocking objects, and intermediate units block the path.
terrain_only: terrain, walls, structures, and blocking objects block the path; intermediate units do not.
```

The target cell's unit does not count as an intermediate blocker. Both path modes still reject blocked terrain or structures at the target cell.

Implemented area shapes:

```text
single: one target cell.
radius: cells within a Manhattan radius around the target cell.
line: cardinal line from caster to target cell.
```

Not yet implemented:

```text
charge_turns / delayed skill release
```

Charge skills need an explicit pending-skill timing model so the first action can reserve intent and the later turn can resolve effects. They should not be faked as ordinary immediate effects.

## Effect Vocabulary

The supported effect types are:

```text
damage_unit
heal_unit
apply_unit_status
remove_unit_status
apply_tile_state
remove_tile_state
apply_element
```

Tile effects resolve into the battle-local tile state system from Phase 51. Since Phase 52, `apply_element` is handled by the centralized elemental reaction system.
Reaction events are not written directly by ordinary skill JSON. Skills declare elemental intent with `apply_element`; the reaction system inspects tile state and emits reaction results internally.

Example effect list:

```json
{
  "id": "firebolt",
  "display_name": "Firebolt",
  "skill_type": "battle",
  "target_type": "enemy",
  "target_policy": "cell",
  "path_blocking": "terrain_and_units",
  "range": 3,
  "area": "single",
  "ap_cost": 1,
  "cooldown": 0,
  "element": "fire",
  "effects": [
    {
      "type": "damage_unit",
      "formula": "intellect",
      "power": 2
    },
    {
      "type": "apply_element",
      "element": "fire",
      "intensity": 1
    }
  ]
}
```

## Implementation Notes

- Keep `UseSkillAction` as the rule entry point.
- Keep `SkillSystem.get_skill_failure()` as the central validation path.
- `SkillSystem` now loads all JSON files from `res://data/skills` instead of a fixed `SKILL_PATHS` list.
- Skill validation checks AP, MP, cooldown, target type, target policy, range, and path blocking.
- Skill loading validates `target_policy`, `path_blocking`, `area`, and every `effect.type`. Invalid definitions are rejected instead of normalized or silently defaulted.
- `SkillSystem` supports `single`, `radius`, and cardinal `line` area shapes for target previews, affected cells, and affected units.
- `BattleSystem` spends AP/MP, sets cooldown, records skill use, and then sends effect context to `BattleEffectResolver`.
- `BattleEffectResolver` owns effect type dispatch and unit effect application.
- Unit conditions use `status`; tile conditions use `tile_state` to keep unit and terrain rules distinct.
- Keep damage and healing formulas deterministic.
- Add summaries for UI preview, but do not let UI execute effects directly.

## Acceptance

Phase 50 is complete when:

- existing skills still load and behave the same;
- skill definitions can declare AP cost, MP cost, cooldown, element metadata, and multiple effect types;
- empty-cell targeting can be described explicitly through data;
- skill summaries expose enough metadata for later tile previews and AI scoring;
- unsupported new effect types fail safely or are ignored with clear debug output until their phase implements them;
- `BattleSystem` no longer contains hard-coded damage, heal, or status effect application.

## Implemented Files

```text
scripts/systems/battle/battle_effect_resolver.gd
scripts/systems/battle/battle_unit_state.gd
scripts/systems/battle/battle_system.gd
scripts/systems/skills/skill_system.gd
scripts/ui/battle_hud_panel.gd
scripts/ui/character_panel.gd
scripts/systems/scenes/location_root.gd
data/skills/*.json
```

## Boundary

This phase does not implement authoritative tile states, elemental reactions, or smarter AI. It prepares skill costs, effect routing, and resolver boundaries so later phases can add those rules cleanly.
