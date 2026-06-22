# Phase 60: Agent Settlement Blueprint Planner

## Status

Complete as v60.3. The default generated village path now uses the agent
blueprint planner without compiler path recovery, and the v60 smoke test has
been rerun successfully after the v60.3 cleanup.

## Goal

Phase 60 replaces the default settlement exterior layout authority with an
agent-based iterative blueprint planner. The internal model follows the paper's
useful shape for this project: shared feature maps, decentralised candidate
proposals, iterative blueprint commits, and later translation into the existing
runtime schema.

The important boundary is that this phase changes how the exterior blueprint is
planned, not how runtime locations work. The existing v59 contracts still own
the compiled output:

- parcels;
- building requests;
- prefab placement;
- building instances;
- exterior door anchors;
- generated interior location ids;
- interior entry, exit, and primary anchors;
- NPC schedule target anchors.

The downstream runtime systems should not need to know whether the final rows
came from an older debug planner or the new agent planner. In the default v60.3
path, however, the compiler is no longer allowed to repair missing planner
roads or fake missing functional areas. Missing planner output must stay
visible as validation failure.

## Why Replace BSP

The BSP district graph was useful for proving deterministic generated villages,
but it made early village layout feel too geometric. It also encouraged the
generator to treat every subdivided leaf as a candidate district even when the
gameplay contract only needed a small number of reachable anchors and
street-facing parcels.

The v60 planner keeps deterministic generation but changes the authority from
partition interpretation to agent proposals:

```text
terrain/location bounds
-> FeatureMapSet
-> open growth auction
-> validated blueprint commits
-> v59-compatible town zones, parcels, building requests, anchors
-> prefab placement and generated interiors
```

BSP is no longer the default layout path for `test_village`.

## Feature Maps

`AgentSettlementPlanner` creates a shared `FeatureMapSet` for the planning
turn. The first implementation tracks:

- `walkable_map`
- `blocked_map`
- `road_map`
- `plot_map`
- `reserved_map`
- `frontage_map`
- `water_map`
- `edge_score_map`
- `center_score_map`
- `quiet_score_map`
- `farm_score_map`
- `public_score_map`

Agents do not write these maps directly. They submit proposals, the planner
validates and commits accepted proposals to the blueprint, and then the feature
maps are rebuilt from that blueprint. This keeps planning state centralized and
prevents agents from silently disagreeing about occupied cells.

## Open Growth Auction

The v60 planner is not a scripted stage sequence. Every planning turn rebuilds
the shared feature maps from the accepted blueprint, asks all available agents
for candidates, rejects invalid candidates, and commits the highest-scoring
valid candidate. Agents compete through scores and constraints; they do not
write directly into the map.

The current agent ids are:

- `road_growth`
- `public_space`
- `civilian_plot`
- `residential_bid`
- `shop_bid`
- `workshop_bid`
- `tavern_bid`
- `farm_claim`
- `training_claim`
- `gate_claim`
- `decoration_fill`

The seed road is still bootstrapped because the road distance map needs an
initial connected source. After that, the planner summary reports
`control_model = open_growth_auction` and
`scripted_stage_sequence = false`.

The functional-area agents now scan open map regions instead of compressing a
rectangle against the boundary. This prevents fake success such as a one-tile
farm and gives farm/training/gate claims real competition against roads and
civilian plots.

In v60.3, farm and training candidates no longer inherit fixed left/right
placement assumptions. They scan valid rectangles across the available map and
must prove an actual access edge against already committed planner roads.

The gate claim now commits its connector road as part of the same accepted
proposal. A later compiler pass may materialize those road cells, but it may
not invent a replacement route for the default agent path.

Generic civilian plots are deliberately separate from concrete buildings.
Building bid agents later differentiate those plots into residence, shop,
workshop, tavern, farm support, storage, or guard roles according to the
request list and local scores. Parcel ids are generated from the growth turn so
later plots cannot collide with already assigned parcels.

Building demand is state weighted, not a fixed stage list. Residence and shop
remain required starter requests. Optional requests become useful only when the
blueprint has created the supporting context: farm support and storage after a
farm, guardhouse after a gate, tavern after a plaza, workers after housing, and
workshops after enough parcel/market context exists.

## Parcel Access

v60.3 separates visual building facing from parcel access. Building art still
faces south so the player can see doors in the top-down view, but the parcel
itself may open to a road on the north, east, south, or west side.

Each agent lot records an `access_cell` and `access_side`. Prefab placement then
keeps the south-facing door and creates an internal yard path from the parcel
entry to the visible doorstep. This avoids forcing every generated parcel to be
south of a road while keeping the existing 2D building presentation readable.

## Runtime Contract

