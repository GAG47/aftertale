# Phase 65: Unified Interaction Resolver

## Status

Complete.

## Goal

Phase 65 replaces the split map-interaction flow with a single resolver based
on `InteractionCandidate` dictionaries.

The interaction range is now exactly:

- the actor's current cell;
- the actor's facing cell.

Drops, beds, wall doors, floor return points, facilities, counters,
workbenches, training points, inspectable objects, crops, terrain actions, and
NPC talk all enter the same candidate collection and sorting path.

## Candidate Contract

`LocationRoot` now resolves a single candidate containing:

- actor and actor id;
- source location id;
- source and target cells;
- relation: `current` or `facing`;
- target kind;
- target id and target reference;
- action id and action type;
- priority and action priority;
- prompt text;
- source building id;
- concrete interior location id;
- anchor id;
- facility role;
- transition context;
- metadata.

`get_interaction_prompt()` and primary action execution both call the same
resolver. The last resolved candidate is cached only while the actor cell and
facing cell stay unchanged, so prompt and execution point at the same target.

## Object Action Contract

`LocationObject` now exposes:

- `is_interactable()`;
- `get_interaction_actions(context)`;
- `build_interaction_candidates(context)`.

Objects declare actions through their existing semantic fields:

- `is_pickable` -> `pickup`;
- scene-transition fields -> `scene_transition`;
- `facility_type = rest` -> `rest`;
- `facility_type = shop` -> `shop`;
- `facility_type = crafting` -> `craft`;
- `facility_type = save` -> `service`;
- training role / training kind -> `train`;
- container / chest kind -> `open_container`;
- `is_inspectable` -> `inspect`.

No `interaction_mode` field was added. Whether an object can be stood on is
still controlled by terrain, collision, and occupancy. Non-blocking objects can
be resolved from the current cell or facing cell; blocking wall objects are
naturally resolved from the facing cell.

## Priority

The first stable priority pass is:

1. facing character talk or attack;
2. current-cell object actions;
3. facing-cell object actions;
4. current-cell exits;
5. facing-cell exits;
6. current-cell crop or terrain actions;
7. facing-cell crop or terrain actions;
8. fallback inspect.

Within the same group, candidates sort by action priority, then target id, then
action id. This keeps same-cell multi-object resolution deterministic.

## Execution

`LocationRoot` now dispatches by `candidate.action_type`:

- `pickup` submits `PickUpAction`;
- `scene_transition` uses the existing `SceneLoader` transition path;
- `rest` submits `RestAction`;
- `shop`, `service`, and `craft` open the existing facility panel path;
- `train` publishes a lightweight training interaction result;
- `harvest`, `water`, and `plant` submit existing crop actions;
- `inspect` submits `InspectAction` or crop inspect feedback;
- `talk` submits `TalkAction`;
- `attack` preserves the existing combat entry behavior;
- `open_container` has a placeholder result until the container system exists.

Existing action systems remain the execution layer. Phase 65 only unifies
candidate resolution and dispatch.

## v64 Contract Consumption

The resolver directly consumes the Phase 64 generated-interior contract:

- wall-door objects carry concrete `target_location_id`;
- return doors preserve `source_building_id`;
- generated bed, counter, workstation, training, and activity objects expose
  candidates from the concrete interior location;
- `generated_basic_interior` remains only a scene shell and is not used as an
  interaction candidate location id.

## Validation

Added `scripts/tests/v65_unified_interaction_resolver_smoke.gd`.

The smoke test verifies:

- standing on a generated bed resolves and executes `rest`;
- facing a generated bed resolves and executes `rest`;
- standing on a dropped item resolves and executes `pickup`;
- facing a dropped item resolves and executes `pickup`;
- same-cell objects sort stably by object id;
- current-cell objects beat ordinary facing-cell objects;
- facing NPC talk beats ordinary object interaction;
- facing a generated exterior wall door enters its concrete generated
  interior;
- standing on an interior return point returns to the exterior;
- facing an interior return point also returns to the exterior;
- prompt and execute use matching target id, action type, target cell, and
  relation;
- concrete generated interiors never report `generated_basic_interior` as the
  candidate source location;
- v64 generated-interior contract smoke still passes;
- v64 policy playable settlement smoke still passes;
- v63 settlement scene compiler smoke still passes.

## Verification

- `run_v65_smoke.json` smoke execution passes.
- Godot headless project load passes.
- `git diff --check` passes.
