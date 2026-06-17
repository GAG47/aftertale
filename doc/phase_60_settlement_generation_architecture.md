# Phase 60: Settlement Generation Architecture

## Status

Complete.

## Goal

Phase 60 defines the permanent settlement generation architecture.

This phase rejects previous scene-generation implementations as active design
authority. Removed BSP, road-first, parcel, prefab, and generated-interior
paths must not shape the new generator's data model, ownership boundaries, or
output contract.

From this phase forward, every settlement type must use the same generation
pipeline:

```text
SettlementPolicy
SettlementContext
        |
SettlementGenerationSession
        |
        v
FeatureMaps
-> Agents
-> Proposals
-> Resolver
-> Blueprint
-> Evaluator
-> Compiler
```

Village, forest village, fishing village, mining camp, roadside town, port
town, fortress town, and city generation must not become separate generator
families. Their differences must come from policy data, agent activation by
step, agent weights, evaluator weights, and asset families.

## Result

Phase 60 establishes the new settlement-generation authority. It defines the
pipeline, lifecycle owner, seed ownership, proposal lifecycle, trace model,
blueprint authority, resolver/evaluator boundary, compiler contract, roadmap
boundaries, and forbidden implementation patterns.

No runtime settlement behavior is implemented in this phase. That work begins
in Phase 61. Phase 60 is complete because the architecture and future phase
contracts are now stable enough for implementation to proceed without depending
on the removed BSP, road-first, parcel, prefab, or generated-interior paths.

## Architectural Rule

Phase 60 is an architecture-definition phase, not a temporary implementation
phase.

The complete structure must be designed before settlement behavior is expanded.
The generator must not be developed through throwaway partial pipelines,
compatibility shims for the old village data shape, or feature slices that
pretend to be the final architecture while bypassing core layers.

The active design rule is:

```text
generate_settlement(policy)
```

The forbidden design shape is:

```text
generate_village()
generate_port()
generate_city()
generate_fortress()
```

## Seed Ownership

Randomness belongs to the generation session, not to multiple planning data
objects.

`SettlementContext` may expose a world seed or source-world identity.
`SettlementPolicy` may request a settlement seed override. The active random
state, deterministic step order, and reproduced run metadata belong to
`SettlementGenerationSession`.

## Core Data Model

### SettlementPolicy

`SettlementPolicy` describes what kind of settlement should grow and why.

It owns:

- settlement type;
- scale;
- economy tags;
- geography preferences;
- road style;
- density;
- defense level;
- wealth level;
- required landmarks;
- banned landmarks;
- district rules;
- aesthetic tags;
- agent weight overrides;
- evaluator weight overrides;
- asset family preferences.

It must not own exact tile placements, exact building coordinates, or renderer
instructions. It also must not own the active random state.

### SettlementContext

`SettlementContext` describes the world area available to the generator.

It owns:

- map size;
- terrain grid;
- existing roads;
- existing water;
- existing obstacles;
- entrances;
- important world points;
- asset catalog references;
- source-world seed or source-world identity.

It must not choose the settlement plan. It only reports available facts.

### SettlementGenerationSession

`SettlementGenerationSession` owns the generation lifecycle.

It owns:

- policy;
- context;
- active random state;
- current step;
- active agents;
- deterministic execution order;
- proposal history;
- committed events;
- generation trace;
- debug trace;
- final blueprint;
- compiler handoff.

It must not create settlement intent directly. It initializes feature maps and
the blueprint, activates agents by step, gathers proposals, calls the resolver,
calls the evaluator, advances generation steps, and hands the final blueprint
to the compiler.

### FeatureMapStore

`FeatureMapStore` converts context and accepted blueprint changes into maps
that agents can read.

The required maps are:

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

More maps may be added later, but feature maps must remain explainable,
deterministic, and derived from context or accepted proposals.

### SettlementBlueprint

`SettlementBlueprint` is the semantic plan. It is the generator's main truth.

It owns:

