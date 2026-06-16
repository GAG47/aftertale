# Phase 63: Settlement Scene Compiler

## Status

Complete.

## Goal

Phase 63 moves the settlement-generation output from the debug blueprint view
into the normal Godot location pipeline.

This phase compiles a Phase 62 `SettlementBlueprint` into gameplay-visible
location data that `LocationRoot`, `LocationGrid`, `DebugTileRenderer`, and the
existing scene layer renderers can load.

Phase 63 does not implement multiple settlement types. That decision is left
for a later phase.

## Compiler

Added `TileSceneCompiler` under `scripts/systems/settlements/`.

The compiler runs the settlement session from a `settlement_blueprint`
location generator definition and compiles the session result into normal
location data:

- `tiles`;
- `terrain`;
- `zones`;
- `town_zones`;
- `floor_overlays`;
- `structures`;
- `roofs`;
- `entrances`;
- `anchors`;
- `characters`;
- `collision_overrides`;
- `state`;
- `generation_summary`.

The compiler does not repair invalid planning. It consumes the accepted
blueprint output from the resolver pipeline.

## Location Integration

`DefinitionLoader` now supports the `settlement_blueprint` generator type.

Added:

- `data/locations/generated_settlement.json`;
- `scenes/locations/generated_settlement.tscn`.

The main game start now loads `generated_settlement.tscn` at
`main_entrance`, so the settlement blueprint output is visible in the normal
game scene instead of only in the debug tool scene.

## Rendered Layers

The compiled location maps blueprint layers into existing Godot presentation
data:

- roads become path tiles;
- plots become plot tiles and zones;
- cores become plaza tiles and anchors;
- buildings become building floor tiles, foundations, roofs, and collision
  overrides;
- optional landmarks become visible structures when present in the blueprint;
- debug overlays retain blueprint source ids and proposal-derived metadata;
- seed, proposal counts, rejected counts, and committed counts are stored in
  location state and generation summary.

## Collision And Navigation Surface

Building footprints generate `collision_overrides` so `LocationGrid` treats
them as movement and sight blockers.

Roads, plots, entrance cells, and core tiles remain walkable. The player is
spawned through the normal entrance system.

## Validation

Added `scripts/tests/v63_settlement_scene_compiler_smoke.gd`.

The smoke test verifies:

- deterministic compiled output for a fixed seed;
- valid `LocationGrid` output;
- preserved road, plot, and building counts;
- visible building roofs;
- building collision overrides;
- debug overlays with blueprint source ids;
- player spawn data;
- successful instantiation of `generated_settlement.tscn`;
- initialized `LocationRoot` grid and scene summary.

## Verification

- `v63_settlement_scene_compiler_smoke.gd` passes under Godot headless.
