# Phase 61: Adaptive Parcel Building Cores

## Status

Complete. The default generated village now compiles agent-planned civilian
lots as organically grown cell-set parcels, protects required settlement goals
from optional growth through priority-filtered auction arbitration, fits
south-facing building cores inside those parcel cells, and adapts yards and
parcel paths to the accepted parcel shape.

## Goal

Phase 61 removes the remaining rectangular prefab-lot assumption from ordinary
building placement. The old prefab catalog is no longer treated as a whole
rectangular lot. It is treated as a building core definition:

- footprint size;
- role/archetype tags;
- south-facing door offset;
- visual facade data;
- optional local exterior slots.

The parcel owns the larger shape. The compiler may keep old prefab slots only
when they fit the actual parcel yard cells. It may not force a rectangular yard
just because the prefab once declared one.

## Door Rule

Building doors remain south-facing. This is a top-down 2D presentation rule:
players need to see and use the door clearly.

Parcel access is separate from door facing. A parcel may connect to a road from
the north, east, south, or west side, but the building core still has a south
door. The parcel then owns the internal path from its access cell to the
visible doorstep.

## Cell-Set Parcels

`AgentSettlementPlanner` now writes generic civilian lots with explicit
`cells`, `cell_count`, and `shape_model`. The active model is
`cell_set_organic_growth_lot`: a connected cell set grown from the road access
cell into a local core area and then expanded by frontier scoring. This keeps
the parcel reachable and able to host a south-door building core while avoiding
the transitional fixed notched shape.

The feature maps rebuild `plot_map` from parcel cells when present. Candidate
validation also checks parcel cells instead of treating every lot as only a
bounding rectangle.

## Required Goal Arbitration

Required settlement goals are protected by `required_goal_policy =
priority_filtered_auction`. While any required goal is missing, optional
building bids and decoration slots cannot win the auction. Roads may still win
when they are needed to expose future candidates, and required candidates still
compete by score:

- plaza;
- farm;
- training yard;
- wild gate;
- required residence;
- required shop.

If a required goal still cannot be produced, it remains in
`required_goal_failures` and `unmet_goals`; the compiler and tests treat that as
visible failure, not as an acceptable smaller village.

## Building Core Adaptation

`VillageRoadGenerator` now converts an accepted lot into a parcel with:

- `bounds` as the outer debug rectangle;
- `cells` as the authoritative parcel shape;
- `buildable_cells` for inspectable compiler output;
- `access_cell` and `access_side`;
- `door_side = south`.

Prefab placement searches for a south-door building core whose footprint,
door, doorstep, and parcel path all stay inside the parcel cell set. Successful
placements record:

- `core_placement.model = south_door_core_fitted_to_parcel_cells`;
- `core_placement.door_policy = south_only`;
- `yard_cells`;
- `yard_path`;
- `adaptive_yard_slots`.

If no building core fits a requested lot, the compiler records a
`building_adaptation_failure`. Required residence/shop failures are validation
errors.

## Presentation

Parcel surfaces, front clearance, and front paths can now be emitted per cell.
This lets debug presentation reflect irregular parcels instead of painting only
one rectangle.

Adaptive yard decorations are generated from the accepted parcel yard cells.
Old prefab exterior slots remain optional local decorations and are skipped
when their resolved cell falls outside the final parcel yard.

## Validation

The v61 contract checks:

- agent settlements do not use compiler road recovery;
- the generated summary reports organic cell-set parcel and south-door core
  placement models;
- the planner reports required-goal priority arbitration and no required-goal
  failures;
- required building core adaptation did not fail;
- every agent parcel has a nonempty cell set and valid access cell;
- every generated building keeps `door_side = south`;
- every building core footprint, door, doorstep, yard path, and yard cell stays
  inside its parcel cell set;
- adaptive core placement records use `door_policy = south_only`.

`scripts/tests/v61_adaptive_parcel_building_core_smoke.gd` verifies the default
test village contains organically grown irregular parcel cell sets, no
transitional notched parcel model, protected required goals, and adaptive yard
slots.

## Boundaries

This phase does not implement the paper's full worker, goods, income, and
settlement economy loop. It also does not complete a world-connection planner
for regional trade, roads, or wilderness logic. Those remain future settlement
growth layers.

Special public areas such as farm and training yard are still functional area
claims, not ordinary building-core parcels. They are now protected required
goals in the planner, so optional buildings cannot crowd them out. Their
internal decoration logic is still not the same generalized parcel-structure
generator used here for ordinary buildings.
