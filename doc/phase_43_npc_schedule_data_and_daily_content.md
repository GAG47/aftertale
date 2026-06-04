# Phase 43: NPC Schedule Data And Daily Content

## Goal

Phase 43 formalizes NPC schedule data and gives important NPCs clearer daily routines.

Phase 42 makes visible same-map walking possible while preserving the old schedule format. Phase 43 is the point where schedule data becomes more semantic and easier to author at scale.

## What Changed

Added optional location `anchors` and expanded schedule entries with semantic fields.

Runtime now supports:

- resolving schedule targets by `anchor_id`;
- falling back to `grid_position` when an anchor is missing or not used;
- using anchor facing unless the schedule entry overrides it;
- storing `activity_type` on `CharacterEntity`;
- including `activity_type` in character summaries;
- carrying `anchor_id`, `activity_type`, and `movement` through offscreen schedule summaries.

Validation now checks:

- anchor ids and anchor cells;
- duplicate anchors;
- schedule `anchor_id` references;
- `grid_position` fallback cells;
- supported `activity_type` values;
- supported `movement` values;
- schedules defined on character source files;
- schedules defined directly on location character spawn rows.

Updated test content:

- `test_village` now has anchors for home, shop, tavern, plaza, training yard, wild gate, and farm work points.
- The village merchant now has a home / shop / lunch / shop / tavern / home routine.
- The village guard now has training yard, plaza check, training yard, and night gate guard entries.
- `test_field` now has field work, path watch, pond walk, west path, and rest anchors.
- `test_clearing` now has guard post and night patrol anchors.
- `debug_villager` and `debug_guard` source schedules now use `anchor_id`, `activity_type`, and `movement` while keeping explicit `grid_position` fallbacks.

## Why This Comes After Phase 42

Schedule format should not be expanded before the movement executor is stable.

Phase 42 answers:

```text
Can an NPC walk from its current cell to a scheduled target cell?
```

Phase 43 answers:

```text
How do we author readable daily routines without hardcoding every cell into every NPC?
```

Keeping these phases separate prevents data model work from being mixed with movement bugs.

## Current Data Shape

Current schedule entries are grid-position based:

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

This is still valid. Phase 43 should be backward compatible with this shape.

## Target Data Shape

Phase 43 may introduce optional semantic fields:

```json
{
  "id": "breakfast",
  "start": "06:30",
  "end": "07:10",
  "location_id": "test_village",
  "anchor_id": "house_table",
  "facing": "up",
  "activity_type": "eat",
  "activity": "eating breakfast",
  "movement": "walk",
  "priority": 10
}
```

Recommended fields:

- `id`: stable schedule entry id.
- `start`: local day start time, `HH:MM`.
- `end`: local day end time, `HH:MM`, may cross midnight.
- `location_id`: target location.
- `grid_position`: explicit fallback target cell.
- `anchor_id`: optional semantic location target.
- `facing`: final facing after arrival.
- `activity_type`: machine-readable behavior category.
- `activity`: player/debug readable activity text.
- `movement`: movement mode, initially `walk`.
- `priority`: priority for future interruptions.

`grid_position` should remain valid and supported. If both `anchor_id` and `grid_position` exist, the anchor may resolve the target and `grid_position` acts as fallback.

Implemented resolution order:

```text
anchor_id grid_position, if the anchor exists
-> schedule grid_position fallback
-> no target
```

Implemented facing order:

```text
schedule facing
-> anchor facing
-> character current/default facing
```

## Location Anchors

Location data may define anchors:

```json
"anchors": [
  {
	"id": "house_bed",
	"kind": "bed",
	"grid_position": { "x": 2, "y": 3 },
	"facing": "down"
  },
  {
	"id": "shop_counter",
	"kind": "work",
	"grid_position": { "x": 18, "y": 4 },
	"facing": "down"
  }
]
```

Anchors are semantic references for schedule authoring. They should not create collision or interaction by themselves.

Rules:

- anchors resolve to grid cells;
- anchors may provide default facing;
- anchors may refer to an existing object id, but do not replace objects;
- missing anchors should fall back to `grid_position` if present;
- validation should report missing anchors when no fallback exists.

## Daily Content Scope

Phase 43 should give the important visible NPCs more meaningful routines.

Suggested initial targets:

- village merchant: home / shop counter / tavern / home;
- village guard: training yard / wild gate / patrol point;
- test villager: field / plaza / home or tavern;
- future named NPCs: bed / meal point / work point / social point.

The goal is readable daily rhythm, not complex autonomy.

## Validation Updates

The validation tool should understand:

- schedule time format;
- schedule target location ids;
- explicit `grid_position` cells;
- `anchor_id` references;
- fallback behavior when both anchor and grid position exist;
- `activity_type` values from an approved small set;
- cross-midnight entries.

Suggested first `activity_type` set:

```text
idle
travel
eat
work
shopkeep
patrol
train
rest
sleep
social
```

## Not Done Yet

Phase 43 does not implement:

- new pathfinding;
- activity execution;
- hunger, energy, or mood;
- event interruptions;
- offscreen route simulation;
- AI-generated schedules.

## Validation

Phase 43 is complete when:

- old schedule entries still load;
- new schedule entries can target anchors;
- missing or invalid anchors are caught by validation;
- important test NPCs have clearer daily routines;
- schedule debug output remains understandable;
- movement from Phase 42 can consume resolved schedule targets without knowing whether they came from `grid_position` or `anchor_id`.
