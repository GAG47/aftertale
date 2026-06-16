# Phase 62: General Settlement Generation

## Status

Complete.

## Goal

Phase 62 turns the Phase 61 planning loop into a general settlement blueprint
generator for roads, plots, buildings, and landmarks.

This phase still does not compile a gameplay-ready Godot location. It proves
that the shared Phase 60 pipeline can produce a visible, inspectable,
deterministic settlement blueprint without hardcoding a single village layout.

## Implemented Scope

The generation session now runs these planning phases:

- core;
- road;
- plot;
- building;
- landmark;
- validation.

Each phase is handled through the same proposal pipeline:

```text
SettlementPolicy
-> SettlementContext
-> FeatureMapStore
-> SettlementAgent
-> PlanProposal
-> ProposalResolver
-> SettlementBlueprint
-> SettlementEvaluator
-> GenerationTrace
```

Agents still cannot mutate the blueprint directly. They only submit
`PlanProposal` objects. `ProposalResolver` remains the only commit entry point.

## Agents

Added the first general settlement agents:

- `RoadAgent`: proposes approach and branch roads from entrances, core state,
  map bounds, and deterministic session random decisions.
- `PlotAgent`: proposes road-accessible plots by reading committed roads,
  buildable cells, local reservations, and feature-map state.
- `BuildingAgent`: proposes building footprints inside accepted plots.
- `LandmarkAgent`: proposes a central landmark near the core and road network.
- `InvalidConflictAgent`: proposes an intentionally overlapping building
  footprint during validation.

The existing invalid out-of-bounds proposal remains active for resolver
validation coverage.

## Blueprint Model

`SettlementBlueprint` now commits the following general settlement proposal
types:

- `add_road`;
- `add_plot`;
- `add_building`;
- `add_landmark`.

The previous `add_path` type remains accepted as a compatibility alias, but
Phase 62 generation uses `add_road` for road proposals.

Committed blueprint entries store structured road paths, plot areas, building
footprints, building plot ownership, entrance cells, landmark cells, tags, and
proposal history.

## Resolver Rules

`ProposalResolver` now validates:

- supported proposal types;
- in-bounds cells;
- blocked context cells;
- buildable and unoccupied placement cells;
- non-empty roads;
- plot area size;
- plot road access;
- plot overlap;
- building plot ownership;
- building footprint inside the accepted plot;
- building entrance inside the footprint;
- landmark proximity to a road or core;
- conflicting occupied cells.

Invalid proposals are rejected before blueprint mutation. Accepted proposals
are committed through the resolver token only.

## Feature Maps

`FeatureMapStore` now updates after roads, plots, buildings, and landmarks:

- roads update road distance, accessibility, and nearby land value;
- plots update district pressure without occupying the cells;
- buildings occupy their footprint and increase local density pressure;
- landmarks occupy their cell, increase density pressure, and raise nearby
  land value.

The update count still matches the committed proposal count.

## Evaluator And Trace

`SettlementEvaluator` now reports counts for cores, roads, plots, buildings,
landmarks, anchors, and occupied cells.

It also detects missing roads, plots, buildings, landmarks, and inaccessible
plots as the session reaches later phases.

`GenerationTrace` continues to record proposals, accepts, rejects, commits,
evaluator reports, phase transitions, deterministic random decisions, and
session events.

## Godot Debug View

`SettlementDebugView` now renders visible blueprint layers:

- core markers;
- road cells;
- plot cells;
- building cells;
- landmark markers;
- rejected proposal cells;
- proposal, evaluator, and trace summaries.

The grid remains only as a debug background. Phase 62 visual inspection is now
based on the actual committed blueprint layers and rejected proposals.

## Validation

Added `scripts/tests/v62_general_settlement_generation_smoke.gd`.

The smoke test verifies:

- fixed-seed deterministic execution;
- core generation;
- general road generation;
- road-accessible plot generation;
- building generation inside accepted plots;
- landmark generation;
- invalid out-of-bounds proposal rejection;
- invalid overlapping building rejection;
- resolver-only commit authority;
- feature-map update count after commits;
- evaluator report count after commits;
- trace coverage for road, plot, building, and landmark proposals;
- Godot debug view rendering for roads, plots, buildings, core markers,
  landmark markers, and rejected proposal cells.

## Verification

- `v62_general_settlement_generation_smoke.gd` passes under Godot headless.
