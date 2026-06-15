# Phase 60: Road-First Settlement Generation

## Status

Complete.

## Goal

Phase 60 replaces the BSP-led village layout core with a road-first settlement
generator.

The previous v56-v59 generator proved the scene-generation contracts: generated
buildings have stable identities, south-facing doors, generated interior
locations, prefab contracts, parcel debug presentation, and semantic anchors.
However, BSP was the wrong layout authority for natural villages. It created
areas first, then asked roads to repair connectivity afterward. That produced
scattered building islands and road shapes that read like connector artifacts
instead of village growth.

Phase 60 keeps the validated semantic contracts and replaces the layout order:

```text
road skeleton
-> frontage scan
-> street-facing lot scoring
-> parcel contract
-> prefab placement
-> semantic anchors
```

Roads now exist before lots. Ordinary buildings are only placed on lots scanned
from existing road frontage, so south-facing doors and front yards are part of
the candidate contract rather than a post-placement repair.

## Generator Rename

The current generator is now `VillageRoadGenerator` in
`scripts/systems/scenes/village_road_generator.gd`.

The generated location config now uses:

```json
{
  "generator": {
    "type": "village_road"
  }
}
```

The old `VillageBspGenerator` script and `village_bsp` generator type were
removed from the current code path. Historical phase logs still describe the
older implementation, but the active generator no longer uses BSP as its
settlement layout authority.

## Road Skeleton

The generator creates a deterministic road skeleton first:

- a main road crossing the settlement;
- constrained branch roads that form secondary lanes;
- a civic road area near the plaza;
- road-adjacent access to farm, training, gate, and building frontage.

The road skeleton is not a decoration pass. It is the input for later lot
allocation.

## Frontage Lots

After the road skeleton exists, the generator scans cells north of roads for
ordinary south-facing building lots.

Each candidate records:

- stable frontage lot id;
- rectangle bounds;
- south frontage side;
- road frontage cell;
- semantic zone id once selected.

The scanner rejects lots that overlap reserved functional areas such as the
farm, training yard, plaza, or gate. It does not use broad padding that would
erase all frontage in small maps.

## Building Placement

Building requests no longer compete for generic BSP leaves. They choose from
street-facing lots by score:

- shops and taverns prefer frontage near the civic road;
- workshops prefer visible work-street frontage;
- homes prefer quieter branch frontage and cluster with homes;
- farm-related buildings prefer farm-adjacent road frontage;
- guard buildings prefer the gate road frontage.

Prefab placement now snaps the south door to the selected frontage relation.
The building footprint is positioned so the prefab's front clearance sits
between the facade and the road, preserving the v57-v58 parcel/prefab contract.

## Semantic Zones

Generated `town_zones` are now sourced from road frontage assignments rather
than BSP district assignments.

The required zone ids remain stable:

- `plaza`;
- `residential`;
- `market`;
- `farm`;
- `training`;
- `gate`.

Additional building zones such as `tavern`, `farm_service`, `farm_storage`, and
`gate_service` are still generated from selected building lots.

## Preserved Contracts

Phase 60 intentionally keeps the useful parts of v56-v58:

- generated gameplay anchors;
- instance-based building identities;
- generated interior location ids;
- south-facing ordinary doors;
- prefab catalog selection;
- prefab-declared exterior slots only;
- F3 debug parcel presentation;
- validation that anchors, exits, usable objects, and schedule transition
  anchors remain reachable.

The change is the settlement layout authority, not the gameplay contract.

## Validation

Validation now covers the road-first output through the existing scene
generation smoke checks:

- required town zones exist;
- parcels reference valid semantic zones;
- generated buildings reference valid parcel and prefab ids;
- exterior slots are materialized only from prefab declarations;
- required anchors, exits, usable objects, and cross-scene schedule transition
  anchors remain reachable.

## Verification

- `git diff --check` passes.
- `tools/validation/validate_locations.ps1` passes.
- Godot 4.6.3 completes a headless main-scene startup with the generated
  road-first village loaded and no generator contract errors.
