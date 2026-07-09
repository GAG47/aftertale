# Phase 64.1: Interior World Nodes

## Status

Complete as v64.1.

## Goal

v64.1 extends the v64 world/location graph so enterable interiors are world
child locations and doors are world transition edges. This is not a world-map
UI pass, and not a rewrite of the building interior generator.

The model is:

```text
parent exterior location
-> child interior location node
-> enter door edge
-> leave door edge
```

In the current code names:

- `LocationSpec` is the WorldLocationNode spec.
- `ExitSpec` / `ConnectionSpec` is the WorldTransitionEdge spec.

## Interior Nodes

An enterable interior is now represented as a world location node with:

- `location_kind: interior`
- `parent_location_id`
- optional `parent_object_id`
- normal source fields such as `source_type`, `scene_path`, `data_path`, and
  `generator_id`

Furniture, beds, counters, boxes, work points, room regions, and NPC anchors are
not world nodes. They remain content inside the loaded location.

`data/worlds/test_world.json` no longer preloads a hand-authored building
interior row. The test world starts with only the exterior village and wild
plain nodes. Building interiors are imported after `test_village` is
materialized and its generated manifest is available.

The existing `BuildingInteriorGenerator` and generic interior scene still own
the actual interior content. The world registry passes the generation context to
that generator; it does not create a second interior-generation system.

When a generated exterior location is materialized, `WorldLocationRegistry`
also imports that location's generated `interiors` and `transitions` manifests
back into `WorldLocationGraph`. This keeps the world graph aligned with the
actual generated building instances instead of relying on hand-authored fixture
rows. If the generated village creates any number of enterable buildings, each
building that publishes an interior manifest becomes a child location with
enter/leave door edges.

## Door Edges

Generated exterior building doors now receive a generic `world_exit_id` derived
from the building interior id:

```text
<interior_location_id>.enter
```

Generated interior return doors receive:

```text
<interior_location_id>.leave
```

`LocationRoot` handles both grid exits and object-door exits through the same
world transition entry point when a world is active. If no world is active, or
if a legacy object lacks `world_exit_id`, the old `target_scene_path` fallback
continues to work for compatibility. If a stale world edge fails but the object
still has a legacy scene target, the failure is warned and the legacy route is
used rather than trapping the player at the door.

The generated door edges are derived from each building manifest:

```text
<interior_location_id>.enter
  exterior location -> interior location / entry_spawn_id

<interior_location_id>.leave
  interior location -> exterior location / return_spawn_id
```

The inside spawn maps to the generated interior entrance named by
`entry_entrance_id`. The outside spawn maps to the generated village return
entrance named by `return_entrance_id`. These ids are emitted by the generated
building/interior manifests rather than guessed by the world graph.

## Graph Queries

`WorldLocationGraph` and `WorldTransitionService` now support:

- `get_location`
- `get_child_locations`
- `get_edges_from`
- `get_edges_to`
- `get_parent_location_id`
- `is_child_location`
- `get_world_debug_summary`

This lets debug and future UI treat interiors as child nodes instead of a flat
list of unrelated locations.

## Save Behavior

v64 already stores the world runtime state in saves. v64.1 keeps interiors in
the same runtime registry as other locations, so `current_location_id` can be an
interior id. On load, the world service can prepare the current interior's
location data before `SceneLoader` instantiates the generic interior scene. The
saved world data is taken from the live graph, including generated child
interior specs and door edges, so restoring inside a generated interior does not
lose the dynamic graph rows.

NPC schedule settlement now refuses to store empty `grid_position` rows. This
prevents unresolved schedule anchors from later overriding a valid schedule
target and spawning a merchant or other NPC at `(0, 0)`.

## Boundaries

v64.1 does not:

- convert furniture, anchors, or room regions into world nodes;
- split every room into its own location;
- rewrite generated settlement or interior generation;
- build dungeon/special location behavior;
- add a world map UI;
- change wild terrain, battle, or visual terrain work.

Generated settlement buildings now register child interior location specs plus
enter/leave edges when their exterior location data is materialized. This is
still limited to the existing generated building interior model; dungeon/special
locations remain out of scope.

## Validation

The phase was validated against:

- `test_world` does not preload hand-authored generated building interiors;
- `test_village` imports generated child interiors after materialization;
- enter and leave door edges resolve through the world graph;
- required interior and exterior spawns come from generated manifest ids;
- `WorldTransitionService` can transition from exterior to interior and back;
- every generated building door with `world_exit_id` has a graph edge;
- every generated building interior can round-trip through enter and leave
  world edges;
- generated interior context stays aligned with the source building archetype;
- generated entry and return spawn ids survive save-state restore;
- merchant shop schedule entries resolve to the shop interior `primary` anchor;
- offscreen schedule settlement does not produce empty `grid_position` states;
- restored save state keeps generated interior graph rows;
- transition summaries include `transition_type`, `target_location_kind`, and
  `parent_location_id`;
- generated interior data is registered in runtime state;
- the generated interior return door carries the leave `world_exit_id`;
- invalid interior target spawn ids fail clearly.
