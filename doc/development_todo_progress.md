# Development Todo Progress

This document tracks the active settlement-generation roadmap only. Detailed
phase records remain in their own `doc/phase_*.md` files.

## Current Focus

Phase 60 completed the settlement-generation architecture reset. The active
scene-generation line now starts from the new settlement architecture only.

The current focus has reached Phase 65: settlement gameplay now uses a unified
interaction resolver while keeping the shared blueprint and compiler pipeline.

## Scene Generation Roadmap

| Phase | Status | Development Log | Purpose |
| --- | --- | --- | --- |
| v60 | Complete | `doc/phase_60_settlement_generation_architecture.md` | Define the unified settlement-generation architecture: policy, context, session, feature maps, agents, proposals, resolver, blueprint, evaluator, trace, and compiler. |
| v61 | Complete | `doc/phase_61_decentralized_planning_core.md` | Implement decentralized iterative planning and expose the active blueprint, proposals, evaluator reports, and trace through a Godot-visible debug view. |
| v62 | Complete | `doc/phase_62_general_settlement_generation.md` | Implement step-based road growth, generic plot growth, plot differentiation, and building footprint generation through the shared blueprint pipeline. |
| v63 | Complete | `doc/phase_63_settlement_scene_compiler.md` | Compile settlement blueprints into normal Godot location data with visible roads, plots, buildings, collision, debug metadata, and seed reproduction. |
| v64 | Complete | `doc/phase_64_policy_playable_settlement_hooks.md` | Drive settlement variation through `SettlementPolicy` profiles, scale growth from map capacity and policy pressure, and compile generated buildings, per-door return entrances, concrete interior manifests, semantic slots, schedule targets, and facility hooks into the normal game location pipeline without generated NPCs or exterior shop counters. |
| v65 | Complete | `doc/phase_65_unified_interaction_resolver.md` | Unify current-cell and facing-cell interaction resolution through shared `InteractionCandidate` dictionaries for drops, beds, wall doors, return points, facilities, crops, terrain, and NPC talk. |

## Dependency Order

```text
v60 settlement generation architecture
-> v61 decentralized planning core with Godot-visible debug output
-> v62 step-based road growth, generic plot growth, plot differentiation, and footprint generation
-> v63 settlement blueprint compiler into the normal Godot location pipeline
-> v64 policy-driven settlement variation with playable hooks
-> v65 unified interaction resolver
```

## Active Boundaries

- Keep one settlement-generation pipeline for every settlement type.
- Do not revive removed scene-generation approaches as active architecture.
- Do not introduce separate generator entry points for village, port, fortress,
  or city generation.
- Do not let agents mutate blueprints directly.
- Do not let the compiler repair invalid planning.
- Do not wait for a later phase to inspect generated output in game; Phase 63
  compiles the current blueprint output into a normal Godot location.
- Do not create separate settlement generators for policy types. Phase 64
  policy variation must continue through the shared `SettlementGenerationSession`
  and `TileSceneCompiler` path.
