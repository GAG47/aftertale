# Phase 40 - Minimal Village Scene

## Goal

Upgrade the runtime test space from a small field into a minimal village that can act as the first concrete sample for future town generation.

## Scene

Added `test_village` as the new default starting location.

The village contains the required areas:

- residence
- workshop
- shop
- tavern / dining hall
- fields
- plaza
- wild entrance
- training yard

## Data Shape

The village is still hand-authored, but it now includes `districts` metadata. Each district records:

- id
- type
- display name
- bounds
- entrance point

This is not a generator yet. It is a sample output shape that future town generation can target.

## Runtime Facilities

The village reuses current facility systems:

- residence bed uses rest-to-next-morning behavior;
- workshop workbench opens crafting;
- shop counter opens vendor-backed trading;
- tavern counter uses paid full-rest behavior;
- plaza save stone uses the save point flow;
- field plots remain plantable;
- wild gate links to the clearing;
- training yard contains combatable training dummies.

## Navigation

`test_clearing` now returns to `test_village` through the village wild gate entrance.

## Presentation

Added terrain rendering details for:

- building floors;
- plaza stone;
- training ground sand.

Added a separate building presentation layer:

- `BuildingRenderer` draws building walls, roofs, doors, windows, and signs.
- Village buildings now have `buildings` metadata with bounds, door cells, roof color, wall color, and sign labels.
- The current implementation uses the same-map building approach:
  - outside the building, the roof is visible so the area reads as a house/workshop/shop/tavern;
  - when the player enters that building's bounds, the roof is hidden and the interior remains visible.

This keeps the village as one continuous map while leaving larger interiors available for separate scenes later.

## Verification

- Checked the new location data dimensions and object bounds.
- Ran Godot headless startup check successfully.
