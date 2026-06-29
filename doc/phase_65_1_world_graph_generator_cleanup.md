# Phase 65.1 World Graph Generator Cleanup

v65.1 removes the fixture-driven minimum loop that leaked into v65. The world graph generator is now treated as the normal scene-flow source for a new game, not as a wrapper around `test_village -> test_wild_plain`.

## Main Path Rule

The normal world path no longer falls back to old fixtures.

- New game generation failure is a startup error.
- World graph load failure is a startup error.
- Start location materialization failure is a startup error.
- World transition failure does not continue through `target_scene_path`.
- Save loading under an active world requires the saved location to resolve through the world graph.

`target_scene_path` remains only for fully non-world legacy scene data and interior return compatibility. When the world graph is active, transition routing is owned by `WorldTransitionService`.

## Removed Fixture Coupling

`WorldGraphGenerator` no longer knows these fixture concepts:

- `test_village`
- `test_wild_plain`
- `wild_gate`
- `return_to_village`
- `plaza`

Generated nodes use generic world node ids. Generated edges use generic edge ids such as `edge_0001`. The start node is an ordinary graph node except for being the initial current location.

The default `temperate_frontier` profile now starts from `generated_wild`, which is the currently supported generated location kind. This is not a fixture loop; it is the first supported materializable node type.

## Unsupported Kinds

Unsupported location kinds fail explicitly. They are not silently replaced with `generated_wild`.

`generated_settlement` is still reserved but not materialized by the registry. The default profile does not emit it. If a profile gives it positive weight before support exists, generation fails instead of creating a fake node.

## Generated Wild

Generated wild locations now use `res://scenes/locations/generated_wild_location.tscn`, an empty location scene shell that receives pending generated data from the world service.

Generated wild world nodes do not point at `test_wild_plain.tscn` or `test_wild_plain.json`. Their location id, seed, size, profile id, spawns, and exits come from the world graph.

## Settlement Isolation

The old village generator may still use settlement-internal ideas such as a town edge gate zone or guard post for older settlement tests. It no longer writes a hardcoded exit to `test_wild_plain`.

Future generated settlements should expose world-edge anchors, then let the world graph bind external targets.

## Smoke Test Scope

The v65 smoke test now checks architecture properties instead of fixture ids:

- same seed produces the same graph;
- different seed changes the graph signature;
- node count stays within the profile range;
- graph validation and compilation succeed;
- node, edge, and spawn ids are unique;
- all edge endpoints and target spawns resolve;
- generated wild nodes carry generator profile, seed, width, and height;
- generated world data contains none of the old fixture tokens;
- the world service can start, transition, materialize generated wild once, and reuse it on second entry;
- unsupported `generated_settlement` fails explicitly.

Old fixture data can remain for legacy smoke tests, but it is no longer part of the generated world main path.
