# Phase 56: BSP Village Generation

Note: Phase 60 supersedes BSP as the active village layout authority. This file
remains the historical record for the first generated-village implementation.

## Status

Complete.

## Goal

Replace the hand-authored test village layout with a deterministic BSP-driven
town generator while moving gameplay placement away from hard-coded map
coordinates.

The important contract for this phase is not only that `tiles` are generated.
The generated town must also provide the semantic anchors that NPC schedules,
facilities, exits, and training encounters use at runtime.

## Generator Shape

Added `scripts/systems/scenes/village_bsp_generator.gd`.

The generator reads a compact location definition with:

- location id and display name;
- tile size;
- generator type;
- seed;
- map size.

It then produces the complete location dictionary expected by the existing
runtime:

- `tiles`
- `terrain`
- `zones`
- `floor_decorations`
- `structures`
- `roofs`
- `entrances`
- `anchors`
- `exits`
- `shops`
- `objects`
- `characters`
- `state`

`LocationRoot` now detects `generator.type == "village_bsp"` and asks the
generator for the final location data before constructing `LocationGrid`.
Static locations still load exactly as before.

## BSP Layout and Scored Placement

The generator splits the available town rectangle into BSP leaves and assigns
them to village roles. BSP only creates candidate parcels; the generator then
scores those parcels before committing a district or building template.

The plaza reserves the most central parcel first. The remaining district
parcels are scored by their role:

- farm: favors large west/edge parcels and is kept out of main street routing;
- training yard: favors edge parcels with room for combat props;
- wilderness gate: favors an eastern edge parcel for the scene transition.

Buildings are selected from a template pool and scored against the remaining
parcels. The current pool contains:

- residence;
- workshop;
- shop;
- tavern;
- farmer cottage;
- worker cottage;
- storage shed;
- guardhouse.

The building score combines parcel area with role preferences:

- plaza frontage for shop and tavern;
- reachable work-street access for workshop;
- farm adjacency for farmer cottage and storage shed;
- gate adjacency for guardhouse;
- quiet edge placement and residential clustering for homes.

Ordinary building templates have fixed down-facing doors. Candidate parcels are
rejected before scoring if their down-facing frontage cannot produce an in-bounds
doorstep. The generator does not rotate normal houses, shops, taverns,
workshops, cottages, or sheds to fit a parcel. Future special templates can opt
into a different orientation explicitly, but regular town buildings must follow
the art-facing rule.

Each selected parcel is recorded in `generation_summary.placement_log` with
the role, leaf bounds, and score reason. This gives future debugging a direct
answer to why a building landed in a specific parcel.

Each role owns its own placement template. Buildings generate their floor
tiles, wall ring, door opening, windows, roof, facility object, and semantic
anchor. Outdoor districts generate their ground tiles, props, anchors, and
encounter objects.

Roads connect the plaza to generated frontage points: down-facing building
doorsteps, the farm access cell, the training yard edge, and the wilderness
exit. Road carving uses a weighted route search and treats building footprints
and farm interiors as blocked road cells. This prevents roads from cutting
through field plots or through a building body to reach a rotated side/back
door.

Building interiors are reached through their generated door cells. As of the
Phase 57 architecture pass, normal building targets are no longer represented
by shared semantic anchor names in the exterior map. Each placed building owns a
stable building instance id, an exterior door anchor, and a generated interior
location id.

## Semantic Anchors

NPC schedules are now generated from produced scene data rather than
hand-authored cells. The generated villager and guard schedules only reference
anchors produced by the generator; they do not include author-supplied
`grid_position` values.

Generated anchors include:

- one exterior door anchor for each building instance, such as
  `b001.exterior_door`;
- `plaza_social_spot`
- `training_yard_guard_post`
- `wild_gate_guard_post`
- `field_work_spot`

Interior anchors are scoped by their generated interior location id and use
slot names such as `entry`, `exit`, and `primary`. The identity of an NPC target
is therefore the pair of concrete `location_id` and local `anchor_id`, not a
global English role name.

## Validation

The generator performs a contract check on its own output. It verifies that:

- the generated grid is valid;
- required anchors exist;
- anchors and activity cells are open;
- required anchors are reachable from the plaza entrance;
- inspectable and usable objects have at least one reachable interaction side;
- exits are reachable;
- NPC schedule entries reference generated anchors;
- generated schedules do not hand-author `grid_position`.

The contract exists because generated tiles alone are not enough. If a village
template places an NPC target under a counter, routes through a farm plot, or
creates an unreachable exit, startup reports the generator contract error
immediately.

The PowerShell data validator now recognizes generator-backed locations and
checks their compact generator configuration instead of requiring static tile
rows.

## test_village Update

`data/locations/test_village.json` is now a generator configuration instead of
a hand-built map. The existing `test_village.tscn` remains a reusable location
container with the same render layers.

This means the village scene still exercises the existing systems:

- player spawning at the plaza entrance;
- NPC schedule resolution through anchors;
- crafting workbench;
- shop counter;
- bed and tavern rest facilities;
- save point;
- farm pickup;
- training dummies;
- wilderness exit to `test_clearing`.

## Verification

- `tools/validation/validate_locations.ps1` passes.
- Godot 4.6.3 completes a headless main-scene startup with the generated
  village loaded.
- The generated village self-check reports no contract errors during startup.

## Notes

The local Godot editor build crashes when launching a one-off scene or script
from the command line with `--scene` or `--script`. The default project startup
path is stable and was used for verification. A standalone smoke script was
kept at `scripts/tests/v56_scene_generation_smoke.gd` for environments where
the Godot CLI script entry point works correctly.
