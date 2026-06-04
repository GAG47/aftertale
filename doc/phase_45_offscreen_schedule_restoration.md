# Phase 45: Offscreen Schedule Restoration

## Goal

Phase 45 makes NPC schedule state recover correctly when the player leaves and later re-enters a scene.

Earlier phases focus on visible current-map behavior. Phase 45 handles the hidden time between scene visits.

## What Changed5

`NpcScheduleSystem` now owns persistent offscreen schedule summaries.

Added runtime state:

- `offscreen_states`
- `last_settled_minutes_by_location`

Added APIs:

- `get_offscreen_character_state(location_id, character_id)`
- `get_save_state()`
- `apply_save_state(state)`
- `reset_schedule_state()`

When a location root unregisters, the schedule system settles that location from the time it was registered to the current world time. When the player later enters a location again, the schedule system can settle the hidden time between the last recorded settlement and the current time before the location applies its visible schedule.

`LocationRoot` now consults offscreen character state while spawning scheduled characters. If the offscreen state matches the current active schedule entry, the spawn data restores:

- grid position;
- facing;
- schedule entry id;
- anchor id;
- activity type;
- activity text;
- movement mode;
- scheduled location id.

`SaveManager` now stores NPC schedule restoration state under `npc_schedules`. Loading a save restores that state before the target scene is loaded. To avoid pollution from the scene that existed before loading, the schedule system skips the next unregister settlement after applying save state.

New games call `NpcScheduleSystem.reset_schedule_state()` so offscreen summaries do not leak between sessions.

## Relationship To Existing Systems

`NpcScheduleSystem.settle_offscreen_location()` already exists. It can inspect a location's character rows and produce a summary of where scheduled NPCs should be at a target time.

Phase 45 should expand that idea into a reliable restoration model:

```text
player leaves location
-> offscreen schedule state is settled
-> time passes
-> player enters a location
-> NPCs are spawned or positioned according to current schedule state
```

Implemented behavior:

- visible locations are settled when they are unloaded;
- previously settled locations are advanced when they are entered again after hidden time passes;
- re-entered NPCs spawn from active schedule data plus matching offscreen state;
- active scene NPCs still use Phase 42 movement and Phase 44 activities while visible;
- removed / defeated characters and party members continue to follow existing rules.

## Scope

Phase 45 should answer:

- Is the NPC currently in this location?
- If yes, where should the NPC appear?
- Is the NPC already arrived at a schedule target?
- Is the NPC currently traveling between schedule targets?
- What facing and activity should be restored?

The first version can be deterministic and approximate. It does not need to replay every hidden step.

## Offscreen State Shape

Suggested state:

```json
{
  "character_id": "debug_villager",
  "location_id": "test_village",
  "schedule_entry_id": "shop_day",
  "grid_position": { "x": 18, "y": 4 },
  "facing": "down",
  "activity_type": "shopkeep",
  "activity": "tending the shop",
  "state": "arrived",
  "settled_at": 720
}
```

For future route-aware travel:

```json
{
  "character_id": "debug_villager",
  "from_location_id": "test_village",
  "to_location_id": "test_field",
  "schedule_entry_id": "work_morning",
  "state": "traveling",
  "departed_at": 460,
  "arrives_at": 510
}
```

The first implementation may resolve most offscreen entries directly to their active target cell. Route-aware travel can be introduced only where the data is ready.

## Re-entry Rules

When loading a location:

- find each NPC's active schedule entry for the current time;
- resolve its target location and target cell;
- if the target location is this location, spawn or place the NPC there;
- if the target location is another location, do not spawn the NPC here;
- if a travel state says the NPC should be in transit, either spawn at a suitable route point if supported or keep the NPC absent until arrival.

If a saved runtime state conflicts with schedule state, phase rules must define precedence.

Suggested precedence:

1. removed or defeated characters stay removed if game state says so;
2. party members follow party rules and ignore NPC schedule;
3. active schedule determines normal NPC location;
4. runtime inventory, HP, and equipment still come from character runtime state.

## Interaction With Visible Movement

Offscreen restoration should not cause visible teleporting while the player is watching.

- If the NPC is visible, Phase 42 movement agent handles schedule movement.
- If the NPC is not visible, Phase 45 settlement chooses the appropriate restored state.
- On re-entry, NPCs may spawn at the settled position.

## Not Done Yet

Phase 45 does not add:

- autonomous decision making;
- event interruptions;
- full route graph simulation for all locations;
- background combat;
- background economy;
- AI-generated summaries.

## Validation

Phase 45 is complete when:

- leaving and re-entering a location restores scheduled NPCs to plausible current positions;
- NPCs whose active schedule points elsewhere are absent;
- party members are not incorrectly restored as normal NPCs;
- removed or defeated characters do not reappear through schedule settlement;
- NPC runtime state such as HP and inventory is preserved;
- visible NPCs do not teleport while the player remains in the scene;
- resting or advancing time offscreen produces schedule-consistent re-entry results.
