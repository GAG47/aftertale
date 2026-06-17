# Phase 64: Policy-Driven Playable Settlements

## Status

Complete.

## Goal

Phase 64 turns the Phase 62/63 settlement pipeline from a single generated
settlement sample into policy-driven settlement variation with gameplay hooks.

All supported settlement types still use the same generation entry:

```text
generate_settlement(policy)
```

No separate village, forest, trade, mining, or test-settlement generator was
introduced.

## Policy Profiles

Added settlement policy profiles under `data/settlement_policies/`:

- `farming_village.json`
- `forest_village.json`
- `roadside_trade_village.json`
- `mining_camp.json`

Each profile defines:

- settlement type and scale;
- economy tags;
- road style;
- density;
- wealth and defense levels;
- required and banned landmarks;
- agent weight overrides;
- demand weight overrides;
- plot-use bidding weights;
- asset family preferences;
- gameplay hook rules;
- a deterministic policy seed.

`SettlementPolicy` can now load a policy profile by id and merge optional
inline generator overrides. `generated_settlement.json` now specifies
`settlement_policy_id` instead of embedding a temporary fixed test policy.

## Generation Effects

Policy data now affects generation rather than acting as metadata only.

The session applies policy to:

- agent activation cadence and commit caps;
- agent weight summaries;
- demand ledger target counts;
- plot use bidding weights;
- road style scoring;
- target plot count;
- building fill ratio;
- building type selection;
- interior template selection;
- building asset family selection;
- generated gameplay hook ids.

The same agents remain active across policies. Differences come from policy
profile data, not from separate generator classes.

## Growth Hardening

Phase 64 no longer uses the earlier fixed demonstration plot cap.

Settlement size now scales from:

- buildable map area;
- policy density;
- policy scale;
- demand ledger pressure;
- dynamic agent commit budgets;
- dynamic generation step budget.

Candidate sampling also scales with the settlement target and candidate pool
instead of using the same small fixed sample size on every map. This preserves
the paper-style process of collecting legal candidates, sampling, scoring, and
choosing a winner without forcing a 48x32 map to behave like a small smoke
sample.

## Gameplay Hooks

Blueprint buildings now carry the required gameplay fields:

- `building_type`
- `use_type`
- `plot_id`
- `area`
- `entrance_cell`
- `front_access_cell`
- `facing`
- `interior_template_id`
- `npc_home_anchor`
- `npc_work_anchor`
- `interaction_anchor`
- `shop_anchor`
- `quest_anchor`

Public plots receive:

- `public_anchor`
- `npc_gather_anchor`
- `notice_anchor`
- `quest_anchor`
- `interaction_anchor`

Entrances and roads receive:

- `player_spawn_anchor`
- `settlement_entrance_anchor`
- `road_network_anchor`

The compiler maps these hooks into normal location data:

- generated building doors become scene-transition objects;
- each generated building door receives its own exterior return entrance;
- generated commercial hooks become shop-capable objects when a commercial
  building exists;
- generated public hooks become public interaction objects;
- generated NPCs are spawned from blueprint home, work, and public anchors
  instead of a single handwritten coordinate;
- NPC schedule rows move between distinct generated anchor ids;
- player spawn remains driven by the generated entrance.

Phase 64 adds a small `generated_basic_interior` location so generated
building entrances can resolve to a loadable scene while full interior
generation remains deferred.

## Debug View

`SettlementDebugView` now supports policy comparison.

It includes:

- a policy selector for the four v64 profiles;
- a regenerate button for the active policy;
- active policy id and settlement type;
- road style;
- density;
- asset family;
- agent weight summary;
- demand ledger;
- plot use counts;
- building type counts;
- required landmark status;
- existing connectivity diagnostics;
- existing score penalties;
- existing step replay and agent search panels.

This keeps the debug view focused on proving policy-driven generation
behavior, not just showing a final map.

## Compiler Contract

`DefinitionLoader` now accepts both `settlement_blueprint` and `settlement`
generator types for the shared compiler path.

`TileSceneCompiler` reads `settlement_policy_id`, loads the corresponding
policy profile, runs the normal settlement session, and compiles the resulting
blueprint into location data.

Generated location results are cached by resolved location id and data path.
Returning from a generated interior to the exterior settlement reuses the
materialized settlement instead of rerunning the full generation session.

The compiler still does not repair invalid planning. Road graph validation
remains strict. Entrance presentation no longer overwrites a road tile when
the entrance cell is already part of the road network.

## Validation

Added `scripts/tests/v64_policy_playable_settlement_smoke.gd`.

The smoke test verifies:

- all four policies generate through the same compiler/session pipeline;
- policy plot-use counts are observably different;
- policy agent-weight summaries are different;
- farming production weight is higher than farming commercial weight;
- roadside commercial weight is higher than farming commercial weight;
- mining production and worker-housing pressure are high;
- forest density is lower than roadside density;
- every policy preserves v62.5 compiled road connectivity;
- the roadside 48x32 policy sample is not capped at the old 18-plot demo size;
- generated buildings expose interior and interaction hooks;
- generated building doors return to per-building exterior entrances, not the
  main entrance;
- at least one generated building maps to an interior template;
- generated NPC schedules contain distinct semantic anchor targets;
- generated shop objects use generated shop ids and blueprint-bound vendors;
- `generated_settlement.json` is driven by `settlement_policy_id`.

## Verification

- Godot headless project load passes.
- `run_v64_smoke.json` smoke execution passes.
