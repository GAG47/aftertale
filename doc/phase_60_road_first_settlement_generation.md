# Phase 60: Removed Road-First Settlement Attempt

## Status

Removed.

## Reason

The first Phase 60 implementation was removed because it only appeared to be a
road-first settlement generator. It still made unsafe shortcuts:

- it generated a shallow road sketch instead of a real road skeleton model;
- it scanned fixed-size frontage lots;
- it assigned buildings one by one instead of planning the lot set;
- it kept building prefab, parcel, generated interior, and repair-routing code
  in the active generator path.

Keeping that implementation would have made later generation work depend on a
bad structure, so it was deleted instead of repaired.

## Removed Current-Path Pieces

- BSP generator entry points are not present in active code.
- The incorrect Phase 60 building and frontage placement code was removed.
- Generated building interiors were removed from the active loading path.
- Building prefab catalog data and loading code were removed.
- Temporary prefab placeholder drawing was removed from the scene component
  library.

The next valid step is Phase 60.1, which rebuilds only the road skeleton and
keeps all lot and building work out of the generator.
