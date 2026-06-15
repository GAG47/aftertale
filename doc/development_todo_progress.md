# Development Todo Progress

This document tracks planned work after Phase 49. It is an index, not the full design record; each phase keeps its detailed development log in its own `doc/phase_*.md` file.

## Current Focus

Phases 50 through 54 form the first complete battle-deepening slice. Phase 55
restructured the full UI layer. Phases 56 through 60 move scene generation from
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
- road-first settlement generation that scans street frontage before placing
  parcels and buildings.

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
| v60 | Complete | `doc/phase_60_road_first_settlement_generation.md` | Replace the BSP-led village layout core with a road-first skeleton, frontage lot allocation, and street-facing prefab placement. |

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
-> v60 road-first settlement generation
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
