# Phase 67.2 Semantic Role Expansion

Note: v67.7 supersedes the original `required_roles` and
`optional_role_pool` input contract. This file remains the historical v67.2
record; the current main path uses the demand contract documented in
`doc/phase_67_7_region_demand_contract.md`.
v67.8 additionally moves role definitions from `RegionTypeProfile` into the
global `SemanticRoleLibrary`.

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

New game startup still enters through `RegionLocationGraphCompiler`. This phase
made semantic role expansion a real compiler stage:

```text
compile_semantic_roles_result(input)
-> SemanticRoleResult
```

The full `compile_to_location_graph_result()` boundary has since advanced in
v67.3. The semantic role result remains independently testable through
`compile_semantic_roles_result()`.

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
- SemanticRoleResult containing Location Graph fields such as `location_id`,
  `edge_id`, `scene_path`, `spawn_id`, or `target_location_id`.

The compiler does not add missing roles to make invalid input pass.

## Explicitly Not Supported In v67.2

v67.2 does not implement:

- role to Location node expansion;
- Edge Contract generation;
- Graph Validator;
- Graph Snapshot save/load;
- runtime adapter travel through the new graph;
- scene generation or scene exits.

v67.3 implements the next Location Nodes stage and moves the full graph boundary
forward to v67.4 Edge Contracts.

## Verification

Verified with default project startup:

```text
Godot --headless --path D:\godotproject\aftertale --quit-after 2
```

The semantic-role smoke test reaches a valid `SemanticRoleResult`. Current full
startup now reaches v67.3 Location Nodes and fails at the expected v67.4
boundary instead of loading any old world graph.

Additional capability coverage lives at:

```text
scripts/tests/v67_2_semantic_role_expansion_smoke.tscn
```

The smoke test checks town and forest RegionInputs, same-seed reproducibility,
different-seed optional role variation, invalid input failures, semantic-only
result fields, and the current Location Graph boundary. On this local Windows
Godot build, direct `--scene` and `--script` test launches still crash in the
engine before project code runs, so the default startup path is the executable
verification used here.
