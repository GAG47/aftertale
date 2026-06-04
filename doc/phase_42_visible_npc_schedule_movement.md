# Phase 42: Visible NPC Schedule Movement

## Goal

Phase 42 upgrades current NPC schedule movement from direct relocation to visible step-by-step walking inside the currently loaded map.

The player should be able to see an NPC leave one scheduled position, walk through valid grid cells, and arrive at the next scheduled position. This phase is about movement execution only. It does not redesign schedule data, add behavior simulation, or introduce AI decision making.

## What Changed

Added `scripts/systems/schedules/npc_movement_agent.gd`.

The movement agent executes visible same-map schedule movement:

- accepts schedule movement requests from `LocationRoot`;
- computes a four-directional grid path with breadth-first search;
- moves the NPC one cell at a time;
- updates occupancy through `LocationGrid.move_character()`;
- updates visible position through `CharacterEntity.set_grid_position()`;
- faces the NPC toward each movement step;
- applies final schedule facing and activity after arrival;
- reports arrived and blocked movement as world changes.

`LocationRoot` now owns one movement agent for the active scene. Its schedule application path no longer directly relocates visible NPCs when the target schedule cell is in the current map. Instead, it creates a movement intent and lets the agent advance it over time.

Cross-location schedule changes still use the existing behavior: NPCs leave the loaded scene or spawn into it according to the active schedule entry. This keeps Phase 42 focused on visible same-map movement only.

## Relationship To Existing Systems

Phase 8 already established world time, daily schedule entries, and schedule application through `NpcScheduleSystem` and `LocationRoot`.

Current behavior:

- `NpcScheduleSystem` decides which schedule entry is active.
- `LocationRoot.apply_current_schedule()` applies the active entry to visible NPCs.
- When an active entry changes, the NPC is moved directly to the target grid cell.
- `CharacterEntity.set_grid_position()` plays a short visual tween, but the logical position changes immediately.

Phase 42 keeps that authority split:

- `NpcScheduleSystem` still decides the active schedule entry.
- `LocationRoot` still owns the currently loaded scene and visible characters.
- `LocationGrid` remains the source of collision and occupancy truth.
- `CharacterEntity` remains the visible character token.

The new responsibility is a visible movement executor that turns a schedule target into a path and advances the NPC one cell at a time.

## Implemented Scope

Implemented in this phase:

- `NpcMovementAgent` for visible schedule movement.
- Same-map movement intents keyed by character id and schedule entry id.
- BFS pathfinding over the current `LocationGrid`.
- Dynamic blocking checks on every step.
- One re-path attempt when the next step becomes blocked.
- Scheduled movement pause while combat is active.
- Arrival feedback and world changes.
- Blocked movement feedback and world changes.
- Existing schedule data compatibility.

Kept unchanged:

- schedule entry format;
- offscreen settlement format;
- cross-map schedule handling;
- interaction object behavior;
- party follower behavior;
- battle movement behavior;
- save data shape.

## Core Design

Introduce a visible movement layer for scheduled NPCs in the current map.

Conceptually:

```text
time changes
-> active schedule entry is selected
-> visible NPC needs to reach target cell
-> movement intent is created once
-> path is found through LocationGrid
-> NPC walks one cell per step
-> arrival applies facing and activity
```

The important rule is that a schedule entry change creates an intent. Time changes should not recreate the same intent every minute.

## Proposed Runtime Pieces

### NPC Movement Intent

A movement intent records one scheduled movement job:

```text
character_id
schedule_entry_id
from_cell
target_cell
target_location_id
arrival_facing
arrival_activity
state: walking / arrived / blocked / cancelled
```

The intent belongs to the visible scene runtime. It is not a saved world fact yet.

### NPC Movement Agent

`NpcMovementAgent` should execute visible scheduled movement for characters in the active `LocationRoot`.

Responsibilities:

- accept movement intents from `LocationRoot`;
- compute a path through walkable grid cells;
- advance the NPC one grid cell per movement step;
- update `LocationGrid` occupancy through `grid.move_character()`;
- call `CharacterEntity.set_grid_position()` only after the grid accepts the move;
- face the direction of travel while walking;
- apply final facing and activity when arriving;
- report blocked movement through existing schedule result feedback.

It should not decide what an NPC wants to do. It only executes movement that schedule logic has requested.

### Pathfinding

The first implementation can use a simple breadth-first search.

Requirements:

- use `LocationGrid.in_bounds()`;
- use `LocationGrid.can_enter()` for candidate cells;
- allow the NPC's own current cell as the path origin;
- avoid moving through characters, objects, walls, fences, and other blockers;
- search four-directional grid movement only.

The current maps are small enough that BFS is sufficient. A more advanced pathfinder can be introduced later if map size or terrain cost requires it.

## LocationRoot Integration

The current `_apply_schedule_entry_to_character()` path directly calls `_move_scheduled_character()`.

Phase 42 should change same-map schedule movement to:

```text
if schedule target is in the current location:
    if the character is already at the target:
        apply facing and activity
    else:
        submit or refresh movement intent
        mark visible state as traveling
```

Cross-location schedule changes should keep the existing leave / appear behavior for now.

## Collision Rules

Movement must not bypass existing grid rules.

- NPCs must not walk through structure blockers.
- NPCs must not walk through blocking objects.
- NPCs must not walk through the player.
- NPCs must not push or swap with the player.
- NPCs must not overwrite another NPC's occupied cell.
- If the next step becomes blocked, the movement agent may re-path once.
- If re-pathing fails, the existing `scheduled_character_blocked` style result should be emitted.

`LocationGrid` remains the only movement authority.

## Time And Combat Rules

Phase 42 should avoid repeated intent churn.

- Create a new intent when the active schedule entry id changes.
- Create a new intent when the target cell changes for the same entry.
- Do not recreate the same intent on every `time_changed` signal.
- Pause scheduled walking while `GameState.current_mode` is combat.
- Party members remain skipped by NPC schedule updates.

## Data Compatibility

Phase 42 should continue using current schedule data:

```json
{
  "id": "shop_day",
  "start": "06:00",
  "end": "17:59",
  "location_id": "test_village",
  "grid_position": { "x": 18, "y": 4 },
  "facing": "down",
  "activity": "tending the shop"
}
```

No `anchor_id`, new activity schema, or route data is required in this phase.

## Not Done Yet

Phase 42 does not add:

- formal anchor-based schedule data;
- full daily routines;
- activity handlers such as eating, working, or sleeping;
- cross-map route simulation;
- offscreen travel progress;
- autonomous decision making;
- AI-controlled behavior selection;
- weather, hunger, energy, or mood rules.

## Validation

Phase 42 is complete when:

- an NPC visibly walks between two schedule cells in the same loaded map;
- the NPC follows valid grid paths instead of teleporting;
- the NPC cannot pass through walls, structures, objects, the player, or other blocking characters;
- blocked movement reports a schedule movement failure without corrupting occupancy;
- arrival applies the schedule entry's final facing and activity;
- combat mode prevents visible schedule walking from advancing;
- existing player movement, interaction, battle, shop, crafting, save, and scene transition behavior still works.
