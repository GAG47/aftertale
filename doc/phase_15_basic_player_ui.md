# Phase 15 Basic Player UI

## Goal

Provide a usable player-facing menu so common state can be checked without opening the debug panel.

## Menu

Open with `Tab` or `I`.

Tabs:

- `Inventory`: item name, quantity, type, usable marker, and description
- `Quests`: quest status, objective progress, failed reason when present
- `Character`: identity summary, HP, position, attributes, and equipment slots
- `System`: resume, save, load, save status, and control reference

## Save And Load

The system tab calls the existing `SaveManager`.

- `Save`: writes to `user://saves/slot_1.json`
- `Load`: reads from `user://saves/slot_1.json`
- `Resume` and `Close`: return to exploration through `UIRoot`, preserving the existing menu mode rules

## Notes

This is a functional UI pass, not a final visual skin. It keeps the existing Godot Control structure and data summaries so later art, icons, and layout polish can replace presentation without changing gameplay systems.
