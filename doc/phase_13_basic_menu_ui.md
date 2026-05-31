# Phase 13: Basic Menu UI

This phase adds a lightweight menu for player-facing state inspection.

It is not the final UI art pass. It uses Godot native controls and keeps the structure ready for later inventory, quest, character, equipment, and crafting workflows.

## Controls

- `Tab`: open or close the menu
- `I`: open or close the menu
- `Esc`: close the menu if it is open

The menu opens only from exploration or menu mode. Dialogue and combat keep their own interaction flow.

## Pages

### Inventory

Shows current controlled character inventory:

- item name
- quantity
- item type
- description

No use/drop/equip actions are implemented in this phase.

### Quests

Shows accepted and completed quests:

- quest name
- status
- objective progress
- objective completion markers
- failure reason when present

### Character

Shows controlled character state:

- name
- kind
- faction
- HP
- position and facing
- core attributes
- equipment slots

## Runtime Behavior

Opening the menu sets `GameState` to `MENU`.

Closing the menu restores exploration mode.

The debug panel remains separate and can still be toggled with `F3`.

## Boundary

This phase intentionally does not add:

- item usage from UI
- equipment changes
- quest tracking pins
- full character sheet styling
- final UI theme or art assets

Those should be handled after the information structure proves useful.
