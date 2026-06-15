# Phase 57: Exterior Doors and Generated Interiors

## Status

Complete.

## Goal

Phase 56 made the generated village usable as a gameplay skeleton. Phase 57
starts moving the village presentation away from exposed debug interiors and
toward exterior building composition.

The first step is to stop showing normal building interiors directly in the
main village scene. Exterior buildings now provide walls and an interactive
door. Entering a building is an explicit interaction, not a walk-over trigger,
so later locked-door rules can attach to the same object contract.

## Exterior Building Contract

Generated village buildings now keep their gameplay parcel, wall ring, and
down-facing frontage, but no longer paint interior floor tiles, roof overlays,
windows, sign badges, or role facilities into the outdoor scene.

For each building, the village generator creates:

- a blocking wall ring;
- a visible door structure;
- a blocking `LocationObject` on the door cell;
- a return entrance on the exterior doorstep;
- a stable building instance id such as `b001`;
- a concrete interior location id such as `test_village__interior_b001`;
- an exterior door anchor owned by that building instance;
- transition context carrying the building instance, archetype id, and interior
  location id.

The door object uses `facility_type = "scene_transition"` and points to the
shared generated interior scene shell. The scene shell is reusable presentation
infrastructure only; the gameplay identity is the generated interior
`location_id`, not the `.tscn` path or the template JSON id.

`archetype_id` is only used to choose temporary interior contents and, later,
prefab candidates. It is not used to resolve NPC schedules, ownership, or
building identity.

## Interior Transition

`SceneLoader` now carries two transient pieces of data:

- pending location context, used by the next generated scene;
- pending return location, used by an interior door to return to the exterior
  door that opened it;
- shared camera zoom, so switching between large exterior maps and small
  interiors does not change the player's current camera scale.

When the player interacts with an exterior door, `LocationRoot` stores the
current scene path and the generated exterior return entrance, passes the
building context to the next scene, and loads
`generated_building_interior.tscn`.

The interior return door uses `target_scene_path = "__return__"` so it can load
the stored return scene and entrance without hard-coding a specific exterior
building.

## NPC Indoor Scheduling

Generated village schedules now point at concrete building interior instances.
For example, a shopkeeping entry targets the generated location id for one
specific shop interior and the local `primary` anchor inside that location.

Cross-location walking no longer uses `building_kind` or `exterior_anchor_id`.
Each schedule entry that targets another location carries
`transition_anchor_by_location`, a map from source `location_id` to the anchor
the NPC must reach before leaving that source location. In the exterior village
this is the target building's exterior door anchor. Inside any generated
interior this is the local `exit` anchor.

When the player is already in the exterior village and an NPC schedule changes
from one interior instance to another, the exterior scene now creates a visible
travel segment. The character is spawned at the previous schedule entry's
exterior transition anchor, then the existing movement agent walks that
character to the current schedule entry's exterior transition anchor. Arrival
at the target door removes the character from the exterior scene and leaves the
NPC represented by the target interior schedule state.

This segment is only created when the schedule entry has just changed. If the
player enters the exterior long after an indoor-to-indoor schedule change, the
offscreen schedule state remains authoritative and the NPC is not replayed from
an old doorway.

This keeps schedule resolution instance-based:

- building type chooses content or future prefab candidates;
- building instance id identifies a placed building;
- interior location id identifies a specific indoor scene instance;
- local anchor id identifies a slot inside that specific location;
- transition anchors describe how a visible NPC leaves the currently loaded
  location before the character is removed from that scene.

## Generated Interior Scene

Added `scripts/systems/scenes/building_interior_generator.gd` and a shared
scene shell at `scenes/locations/generated_building_interior.tscn`.

The interior generator creates a small temporary room from the building
instance context:

- homes and cottages get a bed placeholder;
- workshops get a workbench;
- shops get a shop counter;
- taverns get a tavern rest counter;
- storage sheds get crates;
- guardhouses get guard equipment.

The template file `data/locations/generated_building_interior.json` is not a
world identity. Its id is `building_interior_template`, and the generator
overrides it with the concrete interior instance id from the door or registry
context.

This is still a functional placeholder, not the final art prefab system. The
important contract is that exterior buildings no longer expose their interior
contents in the main village scene, and facilities can move behind explicit
door interaction.

## Resolved Location Registry

`DefinitionLoader` now has a resolved-location layer for generated scenes:

- `load_resolved_location()` reads a location definition and materializes its
  generator output;
- generated villages register their building and interior manifests by
  concrete location id;
- `resolve_location_by_id()` can return generated interior data by instance id
  after the owning town has been materialized;
- NPC offscreen settlement uses resolved generated locations instead of raw
  JSON, so generated anchors and generated character rows are visible to the
  schedule system.

The registry is cleared with the normal definition cache so generated identity
does not survive across data reloads.

## v57.2 Parcel And Prefab Contract

The village generator now separates a placed building into three data layers:

- `parcel`: the generated lot that can receive a building;
- `building_prefab`: the placeholder contract used to choose a building shape;
- `building`: the concrete building instance created from a parcel and a
  prefab.

Ordinary building doors are fixed to the south side. The generator no longer
chooses a door direction from road position or target direction. Parcel data
records the eventual `door_slot` and `road_anchor` so later art prefabs can be
matched by door position, not by a direction decision made during placement.

Each parcel records:

- stable parcel id;
- source district/preference;
- lot bounds and buildable area;
- allowed archetypes;
- yard policy;
- south door side;
- generated door slot and road anchor after placement.

Yard policy is data, not decoration. It decides whether a prefab is allowed to
occupy a parcel shape; it does not automatically scatter props outside a
building.

## v57.3 Placeholder Prefab Library

The generator now carries a small placeholder prefab library under
`building_prefabs`. These entries are not final art assets. They define the
contract future art prefabs must satisfy:

- prefab id;
- archetype tags;
- footprint size;
- fixed south door side;
- door offset;
- required front clearance;
- allowed yard policies;
- interior template id;
- optional exterior slots.

The current exterior slots are intentionally empty. Outdoor objects must come
from explicit prefab slots later, not from a global empty-space decoration pass
or broad archetype assumptions.

## v57.4 Parcel To Prefab Placement

Building placement now follows this pipeline:

```text
building request
-> scored BSP leaf
-> parcel contract
-> compatible placeholder prefab candidates
-> selected prefab placement
-> building instance
-> interior instance
```

Prefab selection checks archetype tags, yard policy compatibility, footprint
fit, south door slot, and front clearance. The chosen prefab id and its
contract are copied onto the concrete building instance, while the parcel keeps
the generated footprint, door slot, road anchor, and yard bounds.

This completes the v57 scene-generation presentation foundation without adding
global random decoration. Exterior richness should now come from parcel policy
and explicit prefab slots in later art-facing work.

## Spawn Rules

Location entrance spawning now takes priority over saved runtime position when
a scene is loaded with an explicit `entrance_id`. Save-file restore still
applies its stored character state after loading, but normal scene transitions
spawn at the requested entrance. This keeps building entry and return stable.

## Camera Rules

Camera zoom is no longer derived from the current map size. Small interiors do
not force a larger minimum zoom to cover the whole map. The same min/max zoom
range applies to every location, and the current zoom value is stored on
`SceneLoader` so scene transitions preserve camera scale.

## Verification

- `tools/validation/validate_locations.ps1` passes.
- `git diff --check` passes.
- Godot 4.6.3 completes a headless main-scene startup with the generated
  village loaded and no generator contract errors.