- cores;
- districts;
- roads;
- plots;
- buildings;
- landmarks;
- production areas;
- defenses;
- decorations;
- entrances;
- exits;
- interaction anchors;
- history events.

It must not directly store final tile strings, Godot node paths, renderer-only
objects, or temporary repair artifacts.

Decorations are semantic decoration plans, not final rendered props. A
decoration plan may describe a fence line, clutter area, shrine approach,
market-stall group, tree belt, or roadside detail density. It must not describe
final Godot node paths or one-off rendered props.

`SettlementBlueprint.history` records accepted semantic events only. Rejected
proposals, validation notes, scores, and debug diagnostics belong to the
generation trace.

### SettlementAgent

`SettlementAgent` is a spatial planner.

Each agent may read policy, context, feature maps, and blueprint state. It may
submit proposals. It must not directly mutate the blueprint, feature maps, or
compiled scene output.

Required agent families:

- core agent;
- road agent;
- district agent;
- plot agent;
- building agent;
- public anchor or landmark agent;
- production agent;
- defense agent;
- detail agent;
- correction agent.

Agents are not NPCs. They are planning components.

Required agent families must exist as part of the architecture, but they do not
all run for every settlement. Activation is controlled by `SettlementPolicy`,
agent activation step, feature-map pressure, and evaluator feedback.

`CorrectionAgent` is not a late patching system. It participates in the normal
proposal loop and may only submit correction proposals before compilation. It
may propose work such as reconnecting broken paths, freeing blocked entrances,
reducing over-dense plot clusters, or restoring required approach space. It must
not bypass the resolver, mutate compiled scene data, or make an invalid
blueprint appear valid during compilation.

### PlanProposal

`PlanProposal` is the only way an agent asks to change the plan.

It owns:

- proposal id;
- proposer id;
- step;
- stage;
- type;
- priority;
- score;
- cost;
- reason;
- affected cells;
- area;
- path;
- tags;
- dependencies;
- conflicts;
- payload;
- validation notes.

Proposals must be inspectable. A proposal that cannot explain its reason must
not be accepted.

The proposal lifecycle is:

```text
created
-> validated or rejected
-> scored
-> accepted or superseded
-> committed
-> recorded in the generation trace
```

Accepted and committed proposals may create blueprint history events. Rejected,
superseded, and low-scoring proposals must remain in the generation trace, not
in blueprint history.

### ProposalResolver

`ProposalResolver` is the only system allowed to commit proposals.

It owns hard accept-or-reject authority:

- boundary checks;
- collision checks;
- reachability checks;
- road-continuity checks;
- density checks;
- hard settlement-policy checks;
- step compliance checks;
- conflict arbitration;
- priority arbitration;
- blueprint mutation;
- feature-map update dispatch.

It must not generate new design intent. It accepts, rejects, orders, and commits
agent proposals.

The resolver decides whether a proposal can be committed. It may consult
evaluator feedback, but final commit authority remains in the resolver.

### SettlementEvaluator

`SettlementEvaluator` participates throughout generation.

It owns quality scoring, pressure feedback, and diagnostic reports:

- required landmark checks;
- road connectivity checks;
- anchor reachability checks;
- plot access checks;
- building entrance checks;
- district coherence checks;
- economy relationship checks;
- defense boundary checks;
- settlement-type fit feedback;
- visual-plausibility checks;
- failure reports;
- score reports.

Evaluator checks are not a final afterthought. Generation must consult the
evaluator after committed changes and use its reports to guide later proposals.

The evaluator does not commit proposals. It reports quality, fit, pressure, and
needed improvements back to the session and later agent steps.

### GenerationTrace

`GenerationTrace` is the debug record of the run.

It owns:

- generated proposals;
- rejected proposals;
- superseded proposals;
- proposal scores;
- validation notes;
- evaluator reports;
- feature-map update notes;
- generation step transitions;
- deterministic random decisions;
- debug diagnostics.

It is separate from `SettlementBlueprint.history`. The blueprint records the
accepted semantic history of the settlement. The trace records why generation
made or rejected decisions.