`VillageRoadGenerator` still compiles the final runtime location data. After the
agent blueprint is accepted, the compiler materializes planner-owned rows for:

- prefab selection;
- parcel surface, access, frontage, and yard overlays;
- building instance ids;
- door objects and exterior door anchors;
- transition pairs;
- generated interior manifests;
- generated character rows and schedules.

The generated location also records a `building_requests` summary so the agent
role assignment is inspectable, but runtime systems continue to consume the
existing `parcels`, `buildings`, `anchors`, `interiors`, and `transitions`
arrays.

The compiler records `compiler_recovery_count` and `compiler_recovery_log`.
For `agent_settlement_blueprint`, recovery count must remain zero. The legacy
road-first debug path may still use compiler recovery, but the default planner
path treats recovery as an error instead of a convenience.

The planner summary also exposes `generic_parcel_count`,
`building_plan_count`, `assigned_request_ids`, `unassigned_parcel_count`,
`required_zone_ids`, `required_request_ids`, `auction_log`, `commit_log`,
`rejected_log`, and `unmet_goals`. `unmet_goals` is intentionally explicit so
missing required growth output cannot be hidden by the v59-compatible compiler
layer.

## Merchant And Guard Compatibility

The current merchant-like NPC is `debug_villager`. Their schedule is still
generated by `VillageRoadGenerator` after buildings compile:

- home entries target the generated home interior `primary` anchor;
- shop entries target the generated shop interior `primary` anchor;
- cross-scene schedule entries keep `transition_anchor_by_location` pointing
  back to the exterior building door anchor.

The guard remains `debug_guard` and keeps exterior schedule anchors:

- `training_yard_guard_post`
- `plaza_social_spot`
- `wild_gate_guard_post`

The v60 planner must provide the source areas for those anchors, and the
validator confirms the resolved exterior anchors are walkable and reachable from
the plaza.

## Explicit Non-Goals

Phase 60 does not add:

- population generation;
- a new NPC schedule planner;
- persistent generated settlement snapshots;
- AI dialogue;
- settlement economy simulation;
- multi-settlement world generation;
- SceneLoader, NpcScheduleSystem, interaction, or save-system rewrites.

## BSP And Fallback

The old road-first helper path remains available only as an explicit debug
fallback through generator data:

```json
{ "layout_planner": "legacy_road_first" }
```

The default path is `agent_settlement_planner`, and generated summaries report:

```text
type = agent_settlement_blueprint
default_layout_authority = agent_settlement_planner
uses_bsp_layout = false
```

## Validation And Smoke

`VillageRoadGenerator.validate_location_contract()` now checks the expanded v60
contract:

- road/plaza/exit network exists and is connected;
- the default agent path did not use compiler road recovery;
- planner-declared required town zones and required building requests exist;
- required residence/shop checks are derived from planner-declared request ids;
- exterior anchors are walkable and reachable;
- schedule targets resolve through anchors, not raw grid positions;
- interior location ids are unique;
- transition pairs reference known exterior/interior locations;
- building door frontage is walkable and reachable;
- parcel access sides are valid and can be north, east, south, or west;
- decorations do not overlap critical schedule anchors.

`scripts/tests/v60_agent_settlement_smoke.gd` verifies the new default planner,
determinism for the fixed seed, road/plaza/parcel output, merchant shop anchor
resolution, guard training/gate anchor resolution, generated interiors, door
transitions, prefab placement, and absence of validation errors.

The smoke test also rejects a retreat to the old minimum loop by requiring:

- open auction metadata;
- real multi-candidate arbitration;
- zero compiler recovery in the default agent path;
- empty `unmet_goals`;
- parcel access on at least two different sides for the fixed seed;
- at least three differentiated building plans for the fixed seed;
- at least one optional request beyond the required residence/shop pair.

## v60.3 Cleanup Notes

The v60.3 pass removed the remaining default-path dependencies on the previous
minimum-loop interpretation:

- no default compiler path recovery;
- no fake empty-area materialization for plaza, farm, training, or gate;
- no fixed farm-right or training-left placement assumption;
- no assumption that a parcel must sit south of its road;
- no validator-only hard-coded truth for required zones/requests when the
  planner declares its own contract;
- no gate without a planner-committed connector road.

Two debug characters remain part of the contract on purpose. `debug_villager`
and `debug_guard` are still useful probes for generated interiors, exterior
anchors, transitions, and schedule target resolution. They may constrain anchor
existence, but they should not dictate the settlement shape.

## Follow-Up Directions

Useful later work can expand the same proposal/commit model without changing the
runtime contract:

- richer frontage scoring;
- more parcel shapes;
- broader optional-building diversity when map size allows;
- water-aware planning if a location adds water;
- debug UI overlays for feature maps and rejected proposals.
