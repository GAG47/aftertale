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
- may commit multiple non-conflicting winners in the same generation step;
- rebuilds feature maps after each committed proposal;
- runs `SettlementEvaluator` after each committed proposal.

There is no road step, plot step, building step, or landmark step. Agents may
be active on the same generation step. The resolver enforces per-family and
per-spatial conflict capacity instead of a global one-winner queue. Road, plot,
differentiation, footprint, and public-space proposals can all commit in the
same step if they do not exceed their family capacity and do not claim the same
space. Losing candidates are recorded with reason, score, conflict group,
family group, and winner target data.

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
- `RoadEndpointAgent`: grows road segments from recorded road endpoint state.
- `RoadBranchAgent`: grows branch roads from the existing road network.
- `RoadReconnectAgent`: repairs entrance or approach disconnection pressure.
- Three `GenericPlotAgent` instances with the same logic and different bias:
  core bias, road bias, and edge bias.
- `PlotDifferentiationAgent`: turns generic plots into use proposals through
  utility bids for residential, commercial, production, and public use.
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
-> waits across later generation steps
-> differentiated plot use
-> waits across later generation steps
-> building footprint
```

The current differentiation scores are intentionally simple, but they are
recorded as explicit bids:

- residential prefers local land value and lower nearby density;
- commercial prefers road junction pressure;
- production prefers edge and entrance pressure;
- public is limited and receives strong pressure when no public plot exists.

Each bid records plot id, use type, score, reason, nearby use counts, road
access score, core distance score, public-need score, and policy-weight score.
The resolver chooses among these bids by normal proposal arbitration.

There is no economy simulation in Phase 62. The only global demand model is a
small `DemandLedger` with housing, commerce, production, public, and road need.
It is updated after commits and gives differentiation a simple global pressure
source without adding workers, goods, income, or production chains.

Public plots do not receive building footprints in Phase 62. This prevents
plot count and building count from becoming a 1:1 immediate binding.

Small formal building footprints remain allowed for blueprint debugging in
Phase 62. When a residential, commercial, or production footprint is smaller
than 2x2, the building records a `presentation_note` marking it as a future
visual issue. Later presentation work should map 1x2 and 2x1 footprints to
stall, shed, kiosk, or similar minor structures, while formal house, shop, and
workshop output should use at least 2x2.

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
- selects winners under family and spatial capacity;
- rejects conflict losers into `GenerationTrace`;
- rejects non-winning valid candidates as conflict or family-capacity losers;
- commits winners through `SettlementBlueprint.COMMIT_TOKEN`;
- rebuilds feature maps after each commit;
- runs evaluator reports after each commit.

Phase 62 family capacity is deliberately small:

- `road_group`: at most one road winner per step;
- `plot_group`: at most one generic plot winner per step;
- `differentiation_group`: at most one non-public differentiation winner per
  step;
- `public_group`: at most one public differentiation winner per step;
- `footprint_group`: at most one footprint winner per step.

These are not execution phases. They are capacity groups that prevent a single
agent family from flooding a step while still allowing different families to
grow the blueprint together.

Rejected proposal rows include:

- resolver reason;
- validation notes;
- score;
- priority;
- winner target;
- conflict keys.

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
- score penalties with reason, weight, and affected object;
- feedback flags;
- feedback pressure;
- core count;
- road count;
- generic plot count;
- differentiated plot count;
- public plot count;
- building footprint count;
- occupied count.

Current feedback pressure includes:

- `need_more_roads`;
- `need_more_generic_plots`;
- `need_more_differentiation`;
- `need_more_footprints`;
- `need_public_space`;
- `entrance_disconnected`;
- `road_component_count`;
- `entrance_connected`;
- `core_connected`;
- `all_plot_access_connected`;
- `all_building_front_connected`;
- `road_overdensity_zones`;
- `isolated_plots`;
- disconnected building access;
- `weak_core_zones`.

Agents consume this feedback during later steps. Road agents react to road and
entrance pressure, generic plots react to plot pressure, plot differentiation
reacts to public-space pressure, and building footprints react to footprint
pressure.

Road connectivity is evaluated as a graph, not as a nearest-cell adjacency
check. The main road component starts from road cells touching the primary
entrance. Functional roads must form one connected component. Dead ends are
allowed only when they belong to that component. The entrance must connect
through the road graph to the core or a public plot. Core cells must touch the
main component, generic plot `road_access_cell` values must belong to it, and
building `front_access_cell` values must belong to it. Isolated road segments
are reported with segment ids and do not count as valid roads.

## Blueprint Anchors

Phase 62 now records semantic anchors in the blueprint:

- entrance anchors;
- core anchors;
- road endpoint anchors;
- road junction anchors;
- plot access anchors;
- building entrance anchors;
- public plot anchors.

These anchors are semantic relationship records. They are not final props and
do not imply landmark art.

`GenerationTrace` records:

- submitted proposals;
- accepted proposals;
- rejected proposals;
- committed proposals;
- evaluator reports;
- generation step transitions;
- step resolutions;
- agent candidate search, sampling, scoring, and rejection statistics;
- blueprint snapshots for time-slice replay;
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
- connectivity summary with `road_component_count`, `entrance_connected`,
  `core_connected`, `all_plot_access_connected`,
  `all_building_front_connected`, and compiled connectivity fields;
- score penalties explaining why the current evaluator score is below 1.00;
- evaluator feedback pressure;
- trace summary;
- feature-map grid;
- committed roads;
- generic and differentiated plots;
- building footprints;
- core markers;
- rejected proposal cells;
- agent search statistics: valid candidates, sampled candidates, top score,
  chosen score, and rejection distribution;
- a replay step selector backed by `GenerationTrace.blueprint_snapshots`;
- footprint details: plot id, use type, facing, entrance cell, front access
  cell, footprint size, and presentation notes;
- a step log showing accepted and rejected proposal events, including reject
  reason, score, winner target, and conflict group.

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
- `road_component_count == 1`;
- `entrance_connected == true`;
- `core_connected == true`;
- `all_plot_access_connected == true`;
- `all_building_front_connected == true`;
- `compiled_road_connected == true`;
- `compiled_entrance_connected == true`;
- `compiled_core_connected == true`;
- `compiled_plot_access_connected == true`;
- `compiled_building_front_connected == true`;
- core generation;
- road growth;
- road-accessible generic plot growth;
- multiple generic plot bias agents;
- plot differentiation;
- differentiation bid payloads;
- public plot generation;
- delayed plot differentiation and delayed footprint generation;
- building footprint generation inside differentiated plots;
- building footprint debug details;
- evaluator score-penalty details;
- plot count exceeding building count;
- semantic anchor recording;
- invalid out-of-bounds proposal rejection;
- invalid conflicting footprint rejection;
- parallel non-conflicting commits within the same generation step;
- per-family capacity enforcement;
- resolver-only commit authority;
- feature-map update count after commits;
- evaluator report count after commits;
- evaluator feedback pressure output;
- road graph connectivity pressure output;
- trace coverage for agent search statistics;
- trace coverage for blueprint replay snapshots;
- trace coverage for generation steps and all Phase 62 proposal types;
- Godot debug view rendering for roads, plots, buildings, core markers,
  rejected proposal cells, evaluator pressure, and step process logs.

## Verification

- Godot editor class registration passes.
- Runtime headless smoke execution is currently blocked by a Godot runtime
  access violation in this environment before the smoke script can report a
  normal GDScript result.
