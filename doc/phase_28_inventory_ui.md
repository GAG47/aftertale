# Phase 28 Inventory UI

## Goal

Phase 28 separates the backpack from the old tabbed player menu and gives it a dedicated game-facing screen. The first version focuses on making inventory browsing feel like a real RPG interface while keeping inventory facts owned by existing systems and actions.

## Player Flow

- Press `B` to open or close the backpack.
- Press `Esc` to close the backpack.
- Use category buttons to filter items.
- Use the sort menu to change display order.
- Hover or click an item grid cell to inspect it.
- Use detail-panel buttons to submit available item actions.

## UI Structure

The backpack is implemented as `InventoryPanel` under `UIRoot`.

- Header: title, currency, close button.
- Filter row: `全部`, `装备`, `食物`, `材料`, `种子`, `任务`, `其他`.
- Sort menu: default order, name, quantity, category.
- Grid area: scrollable item cells with centered item marker and bottom-right quantity.
- Detail area: selected item name, category, quantity, description, effects, and available actions.

## Rule Boundary

The inventory UI does not directly mutate inventory, equipment, attributes, currency, quests, or world state.

It reads:

- `CharacterEntity.inventory.get_summary()`
- `BusinessSystem.get_currency(character_id)`
- item summary fields such as `item_type`, `quantity`, `description`, `equippable`, `is_usable`, and `attribute_bonuses`

It submits:

- `UseItemAction`
- `EquipItemAction`

The underlying action and system layers remain responsible for validation, persistence, inventory changes, equipment changes, and feedback.

## Notes

The UI presents inventory as an unlimited scrollable grid. Existing system-level inventory capacity is not surfaced in the panel. Crafting and business remain in the old menu for now, but the intended next step is to move those flows to scene objects such as workbenches and stalls.
