# Development Todo Progress

This document tracks planned work after Phase 49. It is an index, not the full design record; each phase keeps its detailed development log in its own `doc/phase_*.md` file.

## Current Focus

Phases 50 through 54 form the first complete battle-deepening slice. Phase 55
focuses on restructuring the full UI layer:

- pipeline-based skill effects and battle resources;
- temporary tile states and elemental reactions;
- tile effects on units;
- explainable enemy decision scoring;
- independent editable UI scenes instead of one monolithic root and runtime
  construction of fixed controls.

## Battle Deepening Roadmap

| Phase | Status | Development Log | Purpose |
| --- | --- | --- | --- |
| v50 | Complete | `doc/phase_50_skill_effect_data_model.md` | Add battle MP costs and route skill effects through a resolver pipeline. |
| v51 | Complete | `doc/phase_51_battle_tile_surface_states.md` | Add battle tile surface state storage, lifetime rules, triggers, and preview summaries. |
| v52 | Complete | `doc/phase_52_elemental_reactions.md` | Centralize fire, water, ice, and lightning reactions so skills apply elements instead of hard-coding reactions. |
| v53 | Complete | `doc/phase_53_status_effects_on_units.md` | Let tile states and reactions affect units at clear battle timing points. |
| v54 | Complete | `doc/phase_54_enemy_ai_scoring.md` | Replace the simple enemy priority chain with a debuggable action scoring model. |
| v55 | Complete | `doc/phase_55_ui_refinement.md` | Split battle, inventory, character, quest, facility, and menu UI into independent static scenes; variable-length items instantiate reusable component scenes. |

## Dependency Order

```text
v50 skill effect data model
-> v51 battle tile surface states
-> v52 elemental reactions
-> v53 status effects on units
-> v54 enemy AI scoring
-> v55 UI refinement and scene extraction
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
