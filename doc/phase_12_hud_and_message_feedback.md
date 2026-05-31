# Phase 12: HUD And Message Feedback

This phase separates player-facing feedback from the debug panel.

It does not build the full game UI suite yet. Inventory UI, character status UI, quest journal UI, and battle HUD should be designed together later.

## Goals

- Keep the top status bar as formal game UI.
- Add a lightweight message log for recent world feedback.
- Stop relying on the debug panel for normal play feedback.
- Keep the debug panel available but less intrusive.

## Runtime UI

`UIRoot` now owns:

- top status bar
- `MessageLogPanel`
- debug panel
- dialogue panel

`MessageLogPanel` displays the latest player-facing feedback from action results.

## Message Source

`UIRoot` listens to:

- `ActionSystem.action_executed`
- `ActionSystem.action_failed`

It sends action feedback into `MessageLogPanel`.

To avoid noise, the message log filters out routine successful updates:

- `MoveAction`
- `BattleMove`
- `BattleTurnStart`
- `ScheduleUpdate`

Failures and meaningful results still show.

## Debug Panel

The debug panel remains developer-facing. It has been moved to the right side so it no longer covers the normal message area as aggressively.

## Boundary

This phase intentionally does not implement:

- inventory screen
- quest journal
- character sheet
- battle command UI
- mouse-driven tactical controls

Those should be handled as a later unified UI pass.
