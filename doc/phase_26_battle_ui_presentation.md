# Phase 26 Battle UI Presentation

This phase improves battle readability without changing battle rules.

## Scope

- Keep combat resolution inside `BattleSystem`, `SkillSystem`, and action results.
- Make the battle HUD readable as a player-facing tactical interface.
- Show battle state directly on map tokens.
- Add short-lived visual feedback for damage, healing, status, and defeat.
- Keep battle range rendering owned by `BattleGridOverlay`.

## Battle HUD

`BattleHudPanel` now presents the active battle as a bottom control surface:

- Current round and current acting unit.
- Current unit HP and AP bars.
- A clear hint for player turns versus enemy turns.
- Horizontal skill cards with AP cost, range, target type, area shape, cooldown, and selected state.
- Skill detail text for the selected skill, including failure reasons when unavailable.
- Compact unit roster in the current unit panel.
- Battle commands grouped on the right side of the dock.

The message log is hidden while combat is active so the map, ranges, tokens, and floating battle feedback remain the primary read.

The panel still calls back through existing wait, flee, and skill selection signals. It does not spend AP, apply damage, or move units directly.

## Token Battle State

`CharacterEntity` can now receive a presentation-only battle summary:

- Blue/red team ring.
- HP and AP micro bars.
- Current action marker.
- Status badge when active status effects exist.

The character's grid position, HP, AP, team, and current-turn data still come from battle summaries and unit state.

## Floating Feedback

`BattleFeedbackPopup` displays short-lived feedback over map characters:

- Damage numbers.
- Healing numbers.
- Status names.
- Defeat markers.
- Invalid player battle actions.

These popups are spawned from `ActionResult.world_changes` and do not mutate world facts.

## Boundaries

- UI reads `BattleSystem.get_summary()`, skill summaries, and action results.
- Skill targeting and area previews still come from `BattleGridOverlay`.
- Battle state changes still flow through `BattleSystem` and `ActionSystem`.
- Rewards, defeat handling, relationship changes, and character removal remain rule-layer responsibilities.
