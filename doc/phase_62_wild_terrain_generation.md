# Phase 62: Wild Terrain Generation

## Status

Complete as v62.

## Goal

Phase 62 adds an independent tile-based wild terrain generator for local outdoor
locations. It is not a world map generator and it is not a settlement foundation
planner. The generator produces natural facts first, then derives runtime tiles,
blockers, walk costs, natural objects, spawn candidates, exit candidates, and a
debug summary from those layers.

The core flow is:

```text
seed + size + terrain profile
-> layered natural maps
-> biome and tile derivation
-> blue-noise natural object sampling
-> spawn and exit candidate selection
-> current LocationGrid-compatible runtime data
```

## Files

The v62 module lives under `scripts/systems/terrain/`:

- `wild_terrain_profile.gd`
- `wild_terrain_blueprint.gd`
- `wild_terrain_generator.gd`
- `wild_location_compiler.gd`

`DefinitionLoader` now recognizes location definitions whose generator type is
`wild_terrain`.

## Profiles

The first supported profiles are:

- `plain`
- `forest_edge`
- `riverbank`
- `foothill`

Profiles are natural parameter sets. They describe tendencies such as height
variation, moisture, vegetation density, rock density, water level, and natural
object density. They are not required-object lists and do not require camps,
herbs, ore, bridges, roads, or village-facing content.

## Natural Water And Wetlands

The v62 presentation pass makes water and wetland terrain part of the natural
layer model instead of a hand-placed feature. Water can now come from low
terrain, pond pockets, drainage seams, or the stronger riverband used by the
`riverbank` profile. Adjacent moist cells derive marsh and wet-meadow biomes so
water edges read as gradual wetlands instead of hard grass-to-water cuts.

Road/path generation is intentionally not part of this pass. Wild locations may
later opt into trails, but plain wild terrain does not require a road layer.

## Blueprint Contract

`WildTerrainBlueprint` exposes:

- `width`
- `height`
- `seed`
- `terrain_profile_id`
- `height_map`
- `moisture_map`
- `roughness_map`
- `vegetation_map`
- `rock_map`
- `water_map`
- `biome_map`
- `tile_map`
- `blocker_map`
- `walk_cost_map`
- `natural_objects`
- `object_candidates`
- `spawn_candidates`
- `exit_candidates`
- `debug_summary`

The generator owns only natural terrain facts and runtime candidate selection.
Downstream settlement systems may read these layers later, but they should not
feed settlement demands back into wild terrain generation.

## Runtime Integration

`data/locations/test_wild_plain.json` is a compact generated location
definition. `scenes/locations/test_wild_plain.tscn` reuses `LocationRoot`,
`DebugTileRenderer`, and the existing layer renderer nodes.

The generated runtime location includes:

- grass, dirt, wet grass, mud, forest floor, stone, rocky ground, shallow water,
  deep water, and exit terrain definitions;
- tree, large rock, and ore vein blockers as structures;
- naturally sampled herb, berry, and fallen branch pickups when the layer
  conditions and sampling allow them;
- a `wild_spawn` entrance chosen from passable generated terrain;
- runtime exits chosen from passable generated terrain using optional exit
  hints.

The village wild gate now targets:

```text
res://scenes/locations/test_wild_plain.tscn / wild_spawn
```

The wild location exit returns to the generated village entrance `from_wild`.
This is only a debug/runtime connection. The terrain generator does not shape
the map around the village.

F3 debug presentation now includes a wild terrain overlay when a generated
blueprint is present. The overlay colors water, wet ground, vegetation, rock,
high ground, and blockers, and the debug panel shows seed/profile plus
passable, water, wetland, forest, and rock ratios.

## Seed And Persistence

The default seed is stored in:

```json
"generator": {
  "type": "wild_terrain",
  "seed": 6201,
  "size": { "width": 64, "height": 64 },
  "terrain_profile_id": "plain"
}
```

Changing `seed`, `terrain_profile_id`, or `size` changes the generated result.
The same seed, profile, and size produce the same blueprint. The generated
location records seed, profile, and size in `state` and includes the full
`wild_terrain_blueprint` dictionary for inspection.

There is not yet a saved generated-location snapshot store. A later save-system
integration can persist the blueprint dictionary keyed by location id plus
seed/profile/size and load it before regenerating.

## Validation

`scripts/tests/v62_wild_terrain_smoke.gd` verifies:

- same seed/profile/size determinism;
- different seed variation;
- layer map existence and dimensions;
- tile/blocker/walk-cost dimension agreement;
- passable ratio in the smoke range;
- generated summary tile, biome, water, and wetland fields;
- riverbank profile water and wetland coverage;
- forest-edge and foothill profiles change the terrain fingerprint;
- spawn candidates are passable;
- configured exit hints resolve to passable exit candidates;
- the compiled runtime location loads as a valid `LocationGrid`;
- the compiled location exposes the blueprint.

The smoke test does not require any specific herb, ore, camp, bridge, road, or
river to exist.
