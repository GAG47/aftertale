# Phase 20 Basic Skill System

This phase turns battle actions into data-driven skills.

## Scope

- Adds battle skill definitions under `data/skills`.
- Adds `SkillSystem` for loading skills, checking target rules, calculating damage, and formatting feedback.
- Adds `UseSkillAction` so skill use enters the action system.
- Adds character skill lists.
- Adds battle unit status effects.
- Adds lightweight skill cooldown tracking.
- Adds skill buttons to the battle HUD.
- Uses the selected skill for combat target highlighting and click targeting.

## Test Skills

- `basic_attack`: 1 AP, adjacent enemy, strength damage.
- `power_strike`: 2 AP, adjacent enemy, stronger strength damage.
- `guard`: 1 AP, self target, applies Guard and ends the current turn.
- `quick_shot`: 1 AP, range 3 enemy target, agility damage.
- `first_aid`: 1 AP, range 2 ally or self target, restores HP.
- `shockwave`: 2 AP, range 2 enemy target, damages enemies around the target cell.

## Combat Flow

1. The active player unit has a selected skill.
2. The battle HUD shows known skills and AP costs.
3. Selecting an enemy-target skill updates highlighted target cells.
4. Clicking a highlighted target submits `UseSkillAction`.
5. `BattleSystem` applies AP cost, damage, statuses, and turn advancement.
6. `ActionResult` records skill use, damage, status changes, and feedback.

## Rule Boundary

The HUD and scene clicks never change HP, AP, or status directly. They select skills or submit a skill action. Skill definitions are data; execution remains in the battle rules layer.
