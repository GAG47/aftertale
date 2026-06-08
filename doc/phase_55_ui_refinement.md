# Phase 55: UI Refinement

## Status

Complete.

## Goal

Split the monolithic UI into independent, editable scenes. Fixed UI structure
must be visible and adjustable in the Godot editor instead of being generated
by scripts at runtime.

## Target Structure

```text
scenes/ui/
  screens/
	ui_root.tscn
	battle_hud.tscn
	inventory_screen.tscn
	character_screen.tscn
	quest_screen.tscn
	facility_screen.tscn
	game_menu_screen.tscn
  components/
	dialogue_panel.tscn
	battle_turn_item.tscn
	status_icon.tscn
	inventory_item_cell.tscn
	quest_list_item.tscn
	party_member_item.tscn
	facility_crafting_view.tscn
	facility_shop_view.tscn
	reusable primitive components
```

`UIRoot` only owns shared overlays, loads the independent screens, switches
their visibility, and forwards signals.

## Rules

- Panels, buttons, labels, bars, anchors, margins, and styles belong in `.tscn`.
- Screen scripts only bind data, update state, and emit user actions.
- Fixed screen structure must not use `Control.new()` or `Button.new()`.
- Dynamic creation is limited to variable-length items such as inventory rows,
  turn-order portraits, status icons, and generated lists.
- Each screen must be independently openable and editable in Godot.
- Shared visual rules move into reusable themes and component scenes.

## Migration Order

1. Extracted the battle HUD into `battle_hud.tscn`.
2. Extracted inventory, character, quest, facility, and game-menu screens.
3. Converted repeated UI items into reusable component scenes.
4. Reduced `ui_root.tscn` to screen composition and shared overlays.
5. Removed direct UI control construction from `scripts/ui`.
6. Preserved existing screen signals and data refresh entry points.

## Battle HUD Boundary

The battle HUD scene owns:

- turn order;
- current character information;
- four skill slots;
- HP, MP, AP, and status display;
- end-turn command;
- optional AI debug panel.

Battlefield tile states and targeting ranges remain map-rendered information.

## Completion Criteria

- Major screens are independent `.tscn` scenes.
- Fixed screen controls are no longer generated at runtime.
- Opening a screen scene in Godot shows its actual editable layout.
- `UIRoot` no longer contains the full node trees of every screen.
- Existing UI actions and data refresh behavior continue to work.

## Verification

- Godot 4.6.3 completes a headless main-scene startup.
- Godot editor filesystem scanning reports no script parse errors.
- `git diff --check` passes.
- `scripts/ui` contains no direct construction of `Button`, `Label`,
  `PanelContainer`, layout containers, sliders, progress bars, or other UI
  controls. Variable-length content uses `PackedScene.instantiate()`.
