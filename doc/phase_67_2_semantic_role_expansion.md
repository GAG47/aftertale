# Phase 67.2 Semantic Role Expansion

v67.2 moves the Region compiler one real stage forward:

```text
RegionInput
-> RegionTypeProfile
-> SemanticRoleResult
-> validation
```

It still does not create Location nodes, edges, scenes, spawns, snapshots, or a
runtime graph.

## Main Path Rule

New game startup still enters through `RegionLocationGraphCompiler`, but the
compiler now performs real semantic role expansion before failing at the next
unsupported boundary:

```text
v67.3 role-to-location-node expansion is not implemented
```

Startup no longer starts `GameState`, resets party state, or unpauses time before
the Region compiler has succeeded. This avoids the v67.1 half-started empty
world state.

## RegionInput Update

`RegionInput` now requires:

```text
forced_role_specs
```

The field may be an empty array, but it must exist. Forced roles are input facts,
not compiler fallbacks. A forced role spec must provide:

```text
role_type
role_slug
```

It must not provide `role_id`; role ids are compiler output.

## Region Type Profiles

Role rules are data-driven through:

```text
data/regions/region_type_profiles/town_region.json
data/regions/region_type_profiles/forest_region.json
```

Each profile defines:

- supported required role types;
- supported optional role types;
- an external-intent role type;
- per-scale optional role count ranges;
- optional role weights;
- coarse-context weight modifiers;
- role tags, allowed role sources, and multiplicity rules.

Unsupported region types fail because their profile is missing. Unsupported
roles fail against the profile instead of being replaced with a supported role.

## SemanticRoleResult

The v67.2 output is `SemanticRoleResult`.

Each result records:

```text
schema_version
compiler_version
stage
region_id
region_type
region_slug
seed
source_hash
selected_roles
external_connection_intents
debug_summary
```

Each semantic role records:

```text
role_id
role_type
role_slug
role_source
role_tags
```

Role ids use:

```text
role.<scope>.<region_type>.<region_slug>.<role_slug>.rr_####
```

## Validation Rules

v67.2 validates and rejects:

- missing profile-required roles;
- unsupported region types;
- unsupported required, optional, or forced role types;
- duplicate required or optional role types in RegionInput;
- forced roles that try to provide compiler-owned `role_id`;
- external connection intents missing `intent_id`, `direction_hint`,
  `travel_type`, or `exit_style`;
- SemanticRoleResult containing Location Graph fields such as `location_id`,
  `edge_id`, `scene_path`, `spawn_id`, or `target_location_id`.

The compiler does not add missing roles to make invalid input pass.

## Explicitly Not Supported Yet

v67.2 does not implement:

- role to Location node expansion;
- Edge Contract generation;
- Graph Validator;
- Graph Snapshot save/load;
- runtime adapter travel through the new graph;
- scene generation or scene exits.

`compile_to_location_graph_result()` includes the valid `SemanticRoleResult` in
its failure payload, then stops at the v67.3 boundary.

## Verification

Verified with default project startup:

```text
Godot --headless --path D:\godotproject\aftertale --quit-after 2
```

The startup reaches a valid SemanticRoleResult and fails at the expected v67.3
boundary instead of loading any old world graph.

Additional capability coverage lives at:

```text
scripts/tests/v67_2_semantic_role_expansion_smoke.tscn
```

The smoke test checks town and forest RegionInputs, same-seed reproducibility,
different-seed optional role variation, invalid input failures, semantic-only
result fields, and the v67.3 Location Graph boundary. On this local Windows
Godot build, direct `--scene` and `--script` test launches still crash in the
engine before project code runs, so the default startup path is the executable
verification used here.
