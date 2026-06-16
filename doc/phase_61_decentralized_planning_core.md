# Phase 61: Decentralized Planning Core

## Status

Complete.

## Goal

Phase 61 implements the first runnable settlement-generation loop from the
Phase 60 architecture.

This phase does not attempt to generate a full village, port, fortress, or
city. Its purpose is to prove that the core pipeline can run deterministically,
that agents can only submit proposals, that the resolver is the only commit
entry point, that feature maps and evaluator reports update after commits, and
that Godot can display the intermediate planning state.

## Implemented Core

Added the first settlement planning core under
`scripts/systems/settlements/`:

- `SettlementPolicy`
- `SettlementContext`
- `SettlementGenerationSession`
- `FeatureMapStore`
- `SettlementBlueprint`
- `SettlementAgent`
- `PlanProposal`
- `ProposalResolver`
- `SettlementEvaluator`
- `GenerationTrace`

The session owns deterministic execution, random state, step order, active
agents, proposal ids, committed steps, trace output, feature maps, blueprint,
resolver, and evaluator.

## Agent Loop

Phase 61 established proposal-only agent participation:

- `CoreSeedAgent`: submits a valid core proposal.
- a road-growth agent submits a valid road proposal.
- `InvalidProposalAgent`: submits an intentionally invalid out-of-bounds
  proposal.

Agents do not mutate the blueprint. They only return `PlanProposal` objects.

## Resolver Authority

`ProposalResolver` validates and commits proposals. It rejects unsupported,
out-of-bounds, blocked, or unbuildable proposal cells.

`SettlementBlueprint` rejects direct writes without the resolver commit token.
This makes the resolver the only accepted commit entry point for Phase 61.

## Feature Maps

`FeatureMapStore` initializes the required Phase 60 maps:

- buildable;
- occupied;
- terrain cost;
- accessibility;
- road distance;
- water distance;
- entrance distance;
- edge distance;
- center distance;
- slope or roughness;
- resource proximity;
- density pressure;
- district pressure;
- land value;
- danger;
- beauty.

Committed proposals update the occupied, road-distance, accessibility, and
density-pressure maps. The store records update count and the last committed
proposal id.

## Evaluator And Trace

`SettlementEvaluator` runs after every committed proposal. Its reports include
step, committed proposal id, score, issues, core count, road count, and
occupied count.

`GenerationTrace` records:

- created proposals;
- accepted proposals;
- rejected proposals;
- committed proposals;
- proposal scores;
- evaluator reports;
- generation step transitions;
- deterministic random decisions;
- session events.

Blueprint history remains separate and records only accepted semantic events.

## Godot Debug View

Added `SettlementDebugView` and `scenes/tools/settlement_debug_view.tscn`.

The debug view renders:

- blueprint summary;
- proposal summary;
- feature-map grid;
- evaluator report summary;
- trace summary.

This is not the Phase 64 gameplay compiler. It is the Phase 61 visible debug
surface required to keep intermediate generation work inspectable in Godot.

## Validation

Added `scripts/tests/v61_settlement_planning_smoke.gd`.

The smoke test verifies:

- fixed-seed deterministic execution;
- normal agent participation;
- invalid proposal rejection;
- agents do not directly mutate the blueprint;
- resolver-only commit authority;
- feature maps update after commits;
- evaluator reports after commits;
- trace records proposals, accepts, rejects, and random decisions;
- Godot debug view renders blueprint, proposals, feature map, evaluator report,
  and trace summary.

## Verification

- `git diff --check` passes.
- `tools/validation/validate_locations.ps1` passes.
- `v61_settlement_planning_smoke.gd` passes under Godot headless.