### TileSceneCompiler

`TileSceneCompiler` is the only layer that converts blueprint data into Godot
scene data.

It owns:

- ground tiles;
- road tiles;
- structure records;
- building objects;
- collision records;
- navigation records;
- interaction points;
- debug overlays;
- reproducible generation metadata.

It must not make settlement planning decisions. If the blueprint is invalid,
the compiler must fail instead of silently repairing it.

Phase 60 defines the compiler contract even though full Godot scene compilation
is implemented in Phase 64.

Before Phase 64, the project must still provide Godot-visible debug output for
the active blueprint state. Early visual output may be a debug renderer,
blueprint overlay, generated report scene, or inspection view instead of final
gameplay-ready scene data. Intermediate roadmap versions must not be invisible.

## Roadmap Boundaries

### Phase 60

Define the complete data structures, ownership boundaries, and pipeline rules.
No old data contract may be treated as the target shape. Define the compiler
contract and the required debug-visibility contract.

### Phase 61

Implement decentralized iterative planning. Agents read feature maps and submit
proposals. The resolver commits accepted proposals and updates the blueprint.
The evaluator participates after each committed step. Godot must be able to show
the current blueprint and generation trace in a debug view.

### Phase 62

Implement road growth, generic plot growth, plot differentiation, and building
footprint generation through the shared pipeline. The output must be reachable,
explainable, and renderable as a blueprint. It must not be hard-coded for one
village type. Godot must be able to show roads, plots, differentiated plot
uses, building footprints, rejected proposals, evaluator feedback, and a step
process log as debug overlays or inspection views.

Full landmark behavior is deferred. Phase 62 may keep only core or public
anchors needed for debugging and feature-map pressure.

### Phase 63

Compile settlement blueprints into the normal Godot location pipeline. The
compiler must produce visible tiles, plots, buildings, collision, road graph
diagnostics, debug overlays, seed persistence, and reproduction metadata
without repairing invalid planning.

### Phase 64

Support policy-driven settlement variation and generated gameplay hooks through
the same settlement pipeline. `SettlementPolicy` profiles may alter agent
weights, demand pressure, plot bidding, road style, density, asset families,
and gameplay hook rules, but no settlement type may introduce a separate
generator entry point.

## Forbidden Patterns

- Do not revive the BSP layout as an active settlement planner.
- Do not revive the old road-first shortcut implementation.
- Do not use previous village output data as the new architecture target.
- Do not let agents directly mutate the blueprint.
- Do not let the compiler repair invalid plans.
- Do not create one generator per settlement type.
- Do not let large-language-model output place final tiles or buildings.
- Do not add tensor fields, diffusion, shape grammars, or external city tools
  to the core pipeline.
- Do not hide invalid planning behind late repair routes.

## Completion Standard

Phase 60 is complete when the following are defined in code or design records:

- every core class listed in this document has a stable responsibility;
- seed ownership belongs to the generation session;
- ownership boundaries are explicit;
- the generation session lifecycle is explicit;
- the proposal lifecycle is explicit;
- generation trace and blueprint history are separate;
- the resolver's authority is explicit;
- evaluator participation is part of the generation loop;
- compiler authority is limited to blueprint-to-scene conversion;
- intermediate roadmap versions have Godot-visible debug output requirements;
- settlement-type variation is policy-driven;
- old village generation formats are not treated as compatibility targets;
- future phases can implement behavior without changing the core pipeline.

## Verification

This phase is verified by design review rather than visual scene output.

Required checks:

- the development roadmap points to this architecture as the active Phase 60
  record;
- later work can be assigned to Phase 61 through Phase 64 without changing the
  pipeline shape.

Verified:

- the development roadmap points to this architecture as the active Phase 60
  record;
- removed Phase 60 and Phase 60.1 development logs are no longer present;
- Phase 61 through Phase 64 have explicit implementation boundaries;
- Phase 61 through Phase 63 require Godot-visible debug output instead of
  invisible data-only progress;
- `git diff --check` passes.
