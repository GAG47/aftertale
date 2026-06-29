# Phase 67 - Region Map World Context

v67 establishes a shared regional geography source for generated world nodes.

The problem before v67 was not visual edge stitching. The deeper problem was
that each generated location could choose its wild terrain profile
independently. Adjacent world nodes could therefore look like unrelated random
maps.

## Main Path

The world graph generation path is now:

```text
world_seed
-> RegionMap
-> region-positioned world nodes
-> region-derived generator profiles
-> region-metadata transition edges
-> generated_wild with RegionPatch context
```

`RegionMap` is saved inside generated `world_data`. It is not a debug-only
artifact.

## RegionMap

`RegionMapGenerator` creates a low-resolution regional geography map with:

- `elevation_map`
- `moisture_map`
- `water_map`
- `forest_map`
- `rock_map`
- `biome_map`
- `feature_map`

Supported region biomes are:

- `sea`
- `coast`
- `plain`
- `forest`
- `riverbank`
- `foothill`
- `rocky`

The biome layer is derived from the continuous numeric layers. It is not chosen
by independent random rolls per cell.

## World Nodes

Generated wild world nodes now record:

- `region_position`
- `region_biome`
- `region_cell`
- `region_patch`
- `generator_profile_id`

`generator_profile_id` is derived from `region_biome` through
`biome_profile_map`. Unsupported region biomes or missing generator profiles
fail explicitly. They do not fall back to `plain`.

Current default mapping:

```text
coast -> riverbank
plain -> plain
forest -> forest_edge
riverbank -> riverbank
foothill -> foothill
rocky -> foothill
sea -> unplaceable
```

## World Edges

World graph edges are now chosen from region positions instead of only node
indices. The connected base graph links nearby region nodes first, then adds
extra nearby edges according to the configured density.

Each edge records:

- `from_region_position`
- `to_region_position`
- `from_biome`
- `to_biome`
- `transition_kind`
- `region_distance`

This does not force adjacent maps to be identical. It makes the reason for the
adjacency explicit.

## RegionPatch Into Wild Terrain

`generated_wild` receives the node `RegionPatch` through the world registry and
passes it to `WildTerrainGenerator`.

The patch adjusts existing wild terrain profile parameters:

- coast and river influence increase water and wet terrain tendencies;
- forest influence increases vegetation and tree density;
- rock and high-elevation influence increase rocks, slopes, and ledges;
- moisture adjusts wetness and herb density.

This is an upstream context applied to the existing generator, not a rewrite of
wild terrain generation.

## Explicit Failure

v67 removes the silent profile fallback in `WildTerrainProfile.get_profile`.

These cases now fail explicitly:

- biome maps to a profile not listed by the world profile;
- biome maps to a profile unsupported by the wild terrain system;
- generated wild node has no region position;
- generated wild node has no region patch;
- generated edge has no region metadata;
- `WildTerrainGenerator` receives an unsupported terrain profile.

## Not Included

v67 does not implement:

- player-facing world map UI;
- seamless edge stitching between location maps;
- exact cross-location river alignment;
- cross-location roads;
- loading screen improvements;
- settlement generation from RegionMap;
- world transition rewrites.

Those are separate future phases.

## Validation

`scripts/tests/v67_region_map_world_graph_smoke.gd` verifies:

- same seed creates the same RegionMap;
- different seeds create different RegionMaps;
- numeric RegionMap layers are continuous;
- biome facts derive from numeric layers;
- world nodes have region position, biome, patch, and biome-derived profile;
- edges carry region and biome transition metadata;
- generated wild locations receive and apply RegionPatch;
- unsupported biome/profile mappings fail explicitly;
- unsupported wild terrain profiles fail explicitly.
