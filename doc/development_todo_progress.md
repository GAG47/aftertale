# Development Todo Progress

This document tracks the active settlement-generation roadmap only. Detailed
phase records remain in their own `doc/phase_*.md` files.

## Current Focus

Phase 60 completed the settlement-generation architecture reset with a corrected
boundary: the unified planning pipeline supersedes the old BSP village planner,
but the v56-v59 semantic map, concrete interior, door/anchor, NPC movement, and
offscreen schedule contracts remain active compiler targets.

The current focus has reached Phase 68: generated settlements now compile a
first-class semantic map and feed generated population planning from that map
before writing NPC assignments and schedule entries into the existing runtime
movement/offscreen schedule model.

## Scene Generation Roadmap

| Phase | Status | Development Log | Purpose |
| --- | --- | --- | --- |
| v60 | Complete | `doc/phase_60_settlement_generation_architecture.md` | Define the unified settlement-generation planning architecture while preserving the v56-v59 semantic map and NPC runtime contracts as the compiler target. |
| v61 | Complete | `doc/phase_61_decentralized_planning_core.md` | Implement decentralized iterative planning and expose the active blueprint, proposals, evaluator reports, and trace through a Godot-visible debug view. |
| v62 | Complete | `doc/phase_62_general_settlement_generation.md` | Implement step-based road growth, generic plot growth, plot differentiation, and building footprint generation through the shared blueprint pipeline. |
| v63 | Complete | `doc/phase_63_settlement_scene_compiler.md` | Compile settlement blueprints into normal Godot location data with visible roads, plots, buildings, collision, debug metadata, and seed reproduction. |
| v64 | Complete | `doc/phase_64_policy_playable_settlement_hooks.md` | Drive settlement variation through `SettlementPolicy` profiles, scale growth from map capacity and policy pressure, and compile generated buildings, per-door return entrances, concrete interior manifests, semantic slots, schedule targets, and facility hooks into the normal game location pipeline without generated NPCs or exterior shop counters. |
| v65 | Complete | `doc/phase_65_unified_interaction_resolver.md` | Unify current-cell and facing-cell interaction resolution through shared `InteractionCandidate` dictionaries for drops, beds, wall doors, return points, facilities, crops, terrain, and NPC talk. |
| v67 | Complete | `doc/phase_67_persistent_generated_settlement_population.md` | Persist generated settlement baselines and generate settlement residents, character definitions, spawn rows, role assignments, and schedule entries from generated building contracts and schedule targets. |
| v67.2 | Complete | `doc/phase_67_persistent_generated_settlement_population.md` | Bind generated settlement baselines to the active save/world context, restore generated indexes before scene load, and isolate generated `user://` definitions and caches across slots. |
| v67.3 | Complete | `doc/phase_67_persistent_generated_settlement_population.md` | Enforce generated NPC schedule, capacity, appearance, entry/exit, visible transition movement, and offscreen settlement integrity. |
| v68 | Complete | `doc/phase_68_semantic_map_npc_schedule_restoration.md` | Restore the v56-v59 semantic map and NPC schedule contract as the generated settlement compiler target, persist semantic maps in snapshots, and plan generated population from semantic map buildings and targets. |

## Dependency Order

```text
v60 settlement generation architecture
-> v61 decentralized planning core with Godot-visible debug output
-> v62 step-based road growth, generic plot growth, plot differentiation, and footprint generation
-> v63 settlement blueprint compiler into the normal Godot location pipeline
-> v64 policy-driven settlement variation with playable hooks
-> v65 unified interaction resolver
-> v67 persistent generated settlement population
-> v67.2 generated settlement persistence integrity
-> v67.3 generated NPC schedule and appearance integrity
-> v68 semantic map and NPC schedule restoration
```

## Active Boundaries

- Keep one settlement-generation pipeline for every settlement type.
- Do not revive the old BSP village planner or village-specific generator
  family as active architecture.
- Preserve the v56-v59 semantic map, concrete interior, door/anchor, NPC
  movement, and offscreen schedule contracts as generated settlement compiler
  targets.
- Do not introduce separate generator entry points for village, port, fortress,
  or city generation.
- Do not let agents mutate blueprints directly.
- Do not let the compiler repair invalid planning.
- Do not wait for a later phase to inspect generated output in game; Phase 63
  compiles the current blueprint output into a normal Godot location.
- Do not create separate settlement generators for policy types. Phase 64
  policy variation must continue through the shared `SettlementGenerationSession`
  and `TileSceneCompiler` path.
- Do not bypass the active save/world context when reading or writing generated
  settlement baselines.
- Do not assign generated residents before calculating concrete building
  capacity.
- Do not replace the v56-v59 schedule model with generated travel entries:
  visible NPCs move in the current location, non-current NPCs settle offscreen,
  and location entry resolves from schedule/offscreen state.
- Do not treat generated `building_contracts` or `schedule_targets` as the
  authoritative population source once `semantic_map` is available. They may
  remain serialized for compatibility and debugging, but generated population
  planning must read semantic map buildings and targets first.
