# Phase 22 Equipment System

This phase adds a basic equipment loop while keeping item ids, slot ids, and rule references in English.

## Equipment Data

Equippable item definitions can include:

- `equippable`: whether the item can be equipped.
- `equipment_slot`: the target slot id, such as `weapon` or `tool`.
- `attribute_bonuses`: flat bonuses applied while equipped.

Player-facing item names and descriptions can be localized, while internal ids stay stable for rules and data references.

## Runtime Rules

Equipment changes go through the action system:

- `EquipItemAction`: removes one item from inventory, equips it to its slot, and returns any replaced item to inventory.
- `UnequipItemAction`: removes the equipped item from a slot and returns it to inventory.

Equipped item definitions are saved in character runtime state, so equipment survives save/load.

## Battle Integration

Characters now expose effective attributes: base attributes plus equipment bonuses.
Battle units and skill formulas read effective attributes for speed, HP, damage, and healing.
Vitality bonuses also increase derived max HP, so tool and armor bonuses affect battle units without requiring each item to write a direct `max_hp` bonus.

## Line Of Sight

Ranged and targeted skills now require line of sight. Targets behind blocking terrain or blocking objects are filtered out of target previews and rejected during skill execution.

This is still a simple grid line check. It does not yet model partial cover, directional cover, height, or projectile arcs.

## Player-Facing Loop

The player menu now exposes the equipment loop:

- Equippable inventory stacks show an Equip button.
- Equipped slots show display names, attribute bonuses, and Unequip buttons.
- Character attributes show base values and effective values when equipment changes them.

The starting player carries `debug_training_sword`, and crafted `debug_tool` can also be equipped. This gives the test route a concrete equipment progression without making UI code mutate inventory or stats directly.

## Completion Notes

Phase 22 is considered complete when:

- Equipping removes one item from inventory and fills the correct slot.
- Replacing equipment returns the previous item to inventory.
- Unequipping returns the item to inventory.
- Equipment survives save/load through character runtime state.
- Battle units and skill formulas read effective attributes.
- Ranged/targeted skills reject blocked line of sight.

These rules are implemented as part of the reusable equipment framework, not as one-off test-scene behavior.
