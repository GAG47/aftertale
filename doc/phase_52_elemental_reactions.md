# Phase 52: Elemental Reactions

## Status

Planned.

## Goal

Create a centralized elemental reaction system so skills apply elements and the battle rules decide how elements interact with tile states, units, and existing surfaces.

This phase should make fire, water, ice, and lightning tactically meaningful without scattering special cases through individual skill definitions.

## Core Rule

Skills should not own reaction logic.

Preferred flow:

```text
skill applies element
-> reaction system reads target cell, tile state, units, and tags
-> reaction system emits deterministic changes
-> BattleSystem applies those changes through ActionResult
```

## Minimum Reaction Table

Fire:

- fire on empty flammable or neutral surface can create burning;
- fire on wet removes wet or fails to ignite;
- fire on frozen melts frozen into wet;
- fire on poison cloud can later trigger explosion, deferred.

Water:

- water on burning extinguishes burning and creates wet;
- water on empty ground creates wet;
- water on electrified may spread or refresh electrified, deferred if too large.

Ice:

- ice on wet creates frozen;
- ice on water-like surfaces creates frozen;
- ice on a unit standing on wet may apply frozen or chilled unit status in Phase 53.

Lightning:

- lightning on wet creates electrified and can spread;
- lightning on conductive tags can spread;
- lightning on a wet unit gains bonus damage or area chaining;
- lightning on normal dry ground behaves as ordinary damage.

## Reaction Input

Recommended reaction request:

```text
element
source_character_id
source_skill_id
target_cell
target_unit_id
intensity
area_cells
```

The reaction system should inspect:

```text
current tile state
cell tags
unit tags or statuses
skill tags
```

## Reaction Output

Recommended output events:

```text
apply_tile_state
remove_tile_state
refresh_tile_state
apply_unit_status
deal_reaction_damage
spawn_reaction_cells
feedback
```

These outputs should be consumed by `BattleSystem` or a battle rule helper, then written into `ActionResult` world changes and feedback.

## Spread Rules

Start with conservative spread:

- wet lightning spreads only through directly adjacent wet cells;
- maximum spread distance is small, such as 2 cells;
- each cell is processed once;
- friendly fire rules should be explicit and deterministic.

This keeps the system readable and prevents one lightning skill from becoming an accidental full-map solver.

## Acceptance

Phase 52 is complete when:

- fire, water, ice, and lightning have centralized reaction rules;
- the minimum four test skills can create visible and rule-owned reactions;
- reaction output is deterministic and debuggable;
- reaction results appear in `ActionResult` feedback and battle summaries;
- unsupported reactions fall back to a harmless default.

## Boundary

This phase may create or remove tile states and may produce reaction damage. It should not yet make enemy AI intentionally plan around reactions; that belongs to Phase 54.
