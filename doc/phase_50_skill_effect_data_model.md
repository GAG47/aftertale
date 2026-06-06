# Phase 50: Skill Effect Data Model

## Status

Planned.

## Goal

Turn the existing battle skill definitions into a stronger data model that can support elemental skills, terrain interaction, and future content expansion without rewriting `BattleSystem` for every new skill.

The current skill foundation already exists:

- skill definitions live under `data/skills`;
- `SkillSystem` loads skill dictionaries;
- `UseSkillAction` sends skill use through the action system;
- battle execution already supports `damage`, `heal`, and `status` effects;
- enemy decisions already read the same skill data as the player.

Phase 50 should extend this foundation rather than replace it.

## Why This Comes First

Elemental combat needs skills to express more than unit damage. A fire skill may damage a unit, mark a tile as burning, and trigger a reaction if the tile is wet. A water skill may heal, extinguish, or create a wet surface depending on the target.

If those rules are hard-coded per skill, later content becomes brittle. Phase 50 creates the vocabulary that later phases can consume.

## Proposed Skill Fields

Core fields remain compatible with current data:

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
cooldown
ends_turn
effects
feedback
```

New optional fields:

```text
element: fire, water, ice, lightning, physical, healing, none
tags: projectile, melee, magic, surface, reaction, support
target_policy: unit_required, empty_allowed, tile_only, unit_or_tile
ai_hints: optional scoring hints for Phase 54
preview: optional player-facing summary fields
```

## Effect Vocabulary

Existing effect types stay valid:

```text
damage
heal
status
```

Phase 50 should prepare additional effect shapes, even if some are executed in later phases:

```text
apply_tile_state
remove_tile_state
apply_element
cleanse_tile_state
modify_movement_cost
trigger_reaction
```

Example effect list:

```json
{
  "id": "firebolt",
  "display_name": "Firebolt",
  "skill_type": "battle",
  "target_type": "enemy",
  "target_policy": "unit_or_tile",
  "range": 3,
  "area": "single",
  "ap_cost": 1,
  "cooldown": 0,
  "element": "fire",
  "effects": [
    {
      "type": "damage",
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
- Replace the fixed `SKILL_PATHS` list with a directory load only if it is small and low risk; otherwise defer directory discovery.
- Extend skill validation through helper methods before expanding battle execution.
- Keep damage and healing formulas deterministic.
- Add summaries for UI preview, but do not let UI execute effects directly.

## Acceptance

Phase 50 is complete when:

- existing skills still load and behave the same;
- skill definitions can declare an element and multiple effect types;
- empty-cell targeting can be described explicitly through data;
- skill summaries expose enough metadata for later tile previews and AI scoring;
- unsupported new effect types fail safely or are ignored with clear debug output until their phase implements them.

## Boundary

This phase does not implement tile states, elemental reactions, or smarter AI. It only prepares skill data and execution plumbing so later phases can add those rules cleanly.
