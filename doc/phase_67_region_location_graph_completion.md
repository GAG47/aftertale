# Phase 67 Region Location Graph Completion

Phase 67 completes the Region -> Location Graph structural compiler line.

The completed path is:

```text
RegionInput
-> SemanticRoleResult
-> Location nodes
-> Edge contracts
-> LocationGraphSnapshot validation
-> snapshot save/load
-> RegionGraphRuntimeService
```

It does not generate scenes, tile maps, scene exits, world-frame samples, or
cross-region networks.

## v67.3 Location Nodes

`LocationNodeExpander` converts every semantic role into a structural Location
node using the active `RegionTypeProfile`.

Location node ids use:

```text
loc.<scope>.<region_type>.<region_slug>.<role_slug>.ln_####
```

Location types are not hard-coded in the expander. They come from the role
definition in the profile, and every profile must declare
`supported_location_types`. A role without a supported `location_type` fails
instead of receiving a default type.

## v67.4 Edge Contracts And Validation

`EdgeContractGenerator` reads profile `connection_rules` and produces structural
edge contracts. External connection intents are bound through the profile's
`external_connection_anchor_role_type`.

Each edge contract includes:

```text
edge_id
from_location_id
to_location_id
from_role_id
to_role_id
travel_type
direction_hint
access_rule
exit_style
bidirectional
edge_source
source_intent_id
```

`RegionLocationGraphValidator` rejects malformed graphs. It checks:

- required graph fields;
- duplicate role, location, and edge ids;
- unknown edge endpoints;
- unknown role references;
- illegal `travel_type` and `access_rule`;
- duplicate location edge pairs;
- graph connectivity from `start_location_id`;
- external connection intents without a boundary location;
- scene-only fields such as `scene_path`, `spawn_id`, `tilemap`, and
  `target_scene_path`.

The validator does not repair graphs.

## v67.5 Snapshot Save/Load

`RegionGraphSnapshotStore` saves a validated graph snapshot to JSON and validates
again after load.

The main startup path saves the compiled snapshot to:

```text
user://region_graph_snapshots/default_region_graph.json
```

Then it loads the same snapshot back before runtime registration. Runtime does
not consume the compiler's transient in-memory result directly.

## v67.5 Runtime Adapter

`RegionGraphRuntimeService` is an autoload service that loads a
LocationGraphSnapshot and exposes:

- `start_graph()`;
- `enter_location()`;
- `travel_by_edge_id()`;
- `get_location()`;
- `get_edges_from()`;
- `get_adjacent_locations()`;
- `validate_location_reference()`;
- `validate_location_references()`;
- `get_save_state()`;
- `apply_save_state()`.

New game startup now compiles, saves, reloads, and registers the Region graph,
then starts the game session and enters the graph `start_location_id`.

`SaveManager` includes the Region graph runtime snapshot under:

```text
region_graph
```

When no playable Scene is loaded, the v67 path can still save and load a
graph-only game state. Graph-only saves store an empty `scene_path` and restore
the current location through `RegionGraphRuntimeService.enter_location()`
instead of pretending a Scene exists.

Player, NPC schedule, and quest location references are validated against the
active LocationGraphSnapshot before graph saves and graph loads complete.
Invalid references fail explicitly.

The normal UI now has a graph-only runtime panel for v67 structural locations.
When no playable Scene is loaded, the panel reads the active snapshot, displays
the current Location node and available Edge Contracts, and travels through
`RegionGraphRuntimeService.travel_by_edge_id()` when the player selects an
exit. This is a structural graph view, not Scene generation.

## Explicitly Not Supported Yet

Phase 67 still does not implement:

- Location Scene generation;
- Scene exit materialization from Edge Contracts;
- visual map loading for these new Location nodes;
- World Frame semantic sampling;
- cross-region graph stitching;
- authored NPC schedules or quest content for generated Location ids.

Those are later systems. Phase 67 owns the structural graph, not the playable
scene layer.

## Verification

Verified with default project startup:

```text
Godot --headless --path D:\godotproject\aftertale --quit-after 2
```

The command exits without Region compiler errors, which means startup completed
the compile -> snapshot save -> snapshot load -> runtime graph load path.

Additional smoke coverage lives at:

```text
scripts/tests/v67_region_location_graph_completion_smoke.tscn
```

It checks town and forest graph compilation, validator failures, snapshot
save/load, runtime start, graph travel, direct location entry, adjacent-location
queries, location-reference validation, and graph-only SaveManager save/load.
Because direct `--scene` and `--script` launches crash in this local Windows
Godot build before project code runs, the smoke was verified by temporarily
setting `run/main_scene` to the smoke scene, running the same headless default
startup command, and restoring the normal boot scene afterward.

The smoke run printed:

```text
v67 Region Location Graph completion smoke test passed
```
