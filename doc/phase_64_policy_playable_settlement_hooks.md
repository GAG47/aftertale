# Phase 64: Policy-Driven Playable Settlements

## Status

Complete.

## Goal

Phase 64 turns the Phase 62/63 settlement pipeline from a single generated
settlement sample into policy-driven settlement variation with gameplay hooks.
It does not generate settlement population. NPC creation, household planning,
job assignment, schedules, and AI-driven residents are deferred to a later
phase.

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
- `home_capacity`
- `work_slots`
- `service_slots`
- `activity_slots`
- `home_slot_anchor`
- `work_slot_anchor`
- `service_slot_anchor`
- `activity_slot_anchor`
- `entrance_anchor`
- `interaction_anchor`
- `quest_anchor`

Public plots receive:

- `public_anchor`
- `public_activity_anchor`
- `notice_anchor`
- `quest_anchor`
- `interaction_anchor`

Entrances and roads receive:

- `player_spawn_anchor`
- `settlement_entrance_anchor`
- `road_network_anchor`

The compiler maps these hooks into normal location data:

- generated building wall doors become non-blocking, non-rendered
  scene-transition objects on the wall-door cell; the visible door is supplied
  by the structure layer, not by a separate exterior floor object;
- each generated building door receives its own exterior return entrance;
- generated commercial hooks keep semantic service slots, but v64 does not
  compile generated shop objects, shop counters, shop records, or shopkeepers;
- generated public hooks become public interaction objects;
- no generated NPCs are written to location data;
- no shopkeeper, worker, resident, or public-gatherer records are generated;
- player spawn remains driven by the generated entrance through the normal
  scene runtime, not through settlement-generated character records.

Phase 64 adds a small `generated_basic_interior` location so generated
building entrances can resolve to a loadable scene while full interior
generation remains deferred.

Enterable generated buildings are now formal structures. A building with an
interior template and scene-transition door must be at least `2x3` or `3x2`.
Small `1x1`, `1x2`, and `2x1` structures are not treated as enterable
buildings and must not receive interior templates or entrance interactions.

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
Interior return objects can be used from the player's current cell, so the
player does not need to face the exit tile after stepping onto it.

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
- generated buildings expose interior and semantic slot hooks;
- generated building doors return to per-building exterior entrances, not the
  main entrance;
- generated building door interaction objects are wall-bound, non-blocking,
  and non-rendered;
- at least one generated building maps to an interior template;
- generated settlement compiler produces zero character records;
- generated NPC count remains zero;
- generated settlement compiler produces zero generated shop records and zero
  generated shop counter objects;
- the default roadside generated settlement is not dominated by commercial
  plots;
- enterable generated buildings are at least `2x3` or `3x2`;
- small structures do not receive interior templates or scene-transition
  interactions;
- `generated_settlement.json` is driven by `settlement_policy_id`.

## Verification

- Godot headless project load passes.
- `run_v64_smoke.json` smoke execution passes.
