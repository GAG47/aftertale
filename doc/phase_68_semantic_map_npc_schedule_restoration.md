# Phase 68: Semantic Map and NPC Schedule Restoration

## Status

Complete.

## Goal

Phase 68 restores the mature v56-v59 semantic map and NPC schedule contract as
the authoritative target of generated settlements.

This phase is not a compatibility patch for older generated snapshots. It
changes the generation output itself: the settlement compiler now emits a
first-class semantic map, and generated population planning reads that semantic
map instead of treating scattered building contracts and schedule target rows as
the source of truth.

## Corrected Contract

Generated settlements now compile these concepts explicitly:

- settlement exterior location identity;
- concrete generated building interior location identity;
- building instance identity;
- exterior door and building entrance anchors;
- interior entry and exit anchors;
- object body cells;
- standing and activity cells;
- allocatable semantic schedule targets;
- target ownership by building, public plot, or location;
- validation metadata for semantic locations, buildings, anchors, and cells.

The old `schedule_targets` and `building_contracts` arrays remain serialized for
debugging and compatibility with existing readers, but Phase 68 makes
`semantic_map.targets` and `semantic_map.buildings` the preferred population
planning input.

## Runtime Rule

Phase 68 does not replace the v56-v59 NPC runtime model.

Visible NPCs still walk inside the current location. NPCs outside the current
location still settle through offscreen schedule state. Cross-location movement
is still represented by schedule transition metadata, not by generated travel
entries.

The generated pipeline is therefore:

```text
SettlementGenerationSession
-> Blueprint
-> TileSceneCompiler
-> semantic_map
-> PopulationPlanner
-> SchedulePlanner
-> existing NPC schedule runtime
```

## Implementation Result

- `TileSceneCompiler` emits `semantic_map` with schema version, locations,
  buildings, semantic targets, standing cells, object body metadata, and
  validation output.
- Public activity objects separate the inspectable object cell from the cells
  where NPCs may stand.
- Interior targets expose activity cells for allocatable roles, so NPCs are
  assigned concrete stand positions instead of stacking on object anchors.
- `GeneratedSettlementStore` persists `semantic_map` in generated settlement
  snapshots and marks new snapshots with generator version `v68`.
- `PopulationPlanner` prefers semantic map buildings and targets, falling back
  to old arrays only when semantic map data is absent.
- `SchedulePlanner` preserves semantic target metadata on each generated
  schedule entry.

## Validation

Phase 68 adds a focused smoke check:

```text
data/run_v68_smoke.json
-> scripts/tests/v68_semantic_map_npc_schedule_restoration_smoke.gd
```

The check verifies that a generated persistent settlement:

- writes a `v68` snapshot;
- exposes a valid semantic map with locations, buildings, and targets;
- has zero semantic validation errors;
- plans population from `semantic_map`;
- gives assignments and schedule entries semantic target ids;
- keeps public object body cells separate from NPC standing cells.

