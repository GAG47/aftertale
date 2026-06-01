# Phase 25 Map Character And Interaction Presentation

This phase continues the board-facing presentation work started in Phase 24.

## Scope

- Keep NPC portraits and final chibi art out of this phase.
- Replace map character debug dots with reusable procedural tokens.
- Add facing and movement feedback for map characters.
- Add a visual highlight for the current exploration interaction target.
- Keep all gameplay changes inside existing actions and systems.

## Character Tokens

`CharacterEntity` now draws a compact token instead of a flat debug circle:

- Player, villagers, guards, companions, and enemies use different readable palettes.
- Training dummies use a simple wooden target token.
- Interactable characters keep a small yellow badge.
- Combatable characters keep a small red badge.
- Defeated characters draw a clear crossed-out overlay.
- A small direction marker shows the character's current facing.

The token is still procedural and data-driven. It is intended as a replaceable placeholder for later AI-generated portrait/chibi assets.

## Movement Feedback

Grid position remains the rule source of truth, but `CharacterEntity` now tweens its visual position briefly when `set_grid_position` changes the cell.

This makes player and scheduled NPC movement easier to read without changing pathing, collision, exits, schedules, or action results.

## Interaction Highlight

`InteractionTargetOverlay` draws a soft pulsing highlight on the cell that the current primary action would affect.

The overlay follows the same priority as the text prompt:

- Pick up drops on the current cell.
- Plant, water, inspect, or harvest crops on the current cell.
- Talk to interactable faced characters.
- Attack combatable faced characters.
- Pick up, use, or inspect faced objects.
- Show faced exits.
- Fall back to the faced inspection cell.

The overlay clears outside exploration mode and does not directly mutate scene, inventory, crop, quest, battle, or save state.

## Boundaries

- Character tokens read character identity and state only.
- Movement animation follows already-approved grid changes.
- Interaction highlighting mirrors action selection but never submits actions.
- Battle targeting remains owned by `BattleGridOverlay` and `BattleSystem`.
- Future art can replace token drawing without changing rule contracts.
