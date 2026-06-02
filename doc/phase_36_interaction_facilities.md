# Phase 36 - Interaction Facilities

## Goal

This phase removes the old player menu from the normal input path and moves crafting, business, resting, and save-point access onto map interaction objects.

## Implementation Scope

- Removed the `Tab` / `I` player-menu toggle from runtime input handling.
- Kept `B`, `J`, and `C` as the direct entries for inventory, quests, and character management.
- Added a facility interaction signal from location scenes to the UI root.
- Added a dedicated facility panel for interaction-object workflows.
- Workbench facilities open crafting actions and can limit the visible recipe list.
- Shop facilities open trading actions through a specific shop id.
- Facility actions still submit normal `CraftAction` and `TradeAction` instances, so crafting and trading continue to use the action system.
- Rest facilities submit `RestAction` from the map interaction layer.
- Bed rest advances time to the next morning and fully restores the current party members present on the map.
- Campfire rest advances a fixed amount of time and partially restores the current party members present on the map.
- Inn rest charges currency, advances time to the next morning, and fully restores the current party members present on the map.
- Save-point facilities call the existing save system from map interaction.
- Added a test-field workbench for `debug_tool` and `packed_snack`.
- Added a test-field stall object bound to the existing `field_stall` shop.
- Added test-field bed, campfire, inn counter, and save-point objects.
- Removed `Tab/I` menu wording from the active exploration prompt.

## Rules

- Crafting is accessed through a map object with `facility_type: "crafting"`.
- Trading is accessed through a map object with `facility_type: "shop"` and a `shop_id`.
- Resting is accessed through a map object with `facility_type: "rest"` and a `rest_type`.
- Save points are accessed through a map object with `facility_type: "save"`.
- Facility objects are usable map objects, but they do not run `UseItemAction`.
- Pressing `E` / `Enter` on a crafting or shop facility opens the relevant facility panel.
- Pressing `E` / `Enter` on a rest facility submits `RestAction` immediately.
- Pressing `E` / `Enter` on a save-point facility saves through `SaveManager`.
- `R` remains a simple wait action and does not restore HP.
- Pressing `Esc` closes the facility panel before falling through to other cancellation behavior.
- The old game menu script remains in the project for reference, but it is no longer reachable through `Tab` / `I`.

## Related Files

- `scripts/core/input_manager.gd`
- `scripts/core/main.gd`
- `scripts/ui/ui_root.gd`
- `scripts/ui/facility_panel.gd`
- `scripts/systems/scenes/location_root.gd`
- `scripts/systems/scenes/location_object.gd`
- `scenes/ui/screens/ui_root.tscn`
- `data/locations/test_field.json`
