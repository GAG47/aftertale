# Phase 67.3 Location Nodes

v67.3 advances the Region compiler by exactly one structural step:

```text
SemanticRoleResult
-> LocationNodeProfile
-> LocationNodeResult
-> validation
```

It does not generate edges, scenes, spawns, tile maps, snapshots, runtime travel,
or graph connectivity.

## Main Path Rule

`RegionLocationGraphCompiler` now exposes:

```text
compile_semantic_roles_result(input)
compile_location_nodes_result(input)
compile_to_location_graph_result(input)
```

`compile_location_nodes_result()` first produces a valid `SemanticRoleResult`,
then expands it into a valid `LocationNodeResult`.

`compile_to_location_graph_result()` now runs through v67.3 and stops at the
next boundary:

```text
v67.4 edge contract generation is not implemented
```

The failure payload includes the valid `LocationNodeResult`.

## LocationNodeProfile

Role-to-location mapping is data-driven through:

```text
data/regions/location_node_profiles/town_region.json
data/regions/location_node_profiles/forest_region.json
```

Each rule maps one semantic `role_type` to one `location_type`, node tags, and a
boundary flag. v67.3 only supports:

```text
count: 1
```

Any other count fails. The compiler does not generate multiple nodes from one
semantic role.

## LocationNodeResult

The v67.3 output is `LocationNodeResult`.

It records:

```text
schema_version
compiler_version
stage
region_id
region_type
region_slug
seed
source_hash
semantic_role_source_hash
location_nodes
role_node_bindings
debug_summary
```

Each location node records:

```text
location_id
location_type
node_slug
source_role_id
source_role_type
source_role_slug
node_source
node_tags
is_boundary
is_hidden
is_required
```

Every node must trace back to exactly one semantic role through
`source_role_id`. Node ids use:

```text
loc.<scope>.<region_type>.<region_slug>.<node_slug>.ln_####
```

`node_slug` is strict:

```text
role_slug exists -> use role_slug
otherwise -> use role_type
duplicate node_slug -> fail
```

The compiler does not silently create `*_2`, `*_copy`, or other repaired slugs.

## Validation Rules

`LocationNodeResultValidator` rejects:

- missing or malformed required result fields;
- `locations` instead of `location_nodes`;
- missing source role references;
- duplicate `location_id`;
- duplicate `node_slug`;
- unsupported role mappings;
- `location_type` values that do not match the active `LocationNodeProfile`;
- next-stage fields such as `edge_id`, `scene_path`, `spawn_id`, `tilemap`,
  `target_location_id`, `target_region_id`, and `start_location_id`.
- external connection artifacts such as `external_connection_bindings`,
  `external_connection_intents`, `source_intent_id`, `boundary_location_id`,
  `intent_id`, `direction_hint`, `travel_type`, `exit_style`, and `access_rule`.

The validator only rejects invalid results. It does not add missing nodes or
repair malformed bindings.

## Explicitly Not Supported Yet

v67.3 does not implement:

- node-to-node connections;
- Edge Contracts;
- graph connectivity;
- scene exits;
- player travel;
- snapshot save/load;
- runtime graph registration.

Those belong to v67.4 and later.

## Verification

Capability coverage lives at:

```text
scripts/tests/v67_3_location_nodes_smoke.tscn
```

The smoke test checks town and forest location node expansion, same-seed
stability, forced role slug behavior, absence of external connection artifacts,
invalid profile and mapping failures, validator rejection of duplicate slugs and
next-stage fields, and the explicit v67.4 boundary.
