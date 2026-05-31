# Phase 14 Save System

## Goal

Persist the current runtime world state without changing the data-driven gameplay shape.

## Controls

- `F5`: save to `user://saves/slot_1.json`
- `F9`: load from `user://saves/slot_1.json`

Saving is blocked during dialogue and combat because those transient modes are not part of the persistent save payload yet.

## Saved Data

- save version and timestamp
- current scene path, scene id, location id
- controlled character grid position and facing
- player runtime state, including inventory, equipment, HP, max HP, defeat state, and attributes
- game flags and world facts
- removed scene objects, such as picked-up drops
- removed scene characters, such as defeated enemies
- time state
- quest states and quest owners
- character and faction relations plus recent relation events

## Runtime Rules

Scene transitions continue to spawn the player at entrances, but inventory and combat stats persist through `GameState.character_runtime_states`.

Loading a save suppresses the old scene's exit-time runtime writeback so the pre-load player state cannot overwrite the loaded state.

Save data is versioned with `SAVE_VERSION` in `SaveManager`. Future systems should add data through their own `get_save_state()` and `apply_save_state()` methods, then be included by `SaveManager`.
