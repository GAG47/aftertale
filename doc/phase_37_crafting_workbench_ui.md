# Phase 37 - Crafting Workbench UI

## Goal

This phase upgrades the workbench from a generic facility list into a dedicated crafting interface and adds batch crafting quantity support.

## Implementation Scope

- Rebuilt the crafting facility UI as a two-column workbench screen.
- Added recipe filters for all recipes, craftable recipes, tools, and food.
- Added a recipe list with selected-row highlighting and craftability status.
- Added a recipe detail panel with output, material requirements, owned counts, and shortage state.
- Recipe lists and material requirements use bounded scroll areas so long recipe or material sets do not stretch the workbench window.
- Added crafting quantity controls.
- `CraftAction` now accepts a `quantity` target field.
- `CraftSystem` now validates, consumes ingredients, adds outputs, and reports world changes using the requested quantity.
- Existing single-craft calls remain compatible because quantity defaults to 1.
- Shop facilities continue to use the facility panel's trade list.

## Rules

- The UI never mutates inventory directly. It submits `CraftAction`.
- Batch crafting checks the full multiplied material requirement before execution.
- Batch crafting simulates inventory capacity after ingredient consumption and before adding outputs.
- Crafting success keeps the workbench open and refreshes the recipe list and detail state.
- Missing-material recipes remain selectable so the player can inspect what is missing.

## Related Files

- `scripts/ui/facility_panel.gd`
- `scripts/systems/actions/craft_action.gd`
- `scripts/systems/crafting/craft_system.gd`
