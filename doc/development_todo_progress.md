# Development Todo Progress

This document tracks planned work after Phase 49. It is an index, not the full design record; each phase keeps its detailed development log in its own `doc/phase_*.md` file.

## Current Focus

Phases 50 through 54 form the first complete battle-deepening slice. Phase 55
restructured the full UI layer. Phases 56 through 62 move scene generation from
a usable skeleton toward presentable generated places:

- pipeline-based skill effects and battle resources;
- temporary tile states and elemental reactions;
- tile effects on units;
- explainable enemy decision scoring;
- independent editable UI scenes instead of one monolithic root and runtime
  construction of fixed controls;
- deterministic generated village scenes with semantic gameplay anchors;
- exterior building doors that transition to generated interior instances with
  concrete building identities;
- prefab-driven exterior presentation contracts for parcels, frontage, and
  placeholder building facades;
- data-driven building prefab catalogs with explicit non-blocking exterior
  slot materialization;
- semantic town zones that select and discard parcel candidates before building
  placement;
- open-auction settlement blueprint planning that commits road, plaza, parcel,
  farm, training, gate, building bid, and decoration proposals before compiling
  the existing v59 runtime location contract, with the default v60.3 path
  rejecting compiler road recovery instead of hiding missing planner output.
- cell-set parcels that can be irregular, while south-facing building cores are
  fitted inside those parcel cells and yards/paths adapt to the final parcel
  shape instead of forcing every old prefab exterior slot to materialize.
- independent wild terrain generation driven by natural layers, sampled natural
  objects, and runtime spawn/exit candidate selection without settlement
  coupling.
- semantic wild elevation that turns generated height into lowland, highland,
  slope, and ridge facts affecting terrain, movement cost, resources, and
  presentation without true multi-level pathfinding.
- continuous wild landform semantics that keep lowland, wetland, woodland,
  open meadow, upland, hillside, and rocky ridge areas readable as connected
  terrain instead of random tile noise.
- a world/location network that treats locations as graph nodes and exits as
  data-driven edges, with generated wild locations materialized on demand and
  reused from runtime/save metadata.
- interior child locations that hang off parent exterior locations in the world
  graph, with doors represented as world transition edges instead of separate
  scene-path door logic.

## Battle Deepening Roadmap

| Phase | Status | Development Log | Purpose |
| --- | --- | --- | --- |
| v50 | Complete | `doc/phase_50_skill_effect_data_model.md` | Add battle MP costs and route skill effects through a resolver pipeline. |
| v51 | Complete | `doc/phase_51_battle_tile_surface_states.md` | Add battle tile surface state storage, lifetime rules, triggers, and preview summaries. |
| v52 | Complete | `doc/phase_52_elemental_reactions.md` | Centralize fire, water, ice, and lightning reactions so skills apply elements instead of hard-coding reactions. |
| v53 | Complete | `doc/phase_53_status_effects_on_units.md` | Let tile states and reactions affect units at clear battle timing points. |
| v54 | Complete | `doc/phase_54_enemy_ai_scoring.md` | Replace the simple enemy priority chain with a debuggable action scoring model. |
| v55 | Complete | `doc/phase_55_ui_refinement.md` | Split battle, inventory, character, quest, facility, and menu UI into independent static scenes; variable-length items instantiate reusable component scenes. |
| v56 | Complete | `doc/phase_56_scene_generation.md` | Replace the hand-authored test village with a BSP-generated village whose gameplay points are resolved through generated semantic anchors. |
| v57 | Complete | `doc/phase_57_exterior_doors_and_interiors.md` | Stop exposing building interiors in the exterior village; enter buildings through interactive doors, then place exterior buildings through parcel contracts and placeholder prefab contracts. |
| v58 | Complete | `doc/phase_58_prefab_exterior_presentation.md` | Move building prefabs into data, render parcel/frontage/foundation presentation layers, and materialize only prefab-declared exterior slots without global random decoration. |
| v59 | Complete | `doc/phase_59_semantic_town_layout.md` | Interpret BSP leaves as district candidates, assign town roles from that graph, select building parcels by score, and expose F3 parcel debug presentation. |
| v60 | Complete | `doc/phase_60_agent_settlement_blueprint_planner.md` | Replace the BSP-led village layout authority with an open-auction agent blueprint planner while preserving v59 parcels, prefabs, doors, interiors, anchors, and NPC schedule targets; v60.3 removes default compiler recovery, supports multi-side parcel access, and records planner-declared required goals. |
| v61 | Complete | `doc/phase_61_adaptive_parcel_building_cores.md` | Replace rectangular prefab-lot assumptions with organically grown cell-set parcels, protect required settlement goals with priority-filtered auction arbitration, fit only south-facing building cores inside parcel cells, and report adaptation failures instead of hiding them. |
| v62 | Complete | `doc/phase_62_wild_terrain_generation.md` | Add an independent natural-layer-driven wild terrain generator that emits reusable blueprint maps, water/wetland biomes, sampled natural objects, spawn and exit candidates, and a generated runtime wild location without settlement coupling or required semantic object patches. |
| v63 | Complete | `doc/phase_63_semantic_elevation.md` | Promote wild height maps into semantic lowland, highland, slope, ridge, and v63.2 landform layers that influence terrain, movement cost, resource placement, runtime presentation, and F3 debug summaries without introducing true multi-level terrain. |
| v64 | Complete | `doc/phase_64_world_location_network.md` | Add a data-driven world/location graph, spawn and exit specs, runtime generated-location registry, generic transition service, and test world connecting the village to an on-demand generated wild location without hard-coding a two-scene loop. |
| v64.1 | Complete | `doc/phase_64_1_interior_world_nodes.md` | Add enterable interiors as child world location nodes, door enter/leave edges, parent/child graph queries, and generated building-interior registry support driven by generated manifests without promoting furniture or anchors to world nodes. |
| v65 | Complete | `doc/phase_65_world_graph_generator.md` | Add a seed-driven local world graph generator with region profiles, generated location node specs, spawn points, paired transition edges, graph compilation, debug summaries, and generated-wild materialization through the existing world transition service. |

## Dependency Order

```text
v50 skill effect data model
-> v51 battle tile surface states
-> v52 elemental reactions
-> v53 status effects on units
-> v54 enemy AI scoring
-> v55 UI refinement and scene extraction
-> v56 BSP scene generation and semantic anchors
-> v57 exterior doors and generated interiors
-> v58 prefab exterior presentation and slot materialization
-> v59 semantic town layout
-> v60 agent settlement blueprint planning
-> v61 adaptive parcel building cores
-> v62 wild terrain generation
-> v63 semantic wild elevation and continuous landforms
-> v64 world location network and generic transitions
-> v64.1 interior child nodes and door transition edges
-> v65 local world graph generation
```

## Minimum Tactical Slice

The first complete slice should prove only four elements and four test skills:

- Fire: deals damage and ignites target cells.
- Water: extinguishes burning cells and creates wet cells.
- Ice: freezes wet cells and can freeze units standing on them.
- Lightning: spreads through wet or conductive cells.

Test skills:

- Firebolt
- Water Shot
- Frost Needle
- Spark

## Boundaries

- Do not introduce black-box AI for battle decisions.
- Do not let UI or presentation nodes mutate battle facts directly.
- Do not make elemental reactions private to individual skill scripts.
- Do not require world persistence for every battle tile state in the first pass.
- Keep player-facing rules readable before adding more elements, probabilities, or special cases.
