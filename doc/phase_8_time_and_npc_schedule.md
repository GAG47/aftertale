# Phase 8: Time and NPC Schedule

This phase gives the world a basic daily rhythm without trying to simulate the whole world in detail.

## Runtime Systems

- `TimeManager` owns day, hour, minute, day/night period, pause state, and time advancement.
- `NpcScheduleSystem` chooses the active schedule entry for an NPC from the current world time.
- `LocationRoot` applies schedule entries to NPCs in the loaded scene.
- Schedule changes are published through `ActionSystem.publish_result()` as `ScheduleUpdate` results.
- `RestAction` advances time through the action layer.

## Schedule Data

NPC schedules live in character JSON definitions:

```json
{
  "id": "day_path_watch",
  "start": "09:00",
  "end": "11:59",
  "location_id": "test_field",
  "grid_position": { "x": 7, "y": 5 },
  "facing": "left",
  "activity": "watching the path"
}
```

Schedules repeat every day. Entries can cross midnight, for example `21:00` to `05:59`.

## Current Behavior

- NPCs spawn at the schedule position for the current time.
- NPCs move to a new scheduled grid cell when the active entry changes.
- NPCs can leave the loaded scene if their active schedule points to another location.
- NPCs can appear in the loaded scene when their active schedule points back to it.
- Blocked scheduled movement emits a `scheduled_character_blocked` world change.
- Offscreen settlement is exposed through `NpcScheduleSystem.settle_offscreen_location()`.

## Debug Flow

- Start the game in `test_field`.
- Open the debug panel with `F3`.
- Watch `Time` and `NPC Schedules`.
- Press `R` to rest for one hour and force schedule changes quickly.
- The Debug Villager changes position and activity across morning, day, afternoon, evening, and night.

## Validation

`tools/validation/validate_locations.ps1` validates:

- location data
- character sources
- dialogue links
- quest links
- schedule time format
- schedule target location ids
- schedule grid positions
- schedule walkability
