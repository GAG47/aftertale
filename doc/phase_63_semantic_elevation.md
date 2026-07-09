# Phase 63: Semantic Elevation

## Status

Complete as v63.2.

## Goal

Phase 63 promotes the v62 `height_map` from a hidden natural input into explicit
semantic elevation data. It does not add true multi-level terrain, bridges over
underpasses, height-based line of sight, climbing, jumping, or tactical height
advantage. The goal is to make wild terrain know and show low ground, higher
ground, slopes, and ridges while keeping the current `LocationGrid` contract.

The core flow is:

```text
height_map
-> elevation_map + slope_map + ridge_map
-> landform_map
-> tile and walk-cost adjustment
-> elevation-aware natural object sampling
-> elevation overlays and ridge/slope decorations
-> debug summary and F3 visualization
```

## Blueprint Contract

`WildTerrainBlueprint` now exposes four v63 layers:

- `elevation_map`: semantic ids such as `lowland`, `midland`, `highland`,
  `slope`, and `ridge`;
- `slope_map`: local height delta strength;
- `ridge_map`: local crest or ridge tendency;
- `landform_map`: v63.2 contiguous terrain semantics such as `wetland`,
  `lowland`, `woodland`, `open_meadow`, `upland`, `hillside`,
  `rocky_slope`, and `rocky_ridge`.

These layers are serialized through `wild_terrain_blueprint`, included in the
generator metadata, and validated by the terrain smoke tests.

## Gameplay Semantics

Elevation affects generated terrain without introducing true vertical levels:

- lowland cells are wetter and can become lowland meadow or wet grass;
- highland cells are drier and can become dry highland or highland meadow;
- slope cells add movement cost and mark hillside biomes without forcing grass
  into dirt presentation;
- ridge cells lean toward stone, rocky ground, and sparse ridge meadow;
- a small number of steep rocky cells can become blocking rock ledges;
- spawn and exit selection avoid high slope and ridge cost when possible.

Natural objects now read elevation source layers:

- herbs prefer moist low ground and avoid ridges;
- large rocks and ore veins score higher on slopes, high ground, and ridges;
- trees avoid steep slopes and ridges;
- berries and branches are lightly penalized on rougher high terrain.

## Runtime Presentation

The wild compiler emits game-layer elevation overlays for non-water generated
terrain:

- `elevation_lowland`
- `elevation_highland`
- `elevation_slope`
- `elevation_ridge`

Overlays include `height`, `slope`, `ridge`, and `drop_edges`. The renderer uses
these facts to tint lowland and highland cells, draw slope hatching, draw darker
drop edges, and add a sparse scree decoration on slopes and ridges.

F3 debug presentation colors lowland, highland, slope, and ridge cells and shows
the v63 ratios in the terrain summary.

## v63.1 Presentation Tuning

The first v63 presentation made slope and highland areas read too much like
roads, wooden planks, or artificial paved patches. v63.1 keeps the same semantic
elevation data and walk-cost behavior, but tunes the runtime drawing so natural
terrain remains dominant:

- highland and lowland overlays use very light temperature tints;
- slope overlays emphasize drop edges instead of filling whole cells;
- ridge overlays use sparse crest marks and lighter edge shadows;
- dirt tile drawing uses subtle dry-soil scratches instead of strong horizontal
  board-like lines;
- elevation no longer mass-converts grass into dirt just to express dry high
  ground or hillside movement cost.

F3 debug overlay remains the stronger diagnostic view for reading exact
elevation classifications.

## v63.2 Continuous Landform Tuning

v63.2 keeps the project on semantic elevation rather than true multi-level
terrain. The goal is visual readability: a player should be able to tell that a
continuous area is low, wet, wooded, open, higher, sloped, or rocky without
needing tactical height rules.

The generator now derives `landform_map` after elevation classification and
before tile selection. This layer converges the natural maps into larger
terrain meanings:

- water and nearby water become water, wetland, and lowland bands;
- midland vegetation can become woodland or open meadow patches;
- highland, slope, and ridge cells become upland, hillside, rocky upland,
  rocky slope, upland ridge, or rocky ridge areas.

Tile selection now has dedicated semantic ground tiles:

- `lowland_grass` uses cooler, darker grass presentation;
- `highland_grass` uses a warmer raised-grass tint and contour marks;
- `slope_grass` uses diagonal slope bands and stronger lift/drop cues.

This avoids using random dirt patches as a substitute for height. Dirt remains
available for dry ground, but high ground is expressed primarily through
contiguous highland/slope/ridge semantics, color temperature, and edge marks.

Natural object sampling also reads `landform_map`. Trees score strongly inside
woodland and lower in open or upland areas, rocks and ore favor rocky uplands
and ridges, and herbs favor lowland or wetland. This makes resources explain
the terrain instead of floating as a separate random layer.

The F3 wild debug overlay now colors landform semantics and reports lowland,
wetland, woodland, open-ground, and upland ratios. This makes it possible to
separate generator problems from renderer problems when a wild scene looks
wrong.

## Validation

The phase was validated against:

- elevation, slope, ridge, and landform maps exist and match blueprint
  dimensions;
- debug summaries include elevation and landform counts and ratios;
- lowland, elevated terrain, slope, and ridge coverage are non-zero for the
  default generated plain;
- v63.2 semantic ground tiles are generated;
- lowland/wetland, upland, and woodland landform groups form non-trivial
  connected components instead of only isolated noise cells;
- slope average walk cost exceeds flat average walk cost;
- natural object source layers include elevation, slope, ridge, and landform
  facts;
- compiled runtime locations emit elevation overlays with drop-edge and
  landform metadata;
- the compiled blueprint exposes `elevation_map` and `landform_map`.

The existing v62 smoke test remains focused on deterministic wild generation,
water and wetland coverage, profile variation, and LocationGrid compatibility.
