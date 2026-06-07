# Phase 54: Enemy AI Scoring

## Status

Complete.

## Goal

Replace the current simple enemy priority chain with an explainable scoring system.

The goal is not to make enemies perfectly optimal. The goal is to make enemies appear tactically aware while keeping behavior deterministic, debuggable, and easy to balance.

## Previous Baseline

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

AI profiles are stored in `data/battle/ai_profiles.json`. They share one scoring
implementation and only change weights and preferred range:

```text
balanced
aggressive
defensive
controller
support
```

Example weight differences:

- aggressive units value damage and kills more than safety;
- defensive units value safe cells and guard behavior;
- controllers value tile states, control, and elemental reactions;
- support units value healing and ally survival;

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

## Implementation

`BattleAiPlanner` now:

- enumerates wait, move, skill, and move-then-skill candidates;
- finds reachable cells using battle movement costs;
- predicts skill legality, affected cells, and affected units from a proposed move cell;
- scores damage, kills, control, survival, tile value, position, target priority, risk, resource use, support, and elemental reactions;
- caps candidate generation and uses deterministic tie-breaking;
- returns the chosen action plus the top five candidates and weighted score reasons.

`BattleSystem` executes the chosen candidate instead of using the former fixed
priority chain. `BattleState.recent_ai_decisions` retains recent decisions and
publishes them as `battle_ai_decision` world changes for inspection.

Characters select behavior with the `ai_profile` definition field. Unknown
profiles fall back to the configured default profile.

## Verification

The v54 smoke scene covers:

- moving and attacking in one scored action;
- preferring lightning against a wet target;
- strongly preferring a confirmed defeat;
- leaving a burning tile;
- choosing first aid for an injured ally.

The project also passes a headless startup and script parse check on Godot
4.6.3.

## Boundary

This phase does not introduce machine learning or language-model-driven combat decisions. Battle AI remains a transparent rule scoring layer.
