# Phase 16 Crafting System

## Goal

Add the first long-term item loop without letting UI or data mutate the world directly.

## Runtime Flow

Crafting uses the existing action layer.

1. The menu sends a `CraftAction` with a `recipe_id`.
2. `CraftAction.check()` asks `CraftSystem` for requirement failures.
3. `CraftSystem.execute_craft()` consumes ingredients, adds outputs, saves the player runtime inventory, and returns an `ActionResult`.
4. `ActionSystem` records and publishes the result.

## Added Data

Recipes:

- `data/recipes/debug_tool.json`
- `data/recipes/packed_snack.json`

Crafted items:

- `data/items/debug_tool.json`
- `data/items/packed_snack.json`

Current test recipes:

- `2 x debug_stick -> 1 x Debug Tool`
- `1 x debug_apple + 1 x debug_stick -> 1 x Packed Snack`

## UI

The player menu now has a `Craft` tab.

Each recipe shows:

- description
- required ingredients
- outputs
- whether it can currently be crafted
- a `Craft` button

The button submits `CraftAction`; it does not edit inventory directly.

## Persistence

Crafting changes the player's inventory, then updates `GameState.character_runtime_states`. Existing save/load support therefore persists crafted outputs and consumed materials without a separate crafting save payload.
