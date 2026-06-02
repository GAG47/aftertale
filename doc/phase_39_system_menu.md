# Phase 39 - System Menu

## Goal

Finish the last piece of the old player-menu split by replacing the remaining tabbed menu with a focused system menu.

## Scope

The system menu is now a session-control UI, not a gameplay panel.

Main actions:

- Continue Game
- Settings
- Return To Title
- Quit Game

## Runtime Behavior

- `Esc` closes any active gameplay panel first.
- If no panel needs to close, `Esc` opens the system menu.
- Continue Game closes the system menu and restores the previous game mode.
- Settings opens a small settings view with:
  - master volume slider;
  - fullscreen toggle;
  - back button.
- Return To Title asks for confirmation before leaving the current session.
- Quit Game asks for confirmation before calling `get_tree().quit()`.

## Title Screen

Returning to title unloads the current scene, pauses time, and shows a minimal title screen:

- New Game
- Continue Game
- Quit Game

New Game starts a fresh session and reloads the current test field entry point. Continue Game loads the existing save if one is available.

## Notes

The old tabbed player menu no longer exposes inventory, crafting, business, quests, character, or save controls. Those features now live in their dedicated panels or interaction facilities.
