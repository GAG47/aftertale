# Phase 21 Skill Targets And Enemy Decision

This phase expands skills beyond adjacent single-target attacks and gives enemies a simple non-AI tactical decision layer.

## Skill Target Types

Supported target types:

- `self`: the caster only.
- `enemy`: active enemy units in range.
- `ally`: active allied units in range.
- `ally_or_self`: active allied units in range, including the caster.

Supported area types:

- `single`: affects one resolved target.
- `radius`: affects matching units within `radius` cells of the chosen target cell.

Supported effect types:

- `damage`: uses `strength`, `agility`, `intellect`, or `flat` formulas.
- `heal`: restores HP using `intellect`, `vitality`, or `flat` formulas.
- `status`: applies a battle status such as Guard.

## Enemy Decision

Enemy turns now follow a simple priority order:

1. If HP is at or below half, try `first_aid`.
2. If HP is at or below half and not already guarded, try `guard`.
3. Choose the highest-scoring damage skill that can currently hit the player.
4. If no skill can hit, move one cell toward the player.
5. After moving, try the highest-scoring damage skill again.
6. If still unable to act, try a survival skill.
7. Otherwise wait.

The scoring is intentionally small and deterministic: it sums estimated damage against affected player units, gives a small bonus for likely defeats, and lightly penalizes higher AP cost.

## Boundaries

This is still not a full AI system. It does not plan multiple turns, evaluate terrain, preserve cooldowns for future opportunities, or coordinate multiple enemies. It is a tactical rule layer that makes enemies use the same skill system as the player.
