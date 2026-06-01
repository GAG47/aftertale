# Phase 23 Playable Vertical Slice

This phase turns the existing rule systems into a playable route without bypassing the architecture.

## Goal

The player should be able to play a basic route without opening the debug panel:

1. Start in `test_field`.
2. Open the menu and equip the starting training sword.
3. Talk to the villager and accept the apple request.
4. Pick up the apple and report back to complete the quest.
5. Pick up seeds, plant them on field plots, water them, rest until mature, and harvest herbs.
6. Travel east to `test_clearing`.
7. Pick up sticks, return to the menu, craft a tool or snack, and equip the tool if desired.
8. Talk to the guard for route context.
9. Fight the training dummy using the tactical battle controls.
10. Return to the field stall and sell gathered or crafted goods.
11. Save and load from the System tab.

## Presentation Changes

The bottom interaction prompt now reads the current rule-backed interaction:

- Pick up drops on the current cell.
- Plant, water, wait for, or harvest crops.
- Talk to interactable NPCs.
- Attack combatable targets.
- Use, pick up, or inspect faced objects.
- Point out exits by movement instead of treating them as direct UI actions.

This prompt does not change world state. It asks the current scene for a summary of what the existing action selection would do.

## Test Route Data

The slice uses the existing field and clearing:

- `debug_player` starts with `debug_training_sword`.
- `test_field` contains the villager, apple, seed pouch, field plots, field stall, and guidance sign.
- `test_clearing` contains sticks, a guard, usable/inspectable objects, and `debug_training_dummy`.
- `debug_training_dummy` is a combat-only target so the guard can remain a conversation NPC.

## Boundaries

This is not a throwaway minimum loop. Each interaction still enters through existing systems:

- Player inputs submit actions or battle requests.
- UI submits equipment, crafting, trade, save, and load requests through systems.
- Quest progress watches action results and world changes.
- Crops are owned by `CropSystem`.
- Currency and market rules are owned by `BusinessSystem`.
- Equipment is owned by `EquipmentSlots` and changes through equip/unequip actions.
- Battle state is owned by `BattleSystem`.

Later visual polish can replace debug shapes, colors, panels, and prompts without changing the rule contracts established here.

## Acceptance Checklist

- The player can understand the next local interaction from the prompt.
- The route can be completed without the debug panel.
- At least one quest, one crop cycle, one craft, one equipment change, one trade, and one battle can occur in one session.
- Save/load preserves inventory, equipment, quest state, crop state, currency, removed drops, and defeated characters.
- No presentation element directly mutates world facts.
