# Phase 46: Lightweight NPC Autonomy And Interruptions

## Implemented Scope

Phase 46 adds a small deterministic autonomy layer on top of the fixed schedule system.

The implemented helper is `NpcAutonomyAgent`, owned by `LocationRoot`.

The rule layer does not move characters directly. It chooses a temporary schedule-like entry, then routes movement through `NpcMovementAgent` and lets `NpcActivityAgent` continue handling arrival behavior.

Current implemented rule:

- if the active location has `state.danger_level > 0`;
- visible guard NPCs are interrupted with reason `danger_alert`;
- the guard targets a `guard_post` anchor, preferring `wild_gate_guard_post` or `clearing_guard_post`;
- the temporary entry uses `activity_type: "patrol"` and `activity: "responding to danger"`;
- when danger returns to `0`, the interruption clears and `LocationRoot.apply_current_schedule()` restores the active fixed schedule.

Default test locations keep `danger_level: 0`, so existing daily schedules remain unchanged unless a location state event raises danger.

## Runtime State

`CharacterEntity` now exposes the active interruption state in summaries:

```json
{
  "interruption_reason": "danger_alert",
  "interruption_priority": 80
}
```

Empty reason and priority `0` mean the character is following the normal schedule/activity loop.

The autonomy agent keeps temporary interruption records in memory:

```json
{
  "reason": "danger_alert",
  "priority": 80,
  "started_at": 1080,
  "target_anchor_id": "wild_gate_guard_post",
  "danger_level": 1
}
```

This state is intentionally not saved yet. Phase 45 remains responsible for restoring fixed schedule placement on re-entry.

## Update Order

`LocationRoot._process()` now updates NPC systems in this order:

```text
scheduled movement
autonomy interruptions
basic activities
```

This means:

- a character already walking can finish or continue normally;
- autonomy can start or clear a temporary high-priority state;
- activity handling still skips characters with active movement.

## Schedule Interaction

While an NPC has an active interruption, normal schedule refreshes do not overwrite it.

When the interruption clears:

1. the temporary movement intent is cancelled;
2. the character interruption fields are cleared;
3. `apply_current_schedule()` runs against the current absolute time;
4. the NPC walks back to the current schedule anchor if needed.

Cross-map departures are also held while a high-priority interruption is active. This keeps the rule simple and avoids a guard leaving the current danger scene because a clock tick advanced.

## Events

The autonomy layer publishes normal `ActionResult` world changes:

- `scheduled_character_interruption_started`
- `scheduled_character_interruption_retried`
- `scheduled_character_interruption_cleared`

Movement completion still comes from `NpcMovementAgent` as:

- `scheduled_character_arrived`
- `scheduled_character_blocked`

## Priority Boundary

Current priority rule:

1. player-controlled, party member, defeated, or wrong-location characters are skipped;
2. immediate location danger interrupts guards at priority `80`;
3. active interruptions block ordinary schedule refresh;
4. when the event condition ends, the fixed schedule resumes.

This gives us a clean place to add future rules without mixing them into scene loading or pathfinding.

## System Boundaries

Allowed:

- choose a temporary target anchor;
- choose a temporary activity;
- request movement through the movement agent;
- expose debug reason and priority;
- resume schedule after the interruption.

Not allowed in this phase:

- completing quests;
- awarding items or money;
- changing relationships;
- killing or removing characters;
- bypassing battle, action, inventory, save, or quest systems;
- AI/model-driven planning.

## Future Rules

Good next autonomy rules can be added as small deterministic branches:

- civilian avoids outdoor route when `danger_level` is high;
- merchant leaves counter after shop-close event;
- NPC flees when directly attacked;
- friendly NPC does a nearby greeting when the player is close;
- low energy skips optional social activity.

Each future rule should record `reason`, `priority`, and its target, and should still execute through movement/activity agents.

## Validation

Completed checks:

- Godot headless project load succeeds.
- Location data validation passes.
- The implemented rule uses `LocationGrid` anchors and `NpcMovementAgent`; it does not create a separate movement path.
- Character summaries expose the active interruption reason and priority for debugging.

