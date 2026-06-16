# Phase 62: Step-Based Settlement Growth

## Status

Complete.

## Goal

Phase 62 replaces the earlier staged generator with step-based blueprint
growth.

The goal is not to generate a finished village in one pass. The goal is to
prove that a settlement can grow through repeated proposal steps while keeping
the Phase 60 ownership boundaries intact:

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

This version implements road growth, generic plot growth, plot
differentiation, and building footprint generation. It does not implement an
economy system, multiple settlement types, formal art output, or full landmark
behavior.

Full landmark behavior is deferred. Phase 62 may keep only core or public
anchors needed for debugging and feature-map pressure. It must not add a fixed
well, shrine, notice board, or other landmark just to fill a layer count.

## Step Loop

`SettlementGenerationSession` now advances by `current_step`.

Each step:

- records a generation step in `GenerationTrace`;
- activates agents by `AgentSpec.activation_step`;
- applies `AgentSpec.activation_interval`;
- stops an agent after `AgentSpec.max_commits`;
- collects proposals from active agents;
- sends all proposals to `ProposalResolver`;
- lets the resolver arbitrate conflicts and commit winners;
- rebuilds feature maps after each committed proposal;
- runs `SettlementEvaluator` after each committed proposal.

There is no road step, plot step, building step, or landmark step. Agents may
be active on the same generation step, and the resolver decides which proposals
survive.

## Proposal Semantics

`PlanProposal` uses:

- `step: int`;
- `stage: String`;
- `type: String`.

`stage` is a proposal category label only. It does not define execution order.

Allowed Phase 62 `stage` values:

- `blueprint_growth`;
- `differentiation`;
- `footprint`.

Allowed Phase 62 proposal types:

- `add_core_seed`;
- `add_road_segment`;
- `add_generic_plot`;
- `differentiate_plot`;
- `add_building_footprint`.

Old proposal aliases from earlier staged implementations are not accepted by
the Phase 62 resolver or blueprint commit path.

## Agent Spec

`SettlementAgentSpec` is intentionally small in Phase 62.

It has only:

- `activation_step`;
- `activation_interval`;
- `max_commits`.

Scoring details remain inside the agents for now. Broad agent-parameter
configuration is deferred.

## Agents

Phase 62 uses these active agents:

- `CoreSeedAgent`: chooses an initial core seed and a short road seed from
  feature-map fitness.
- `RoadExpandAgent`: grows short road segments from road endpoints.
- `RoadBranchAgent`: grows branch roads from the existing road network.
- `GenericPlotAgent`: grows road-connected generic building plots.
- `PlotDifferentiationAgent`: scores generic plots and assigns one use:
  residential, commercial, production, or public.
- `BuildingFootprintAgent`: chooses a footprint inside a differentiated plot
  while preserving entrance space.
- `InvalidProposalAgent`: submits an out-of-bounds proposal for rejection
  coverage.
- `InvalidConflictAgent`: submits a conflicting footprint for resolver
  coverage.

There are no separate residential, commercial, production, or public generator
classes in Phase 62. Plot use is selected by `PlotDifferentiationAgent`.

## Generic Plot Differentiation

Plots are not created directly as houses.

The growth chain is:

```text
generic plot
-> differentiated plot use
-> building footprint
```

The current differentiation scores are intentionally simple:

- residential prefers local land value and lower nearby density;
- commercial prefers road junction pressure;
- production prefers edge and entrance pressure;
- public is limited and prefers central or junction pressure.

There is no economy simulation in Phase 62.

## Resolver

`ProposalResolver` is the only commit entry point.

For each generation step it:

- records every submitted proposal;
- rejects unsupported stages or proposal types;
- checks proposal step compliance;
- checks bounds, context blockers, buildability, plot access, and footprint
  ownership;
- groups conflicts by affected cells and explicit conflict keys;
- sorts valid proposals by score and priority;
- selects winners;
- rejects conflict losers into `GenerationTrace`;
- commits winners through `SettlementBlueprint.COMMIT_TOKEN`;
- rebuilds feature maps after each commit;
- runs evaluator reports after each commit.

Agents never mutate `SettlementBlueprint`, `FeatureMapStore`, or compiled scene
data directly.

## Feature Maps

`FeatureMapStore` remains derived state.

It rebuilds from context and the committed blueprint after every committed
proposal. Phase 62 uses:

- buildable;
- occupied;
- road;
- plot;
- reserved;
- terrain cost;
- water;
- obstacle;
- accessibility;
- road distance;
- entrance distance;
- edge distance;
- center distance;
- density pressure;
- district pressure;
- land value.

The land-value map is deliberately simple: core pressure, road pressure, public
pressure, and obstacle penalties. More detailed land value simulation is
deferred.

## Evaluator And Trace

`SettlementEvaluator` reports after each committed proposal.

Reports include:

- step;
- committed proposal id;
- score;
- issues;
- feedback flags;
- core count;
- road count;
- generic plot count;
- differentiated plot count;
- building footprint count;
- occupied count.

`GenerationTrace` records:

- submitted proposals;
- accepted proposals;
- rejected proposals;
- committed proposals;
- evaluator reports;
- generation step transitions;
- step resolutions;
- deterministic random decisions;
- session events.

Blueprint history remains separate and stores only committed semantic events.

## Godot Debug View

`SettlementDebugView` now has to prove process, not only final state.

It renders:

- blueprint summary;
- layer summary;
- proposal summary;
- evaluator summary;
- trace summary;
- feature-map grid;
- committed roads;
- generic and differentiated plots;
- building footprints;
- core markers;
- rejected proposal cells;
- a step log showing accepted and rejected proposal events.

Example process rows:

```text
step 03: road segment accepted
step 06: generic plot accepted
step 09: plot -> commercial accepted
step 12: building footprint accepted
```

## Validation

Updated `scripts/tests/v62_general_settlement_generation_smoke.gd`.

The smoke test verifies:

- fixed-seed deterministic execution;
- core generation;
- road growth;
- road-accessible generic plot growth;
- plot differentiation;
- building footprint generation inside differentiated plots;
- invalid out-of-bounds proposal rejection;
- invalid conflicting footprint rejection;
- resolver-only commit authority;
- feature-map update count after commits;
- evaluator report count after commits;
- trace coverage for generation steps and all Phase 62 proposal types;
- Godot debug view rendering for roads, plots, buildings, core markers,
  rejected proposal cells, and step process logs.

## Verification

- Godot editor class registration passes.
- Runtime headless smoke execution is currently blocked by a Godot runtime
  access violation in this environment before the smoke script can report a
  normal GDScript result.
