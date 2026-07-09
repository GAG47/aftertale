# Phase 65: Local World Graph Generator

## Status

Complete as v65.

## Goal

v65 adds a local world graph generator. It creates a seed-driven set of world
location nodes, spawn points, and world transition edges, then feeds that data
into the existing v64 world graph and transition service.

This is not a world map UI, not a hand-authored `test_village ->
test_wild_plain` fixture, and not a second scene transition system.

## Terms

The documentation uses these terms:

- `WorldGraph`: the world graph.
- `WorldLocationNode`: a world location node.
- `WorldTransitionEdge`: a world transition edge.
- `SpawnPoint`: an entry or spawn point inside a location node.
- `LocationData`: the concrete scene data materialized for a node.

The current code still uses earlier names in some places:

- `WorldLocationSpec` is a world location node spec.
- `ExitSpec` / `ConnectionSpec` is a world transition edge spec.

## New Files

- `scripts/systems/world/world_generation_profile.gd`
- `scripts/systems/world/world_graph_blueprint.gd`
- `scripts/systems/world/world_graph_generator.gd`
- `scripts/systems/world/world_graph_compiler.gd`
- `data/world_generation_profiles/temperate_frontier.json`

## Generation Flow

The generator entry point is:

```gdscript
var generator := WorldGraphGenerator.new()
var world_data := generator.generate_world_data({
	"world_id": "generated_test_world",
	"world_seed": 6501,
	"region_profile_id": "temperate_frontier",
})
```

It can also return a `WorldGraphBlueprint`:

```gdscript
var blueprint := generator.generate_blueprint(config)
```

The generated result contains:

- `world_id`
- `world_seed`
- `region_profile_id`
- `start_location_id`
- `start_spawn_id`
- `locations`
- `spawns`
- `exits`
- `generator_metadata`
- `debug_summary`

The compiler validates the blueprint and builds the existing v64 graph type:

```gdscript
var compiler := WorldGraphCompiler.new()
var result := compiler.compile_to_graph(blueprint)
```

## Region Profile

The first profile is:

```text
data/world_generation_profiles/temperate_frontier.json
```

It describes tendencies, not fixed requirements:

- node count range;
- start location policy;
- candidate location kinds;
- candidate wild profiles;
- kind/profile weights;
- connection density;
- branchiness;
- generated wild size candidates.

The available wild profiles are a candidate pool. The generator does not
contain rules such as `required_riverbank`, `ensure_foothill`, or
`ensure_all_profiles_visible`.

For the first validation profile, non-start nodes are generated wild nodes so
the world graph generator can be tested against the existing v62/v63 wild
materialization path. This is a profile choice, not a generator requirement.

## Graph Shape

The generator:

1. seeds an RNG from `world_seed` and `region_profile_id`;
2. samples node count from the profile range;
3. creates a start node using the configured start policy;
4. samples remaining node kinds and wild profiles from weighted candidate pools;
5. creates a connected tree skeleton;
6. adds extra edges based on `connection_density`;
7. creates paired directed transition edges for each undirected connection;
8. creates spawn points for edge targets;
9. emits a debug summary.

The graph is not forced to be a line, a loop, or a fixed demo chain.

## Start Policy

The first implemented start policy is `static_test_village`.

That policy uses the existing `test_village` scene and `plaza` entrance as the
start node so the current project remains playable and testable. The generated
world around it is still seed-driven; the generator does not hard-code
`test_village -> test_wild_plain`.

Generated-settlement starts remain a future integration point.

## Generated Wild Nodes

Generated wild nodes still materialize through the existing v64 flow:

```text
WorldTransitionService
-> WorldLocationRegistry
-> WildLocationCompiler
-> WildTerrainGenerator
```

The world graph generator only creates the node spec, seed, profile, size,
spawn points, and transition edges.

When a generated wild node is materialized, `WorldLocationRegistry` converts the
node's outgoing world edges into wild exit hints. The wild compiler uses those
hints to pick passable exit cells and writes the matching `world_exit_id` into
the location exits. This makes generated graph edges visible inside generated
wild scenes without making the terrain generator know about villages or world
structure.

Entering a generated wild node for the first time materializes it. Entering it
again reuses runtime data.

## Save Behavior

Generated world graph data goes through the existing save path:

- `WorldTransitionService.get_save_state()` stores the live graph data;
- generated `LocationData` is stored in `WorldRuntimeState`;
- restoring save state rebuilds the graph and preserves generated edges.

v65 does not add a separate save system.

## Debug Summary

The generated graph includes:

- `world_id`
- `seed`
- `region_profile_id`
- `node_count`
- `edge_count`
- `location_kind_counts`
- `wild_profile_counts`
- `connected`
- `start_location_id`
- `generated_node_ids`
- `generation_warnings`

## Boundaries

v65 does not:

- build a world map UI;
- require every world to contain plain, forest edge, riverbank, or foothill;
- force a loop;
- force a fixed chain;
- rewrite wild terrain generation;
- rewrite settlement generation;
- add a second transition service;
- make generated settlements fully materialize as external nodes yet.

Interior child nodes from v64.1 continue to hang from their parent exterior
locations after those locations are materialized.

## Validation

The phase was validated against:

- region profile loading through the generator;
- same seed produces the same graph signature;
- different seed produces a different graph signature;
- node count is inside the profile range;
- the graph is connected;
- location node ids are unique;
- transition edge ids are unique;
- edge targets and target spawns resolve;
- generated wild nodes have profile, seed, and size;
- the generated result compiles into `WorldLocationGraph`;
- `WorldTransitionService` can load the generated graph;
- a generated wild edge can be traversed;
- first generated wild entry materializes location data;
- second generated wild entry reuses runtime data;
- generated wild exits carry `world_exit_id`;
- restored save state keeps generated graph edges.
