# Phase 17 Farming System

## Goal

Add a small time-based planting loop that uses existing world rules instead of direct UI state mutation.

## Runtime Flow

Standing on a plantable tile and pressing `E` chooses the farming action from the current crop state:

- empty plantable tile with seeds: `PlantAction`
- planted crop that has not been watered: `WaterAction`
- mature crop: `HarvestAction`
- growing crop: reports that the crop is still growing

Each action is created through `ActionSystem`, then executed by `CropSystem`.

## Data

Added items:

- `data/items/debug_seed.json`
- `data/items/debug_herb.json`

Added crop:

- `data/crops/debug_crop.json`

`Debug Crop` requires water, grows for 180 in-game minutes after watering, and yields `Debug Herb`.

## Scene

`test_field` now has several `field_plot` tiles. A `Seed Pouch` drop gives `3 x Debug Seed`.

Plantable cells are terrain-driven through:

```json
"plantable": true
```

## Persistence

`CropSystem` exposes `get_save_state()` and `apply_save_state()`. `SaveManager` includes crop state in save data, so planted, watered, growing, and mature crops survive save/load.

## Visuals

`CropMarker` draws a simple debug marker:

- body color shows growth stage
- blue dot means watered
- yellow dot means mature

This is intentionally temporary and can be replaced with sprite-based crop art later.
