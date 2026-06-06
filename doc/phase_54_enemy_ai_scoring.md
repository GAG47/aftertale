# Phase 54: Enemy AI Scoring

## Status

Planned.

## Goal

Replace the current simple enemy priority chain with an explainable scoring system.

The goal is not to make enemies perfectly optimal. The goal is to make enemies appear tactically aware while keeping behavior deterministic, debuggable, and easy to balance.

## Current Baseline

The current enemy turn logic is intentionally simple:

```text
try survival skill
-> choose best immediate damage skill
-> move toward nearest active player
-> try damage again
-> try survival skill
-> wait
```

This is a good foundation, but it cannot reason about tile states, reactions, threat, or positioning beyond nearest-target pursuit.

## Action Candidate Model

Phase 54 should evaluate candidates shaped like:

```text
move_cell
skill_id
target_cell
target_unit_id
score
score_breakdown
```

Candidates include:

- wait;
- move only;
- move then use skill;
- use skill without moving;
- self or ally support skill;
- tile-targeting elemental skill.

## Scoring Factors

Positive factors:

- damage dealt;
- confirmed defeat;
- multiple enemies hit by area skill;
- healing or protecting allied units;
- creating useful tile states;
- triggering useful elemental reactions;
- standing in good range for the unit role;
- attacking wet targets with lightning;
- freezing wet targets with ice;
- extinguishing dangerous fire near allies.

Negative factors:

- standing on burning or electrified tiles;
- moving into easy surround positions;
- damaging allies;
- wasting area skills on one low-value target;
- spending high AP for low impact;
- moving closer while low HP;
- ending turn in player threat range without reason.

## Role Weights

Use data weights instead of different hard-coded AI classes:

```text
aggressive
defensive
skirmisher
caster
support
guardian
```

Example weight differences:

- aggressive units value damage and kills more than safety;
- defensive units value safe cells and guard behavior;
- casters value area effects and elemental reactions;
- support units value healing and ally survival;
- skirmishers value distance control.

## Score Breakdown

Every chosen action should be explainable in debug data:

```text
damage_score
kill_score
reaction_score
position_score
safety_score
support_score
ap_cost_penalty
final_score
```

This makes tuning possible. If an enemy makes a strange move, the debug panel or log should show why.

## Search Boundary

Keep the first pass shallow:

- evaluate current position and reachable move cells;
- evaluate legal skills from those cells;
- do not plan more than one enemy turn ahead;
- do not coordinate full-team strategies yet;
- keep candidate counts capped if performance becomes visible.

This is enough for enemies to feel smarter without creating a black-box planner.

## Acceptance

Phase 54 is complete when:

- enemy turns choose from scored candidates instead of a fixed priority chain;
- score breakdowns are available for debug inspection;
- enemies avoid obviously dangerous tile states;
- enemies can prefer elemental combos such as lightning on wet targets;
- support and damage skills can both win scoring when appropriate;
- behavior remains deterministic for the same battle state.

## Boundary

This phase does not introduce machine learning or language-model-driven combat decisions. Battle AI remains a transparent rule scoring layer.
