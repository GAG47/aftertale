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
- `data/locations/generated_settlement_v62_48x32.json`;
- `scenes/locations/generated_settlement.tscn`.

The main game start now loads `generated_settlement.tscn` at
`main_entrance`, so the settlement blueprint output is visible in the normal
game scene instead of only in the debug tool scene.

At the end of Phase 63, `generated_settlement.json` was still a compact
gameplay integration sample, while `generated_settlement_v62_48x32.json` was a
separate 48x32 quality-observation sample for judging Phase 62 growth behavior
without the pressure of the small gameplay test map. Phase 64 later upgrades
`generated_settlement.json` to a policy-driven 48x32 gameplay sample.

## Rendered Layers

The compiled location maps blueprint layers into existing Godot presentation
data:

- roads become path tiles;
- plots become plot tiles and zones;
- cores become plaza tiles and anchors;
- buildings become building floor tiles, foundations, structure-layer wall
  rings, non-blocking visual door cells, and collision overrides;
- optional landmarks become visible structures when present in the blueprint;
- debug overlays retain blueprint source ids and proposal-derived metadata;
- seed, proposal counts, rejected counts, and committed counts are stored in
  location state and generation summary;
- plot access cells, building front-access cells, and road graph connectivity
  diagnostics are stored in `generation_summary`.

## Collision And Navigation Surface

Building footprints generate `collision_overrides` so `LocationGrid` treats
them as movement and sight blockers.

Generated settlement buildings do not compile ordinary exterior presentation
into `roofs`. Since generated interiors are separate scenes, the normal
generated settlement view leaves the roof layer empty for ordinary buildings
and presents building fronts through `structures`.

Roads, plots, entrance cells, and core tiles remain walkable. The player is
spawned through the normal entrance system.

Compiler validation rebuilds the road graph from compiled tile data. The
compiled entrance must touch the main road component, that component must
reach the settlement core, plot access cells must belong to it, and building
front-access cells must belong to it. The compiler reports disconnected road
cells instead of silently accepting a visually broken road network.

The compiler also compares compiled road tiles against the blueprint road-cell
count. Roads are painted after plot, public, and core ground layers so road
tiles keep presentation priority. If a later compiled layer removes road
tiles or splits the road graph, validation fails. The compiler does not repair
invalid blueprint output.

## Validation

Added `scripts/tests/v63_settlement_scene_compiler_smoke.gd`.

The smoke test verifies:

- deterministic compiled output for a fixed seed;
- valid `LocationGrid` output;
- preserved road, plot, and building counts;
- no ordinary generated buildings in the roof layer;
- visible generated building wall structures;
- visual generated building door cells on the structure layer;
- building collision overrides;
- debug overlays with blueprint source ids;
- player spawn data;
- road graph connectivity from entrance to core;
- plot and building access on the main road component;
- `compiled_road_connected`;
- `compiled_entrance_connected`;
- `compiled_core_connected`;
- `compiled_plot_access_connected`;
- `compiled_building_front_connected`;
- successful compilation of the 48x32 quality-observation sample;
- successful instantiation of `generated_settlement.tscn`;
- initialized `LocationRoot` grid and scene summary.

## Verification

- Godot editor class registration passes.
- Runtime headless smoke execution is currently blocked by a Godot runtime
  access violation in this environment before the smoke script can report a
  normal GDScript result.
