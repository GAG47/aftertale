# Phase 58: Prefab Exterior Presentation

## Status

Complete.

## Goal

Phase 57 established parcels, generated building instances, generated
interiors, and placeholder building prefab contracts. Phase 58 connects those
contracts to the exterior presentation layer without turning the village into a
random decoration pass.

The purpose of this phase is to make the generated village read less like a
debug wall layout while preserving the architecture needed for future art
prefabs:

- the generator chooses parcel, prefab, footprint, south door slot, and front
  clearance;
- the renderer presents those choices through temporary placeholder facades;
- exterior content remains explicit prefab data, not archetype guesswork or
  global empty-space filling.
- prefab definitions live in data and can later bind to art assets without
  changing the BSP placement logic.

## v58.1 Building Prefab Placeholder Renderer

Added a temporary exterior renderer for generated building prefab placeholders.
The generator emits a `building_prefab_placeholder` structure for each concrete
building instance. This structure does not block movement and does not replace
the actual wall ring or interactive door. It only gives the current placeholder
buildings a clearer exterior face.

The renderer now uses the building's `zone_type` to choose temporary facade
treatment:

- residential buildings use calmer wall tones and window placement;
- shops get a compact sign and window treatment;
- workshops get rougher service markings;
- taverns get a distinct sign board;
- storage and guard buildings get simpler utilitarian markings.

This is still not final art. It is a visualization of the prefab contract so
that the generated village can be inspected while the real art prefab library is
not ready.

The placeholder renderer no longer chooses facade treatment directly from
`zone_type`. It reads the selected prefab's `visual` contract instead:

- `render_kind`;
- `asset_id`;
- `placeholder_style`;
- `wall_palette`;
- `roof_palette`.

The current `asset_id` values are intentionally empty. This keeps the pipeline
ready for real art while allowing the placeholder facade renderer to remain the
fallback presentation path.

## v58.2 Parcel Surface And Yard Policy Presentation

The generator now emits parcel presentation overlays for each building:

- `parcel_surface`: the whole generated parcel footprint;
- `front_clearance`: the required south-side clear area between the door and
  road access;
- `building_foundation`: the actual prefab footprint inside the parcel.

These overlays are presentation-only. They do not change collision, pathing,
anchors, schedules, exits, or object interaction.

Yard policy remains a contract, not an automatic prop generator. A parcel can
say that it has a clear frontage, a small residential yard, a farmyard, or a
workshop service yard. Phase 58 only visualizes that reserved space. It does
not scatter barrels, benches, worktables, outdoor tavern seating, or shop
crates based on broad building type assumptions.

Parcel presentation is now split into game and debug layers:

- debug: `parcel_surface` and `front_clearance`;
- game: `front_path` and `building_foundation`.

The large parcel rectangle is therefore a debug aid, not the normal player-facing
village presentation. The default renderer shows the game layer and hides the
debug parcel bounds.

## v58.3 Exterior Slot Contract Finalization

The placeholder prefab library now gives each prefab an explicit exterior slot
contract:

- `schema_version`;
- `coordinate_space = prefab_local_grid`;
- `content_source = prefab_declared_only`;
- `requires_clearance_validation = true`;
- `exterior_slots`.

The placeholder prefabs now declare a small number of explicit exterior slots.
These are still temporary visual slots, but they prove the final direction:
outdoor content comes from prefab declarations, not from a global post-process
that tries to infer what every building should have outside.

The concrete generated building instance copies the selected prefab contract.
This keeps the future art handoff instance-based:

```text
parcel
-> selected prefab contract
-> concrete building instance
-> explicit exterior slots
-> renderer / object placement
```

## v58.4 Building Prefab Catalog

The building prefab library was moved out of `VillageBspGenerator` and into
`data/generation/building_prefabs.json`.

The generator now loads that catalog through `BuildingPrefabCatalog` before BSP
placement starts. The generator no longer owns the list of prefab sizes, door
offsets, roof palettes, placeholder styles, or exterior slot declarations. It
only asks the loaded catalog for compatible candidates.

Generated village data records:

- the source `building_prefab_catalog`;
- the resolved `building_prefabs`;
- the selected `prefab_id` on each building;
- the copied `prefab_contract` on each concrete building instance.

This makes the future art handoff data-driven. Adding or replacing a building
prefab should be a catalog change, not a generator rewrite.

## v58.5 Exterior Slot Materialization

The generator now materializes prefab-declared exterior slots into concrete
presentation entries.

Each slot declares:

- local prefab-grid position;
- slot kind, such as `structure` or `floor_decoration`;
- render type, such as `flower_pot`, `material_crates`, or `sign_badge`;
- placement layer, such as `yard` or `facade`;
- non-blocking gameplay flags.

During placement, the generator transforms local prefab-grid coordinates into
world grid coordinates and validates the result:

- the slot must stay inside the map;
- it must not occupy the door or doorstep;
- yard slots must fall inside the selected yard bounds;
- non-facade slots must not sit inside the building footprint;
- slots must not reserve or block gameplay cells.

The concrete building instance records `materialized_exterior_slots`, so the
generated result can be inspected against the prefab declaration.

## v58.6 Asset Binding Boundary

Phase 58 does not require final building images. Instead, it establishes the
asset-binding boundary:

```text
prefab.visual.asset_id
-> prefab visual contract
-> renderer chooses asset path or placeholder fallback
```

At this stage the placeholder renderer is the fallback for empty `asset_id`
values. Later art resources can be bound by filling the catalog's visual fields
without changing parcel scoring, building placement, NPC schedule targets, or
door/interior transitions.

## Contract Rules

- Ordinary generated buildings still require south-facing doors.
- Parcel data records the door slot and road anchor; it does not choose door
  direction.
- Placeholder facade drawing is separate from blocking wall structures.
- Parcel and yard overlays are visual-only.
- Exterior props must come from prefab-declared slots.
- Exterior slots are non-blocking in v58.
- Normal gameplay rendering hides debug parcel rectangles by default.
- Gameplay identity remains the concrete building instance id and interior
  location id, not a building type string.

## Validation

The generator contract validation now checks:

- parcels keep south door slots and road anchors;
- prefabs keep south doors;
- prefabs declare `content_source = prefab_declared_only`;
- prefabs declare visual placeholder contracts;
- prefab exterior slots use prefab-local coordinates and do not block gameplay;
- buildings copy a prefab exterior slot contract;
- buildings materialize all declared exterior slots;
- each generated building receives parcel, front-clearance, and foundation
  presentation overlays.

The smoke test also checks the same v58 invariants so the prefab presentation
contract cannot silently disappear while the village still loads.

## Verification

- `git diff --check` passes.
- `tools/validation/validate_locations.ps1` passes.
- Godot 4.6.3 completes a headless main-scene startup with the generated
  village loaded.

The standalone smoke script has been updated with the v58 assertions, but this
local Godot build still crashes when launching one-off scripts through the CLI.
The stable verification path remains the default headless startup plus the
generator's startup contract validation.
