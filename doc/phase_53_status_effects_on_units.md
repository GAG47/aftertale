# Phase 53: Status Effects On Units

## Status

Planned.

## Goal

Connect battle tile states and elemental reactions to unit status, damage, movement, and turn timing.

Phase 51 makes the battlefield remember surface states. Phase 52 makes elements react with those states. Phase 53 makes standing on, moving through, or being hit on those states matter to units.

## Timing Points

Use explicit timing hooks:

```text
unit enters cell
unit starts turn
unit ends turn
unit is hit by skill
unit is affected by reaction
round advances
```

The first pass should prefer predictable rules over hidden probability.

## Minimum Unit Effects

Burning tile:

- unit starts turn on burning: takes fire damage;
- unit enters burning: optional immediate small damage, can be deferred;
- tile remains unless duration expires or water extinguishes it.

Wet tile:

- unit standing on wet can be treated as wet for lightning and ice reactions;
- wet alone does not damage the unit.

Frozen tile:

- movement cost can increase;
- unit starting on frozen may receive `chilled` or `frozen` if Phase 52 produced a direct freeze reaction;
- avoid random slipping in the first pass unless the UI can clearly explain it.

Electrified tile:

- unit starts turn on electrified: takes lightning damage;
- lightning can chain to units on adjacent wet or electrified cells.

## Unit Status Vocabulary

Initial battle statuses:

```text
wet
chilled
frozen
burning
shocked
```

These should use the existing `BattleUnitState` status effect container where possible.

Suggested meanings:

- `wet`: increases lightning vulnerability and enables freezing.
- `chilled`: minor movement or speed penalty.
- `frozen`: skips or limits action for a short duration.
- `burning`: turn-start damage if applied directly to unit.
- `shocked`: short-term AP, speed, or action penalty, deferred if balance is unclear.

## Movement Cost

`BattleSystem._get_reachable_cell_distances()` currently treats each passable step as cost 1. Phase 53 should prepare a rule helper:

```text
get_battle_cell_move_cost(unit, from_cell, to_cell)
```

This lets frozen or sticky surfaces affect pathing without rewriting movement every time a new surface is added.

## Feedback

Every automatic tile or status effect should produce understandable feedback:

```text
<unit> is burned by the flames.
<unit> is frozen on the wet ground.
Lightning jumps through the wet surface.
```

The exact localized text can be tuned later; the important part is that status-driven damage is not invisible.

## Acceptance

Phase 53 is complete when:

- tile states can affect units at turn start or movement timing;
- elemental reactions can apply battle statuses to units;
- movement preview uses modified movement costs when relevant;
- `ActionResult` records automatic damage or status changes;
- no unit status is applied only as a visual effect.

## Boundary

This phase does not require advanced AI planning. Enemy behavior may still use the old decision path until Phase 54, but the data it needs should now be available.
