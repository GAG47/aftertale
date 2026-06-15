# Phase 59: Semantic Town Layout

## Status

Complete.

Superseded as the active layout authority by Phase 60. Phase 59 remains the
historical record of the BSP district-graph attempt; the current generator uses
road-first frontage allocation instead of BSP leaves.

## Goal

Phase 59 changes village generation from direct whole-map BSP occupation into a
BSP district graph interpreted by a semantic town planner.

The previous generator could create a usable village, but buildings competed
for generic BSP leaves across the whole map. That made the result technically
valid but too evenly scattered and too mathematical. The first v59 attempt also
went too far in the other direction by using fixed semantic rectangles. That
made the village look like a zoning diagram and removed the variation that BSP
is supposed to provide.

The corrected v59 implementation keeps BSP as the source of layout variation:

```text
BSP leaves
-> district graph
-> role assignment
-> selected town zones
-> parcel placement
-> prefab placement
```

BSP creates the district candidates. The planner interprets those candidates
instead of replacing them with hard-coded rectangles.

## Debug Parcel Presentation

F3 now toggles scene debug presentation in addition to the UI debug panel.

Normal gameplay rendering still hides debug parcel rectangles. When the debug
panel is visible, `LocationRoot` enables the debug presentation layer on the
scene renderers, so parcel surfaces and front-clearance rectangles can be
inspected again.

This keeps the two needs separate:

- gameplay view shows only the normal building and frontage presentation;
- debug view shows generated parcel boundaries and reserved frontage areas.

## Semantic Town Zones

The generated village now records explicit `town_zones`.

The core zones are:

- `plaza`: civic center;
- `residential`: clustered homes;
- `tavern`: social frontage near the main street;
- `market`: shop and workshop frontage near the plaza;
- `farm`: continuous farm block;
- `farm_service`: farm-adjacent residential/service lot;
- `farm_storage`: storage lot near the farm;
- `training`: training yard;
- `gate`: east exit;
- `gate_service`: guardhouse lot near the exit.

These zones are now derived from selected BSP districts. They are not fixed
screen-space rectangles.

Each BSP leaf is normalized into a district candidate with a stable district id
and neighbor ids. The planner chooses a district near the center for the plaza,
then assigns other BSP districts to farm, training yard, gate, and building
roles by score. The resulting `town_zones` record the interpreted role of the
selected BSP districts.

## Selective Parcel Use

Phase 59 treats BSP subdivision as a source of district candidates, not a
command to use every leaf.

The planner reserves BSP districts for core functions first:

- plaza;
- farm;
- training yard;
- gate.

Buildings then choose from the remaining BSP districts using request scoring:

- homes prefer quiet outer lots and cluster with other homes;
- shops and taverns prefer plaza frontage;
- workshops prefer reachable road lots;
- farm-related buildings prefer farm adjacency;
- guard buildings prefer the gate edge.

Unused BSP districts remain available as grass, approach space, or future
natural presentation. They are not automatically filled with buildings.

Each concrete parcel now records `semantic_zone_id`, and generator validation
ensures every parcel points back to a known town zone.

## Road Generation

The fixed cross-shaped main street from the first v59 attempt was removed. It
made the map read like a coordinate axis rather than a village.

The current road generation connects the plaza to selected BSP-assigned
destinations:

- building doors;
- farm access;
- training yard;
- gate and exits.

This still needs later visual refinement, but it no longer carves full-width
horizontal and vertical spines through the entire map.

## Contract Rules

- Fixed semantic rectangles are not used.
- BSP leaves are normalized into district candidates with neighbor data.
- Core town roles are assigned to selected BSP districts.
- Buildings choose from remaining BSP district candidates by score.
- Parcels must record a valid `semantic_zone_id`.
- The farm remains a continuous functional block rather than road-cut filler.
- F3 debug presentation can show parcel bounds without making them part of the
  normal gameplay view.
- NPC schedules and building identity remain instance-based and are not
  resolved through zone names.

## Validation

Generator validation now checks:

- required town zones exist;
- parcels reference valid semantic zones;
- all previous v56-v58 pathing, prefab, door, and exterior slot contracts still
  hold.

The smoke test was updated with the same v59 semantic-zone assertions.

## Verification

- `git diff --check` passes.
- `tools/validation/validate_locations.ps1` passes.
- Godot 4.6.3 completes a headless main-scene startup with the generated
  village loaded and no generator contract errors.
