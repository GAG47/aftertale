# Phase 60.1: Road Skeleton Only

## Status

Complete.

## Goal

Phase 60.1 rebuilds the village generator around the road skeleton only.

This phase intentionally does not place buildings, parcels, interiors, or
building prefabs. Those systems were removed from the active generation path so
they cannot hide mistakes in the road model.

## Scope

The active generator now produces:

- a deterministic main road crossing the village;
- constrained branch roads;
- plaza, farm, training yard, and gate zones attached to the road skeleton;
- core anchors for plaza, farm, training, and gate activities;
- the wild gate exit;
- debug player, guard, and training dummy rows.

The generator does not produce:

- buildings;
- parcels;
- generated building interiors;
- building prefab catalog data;
- building prefab placeholder structures;
- repair routes from the plaza to targets.

## Design Rule

The road skeleton must stand on its own. If a target is unreachable, generation
or validation should fail. The generator must not add a late connection route
after functional targets are placed.

## Validation

Validation checks:

- generated location grid validity;
- no generated buildings, parcels, interiors, or building prefab data;
- required town zones exist: plaza, farm, training, and gate;
- required anchors exist and are reachable from the plaza entrance;
- exits are reachable from the plaza entrance;
- usable or inspectable objects have a reachable interaction side.

## Verification

- `git diff --check` passes.
- `tools/validation/validate_locations.ps1` passes.
- Godot 4.6.3 completes a headless main-scene startup with no generator
  contract errors.
