# Phase 67.1 RegionInput Compiler Entry

v67.1 starts the Region -> Location Graph compiler line without pretending the
full graph compiler exists yet.

## Main Path Rule

New game startup no longer calls `WorldGraphGenerator` directly. It now loads a
RegionInput document and sends it to `RegionLocationGraphCompiler`.

If RegionInput is missing, invalid, or cannot yet compile to a Location Graph,
startup fails explicitly. It does not load `test_world.json`, does not generate a
v65 world as a fallback, and does not start a fixed demo loop.

## RegionInput Schema

`RegionInput` validates the reusable input contract for later compiler stages:

- `region_id`
- `region_slug`
- `display_name`
- `region_type`
- `seed`
- `coarse_context`
- `required_roles`
- `optional_role_pool`
- `external_connection_intents`

Region ids must use:

```text
region.<scope>.<region_type>.<slug>.rg_####
```

The display name is not the id. It can change for presentation and localization;
the region id is the stable structural reference.

## Compiler Entry

`RegionLocationGraphCompiler` currently exposes two real entry points:

- `validate_region_input_result(input)`
- `compile_to_location_graph_result(input)`

The first validates RegionInput and returns concrete schema errors. The second
validates RegionInput, then fails at the explicit v67.2 boundary:

```text
semantic role expansion is not implemented
```

This is intentional. v67.1 does not emit placeholder roles, fake Location nodes,
or a default graph.

## Removed Old Fixture

`data/worlds/test_world.json` was deleted from main data. The main path no
longer contains the old `test_village -> test_wild_plain` graph fixture.

Older location data and older tests may still exist where they are direct test
or scene-generation assets, but they are not the new-game world graph source.

## Explicitly Not Supported Yet

v67.1 does not implement:

- semantic role selection;
- role to Location node expansion;
- Edge Contract generation;
- Graph Validator;
- Graph Snapshot save/load;
- runtime adapter travel through the new graph.

Those belong to v67.2 through v67.5. If code reaches those boundaries now, it
must fail clearly instead of silently substituting an older world path.

## Verification

Verified with default project startup:

```text
Godot --headless --path D:\godotproject\aftertale --quit-after 2
```

The startup reaches the new Region compiler entry and fails with the expected
v67.2 boundary message instead of loading an old world graph.

Additional smoke coverage lives at:

```text
scripts/tests/v67_1_region_input_compiler_entry_smoke.tscn
```

On this local Windows Godot build, direct `--script` and `--scene` test launches
crashed in the engine before project code ran, while normal project startup
completed and reported the expected compiler-boundary error.
