# Phase 44: NPC Basic Activity Handlers

## Goal

Phase 44 makes NPCs do simple things after they arrive at scheduled targets.

Before this phase, `activity` is mostly descriptive. Phase 44 introduces a small behavior layer that interprets `activity_type` and performs lightweight, deterministic behavior.

## What Changed

Added `scripts/systems/schedules/npc_activity_agent.gd`.

`LocationRoot` now owns one activity agent for the currently loaded scene. The update order is:

```text
scheduled movement update
-> scheduled activity update
```

This keeps movement authoritative. An NPC that is still walking to its schedule target will not execute its arrival activity until the movement agent reports arrival.

`CharacterEntity` now records additional schedule runtime state:

- `current_schedule_anchor_id`
- `current_activity_type`
- `current_movement_mode`

These values are included in character summaries and are available for future behavior, debug, and UI work.

Location anchors may now include optional activity cells:

```json
{
  "id": "training_yard_guard_post",
  "kind": "training",
  "grid_position": { "x": 20, "y": 11 },
  "facing": "left",
  "activity_cells": [
	{ "x": 20, "y": 11 },
	{ "x": 21, "y": 11 }
  ]
}
```

Validation now checks that `activity_cells` and `patrol_cells` are valid walkable location cells.

## Relationship To Previous Phases

Phase 42:

- NPCs can visibly walk to a target cell in the current map.

Phase 43:

- schedules can express semantic targets and machine-readable `activity_type`.

Phase 44:

- after arrival, the NPC enters a small behavior loop based on `activity_type`.

This phase should not choose a new schedule. It only runs the activity selected by the schedule.

## Activity Handler Model

Each activity handler should have a narrow contract:

```text
enter activity
tick activity while current schedule entry remains active
exit activity when schedule entry changes or is interrupted
```

The implemented helper is `NpcActivityAgent`, owned by `LocationRoot`.

The activity layer should receive:

- character;
- current schedule entry;
- current location root;
- resolved anchor or target cell;
- elapsed time if needed.

It should not bypass action or world-state rules when producing real gameplay changes.

Implemented activity behavior:

- entering an activity emits a `scheduled_character_activity_entered` world change;
- mobile activity steps emit `scheduled_character_activity_step` world changes;
- `patrol`, `train`, and `social` use anchor `activity_cells` or `patrol_cells` when available;
- `idle`, `shopkeep`, `work`, `eat`, `rest`, and `sleep` remain stable at their anchor;
- `travel` is ignored as an arrival activity because it belongs to schedule movement.

## Initial Activity Types

### idle

The NPC stands at the target and faces the scheduled direction.

### travel

The NPC is still moving to a scheduled target. This may be treated as an internal state from Phase 42 rather than a final activity.

### shopkeep

The NPC stays near a shop counter and faces the expected direction.

Phase 44 should not rewrite the shop system. It may only update debug state or presentation.

### patrol

The NPC moves between a small set of local cells near the scheduled anchor.

First version rules:

- use only same-map cells;
- use normal movement collision;
- choose from explicit patrol points if present;
- otherwise stand still.

### train

The NPC faces a training target or moves lightly inside the training area.

No stat gain or combat automation is required.

### work

The NPC remains at a work anchor and may face nearby work objects.

No production economy changes are required in the first version.

### eat

The NPC sits or stands near a meal anchor and remains there for the entry duration.

No hunger system is required yet.

### rest / sleep

The NPC stays at a rest or bed anchor. Interaction text may describe the state later, but this phase does not need new dialogue rules.

## Behavior Boundaries

Phase 44 should keep behavior visual and deterministic.

Allowed:

- face a target direction;
- wander or patrol inside a tiny allowed area;
- stand at a work point;
- update `current_activity`;
- optionally expose debug summaries.

Not allowed yet:

- changing inventory;
- generating money;
- advancing quests;
- changing relationships;
- changing crop growth;
- writing save facts directly from visual behavior;
- starting combat automatically;
- using AI to select behavior.

Real world changes should be added only when a later phase explicitly routes them through rule systems.

## Data Compatibility

If an entry only has `activity`, it should still work as a display string.

If an entry has `activity_type`, the activity handler may run a matching behavior.

If `activity_type` is missing, default to `idle`.

## Updated Test Content

The current test data now demonstrates activity handlers without introducing new gameplay rules:

- `test_village` training and gate guard anchors have `activity_cells` for small guard movement.
- `test_village` plaza social anchor has a tiny local movement loop.
- `test_field` pond walk anchor has a small walking loop.
- `test_clearing` guard and night patrol anchors have local activity cells.
- shop, meal, work, rest, and sleep anchors remain stable.

These activity cells are visual / positional behavior only. They do not create production, relationship, quest, combat, or economy effects.

## Not Done Yet

Phase 44 does not add:

- offscreen activity simulation;
- needs, moods, or decision making;
- event interruptions;
- production or economy outputs;
- complex animations or sprite sheets;
- dialogue changes for every activity.

## Validation

Phase 44 is complete when:

- arriving NPCs enter a stable activity state;
- known `activity_type` values run small deterministic behaviors;
- unknown or missing `activity_type` values fall back safely;
- patrol or wander behavior respects collision;
- activity handlers do not break player interaction, shop, crafting, rest, save, battle, or scene transition systems;
- activity state is visible in debug summaries.
