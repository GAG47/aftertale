# Phase 64: World Location Network

## Status

Complete as v64.

## Goal

v64 adds a world/location graph and a generic transition service. The goal is
not a world-map UI, regional map screen, road-network simulation, or another
wild terrain polish pass. The goal is to make Aftertale treat locations as
world nodes and exits as data-driven edges between those nodes.

The core model is:

```text
World
-> LocationSpec nodes
-> SpawnSpec entry points
-> ExitSpec / ConnectionSpec edges
-> runtime generated-location cache
-> generic transition service
```

`test_village` and `test_wild_plain` are v64 fixtures. The framework is not a
hard-coded two-scene loop; the graph can later attach interiors, generated
settlements, wilderness variants, dungeon placeholders, and special locations
through the same node/edge model.

## World Data

The test fixture lives at:

```text
data/worlds/test_world.json
```

It declares:

- `world_id`
- `world_seed`
- `start_location_id`
- `start_spawn_id`
- location specs
- spawn specs
- exit specs

The fixture uses existing location systems:

- `test_village` is a static scene entry backed by
  `res://scenes/locations/test_village.tscn` and
  `res://data/locations/test_village.json`.
- `test_wild_plain` is a `generated_wild` location backed by the existing
  wild terrain compiler, profile `plain`, seed `6201`, and size `64x64`.

The village exit is the existing generated exit id `wild_gate`. The wild return
edge is the existing generated exit id `return_to_village`. v64 maps those exit
ids through the world graph instead of teaching the movement code where they go.

## Runtime Flow

`WorldTransitionService` is the transition entry point:

```text
exit_id
-> WorldLocationGraph lookup
-> target LocationSpec
-> target SpawnSpec
-> WorldLocationRegistry materialization / runtime reuse
-> SceneLoader load
-> current_location_id update
```

For generated locations, `WorldLocationRegistry` materializes once and stores
the compiled location data in `WorldRuntimeState`. Later transitions reuse that
runtime data instead of asking the generator to roll again. The wild terrain
generator remains independent: it only receives seed/profile/size data and does
not know which location linked to it.

`SceneLoader` now supports one pending location-data override. The world service
uses this to hand already materialized data to `LocationRoot` during scene
instantiation. If no world is active, old `target_scene_path` transitions still
work as compatibility fallback.

## Save State

`SaveManager` now includes `WorldTransitionService.get_save_state()` in the save
payload. The world save state contains:

- the world resource/data;
- current world location id;
- generated location data and metadata;
- generation counts;
- recent transition summaries.

On load, the world runtime is restored before the scene is loaded so generated
locations can reuse saved data.

## Debug Summary

Each transition returns and stores a summary containing:

- `from_location_id`
- `exit_id`
- `target_location_id`
- `target_spawn_id`
- `target_location_source_type`
- `generated_or_loaded`
- `seed`
- `warnings`

Failures return explicit errors and also emit warnings through the service.

## Boundaries

v64 intentionally does not:

- add a world map UI;
- generate a procedural world graph;
- rewrite the village, wild terrain, interior, NPC, or save systems;
- make generated settlements fully enterable through the world graph;
- hide generation or transition failures.

`generated_settlement`, `interior`, `dungeon`, and `special` remain compatible
location kinds for future graph nodes, but v64 only fully wires
`generated_wild`.

## Validation

The phase was validated against:

- `test_world` loads and contains multiple location specs;
- `wild_gate` resolves to `test_wild_plain`;
- target spawn `west_entry` resolves to the existing `wild_spawn` entrance;
- generated wild terrain is created on first entry;
- the second entry reuses runtime data instead of generating again;
- current location id updates through both directions;
- invalid exit ids and invalid target spawn ids return clear failures.

Existing v62/v63 wild terrain tests and settlement generation smoke tests remain
responsible for their own generation contracts.
