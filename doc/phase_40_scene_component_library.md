# Phase 40: Scene Component Library

## Goal

`test_village` was no longer only a movement test map. It needed to become a small RPG village prototype where the player can quickly recognize residential, workshop, shop, tavern, farm, plaza, wilderness gate, and training areas.

The previous version relied too much on one-off map drawing and colored building roofs. That made the scene hard to read and hard to expand. This phase introduces a small code-generated scene component library so future scenes can reuse the same visual language instead of rebuilding every village from temporary drawing code.

## What Changed

Added `scripts/systems/scenes/scene_component_library.gd`.

The scene now follows a clear layer model. Conceptually it still keeps floor, lower decoration, interaction / structure, and roof separate; in data it uses five explicit draw passes so floor-like overlays do not get mixed with either terrain characters or standing structures:

- Floor layer: everything under the character's feet. This includes grass, paths, plaza stone, farmland, training ground, building floors, and exits. Floor-internal details such as farmland grooves, plaza stone seams, and path pebbles belong to this layer.
- Floor overlay layer: optional floor-like overlays placed above terrain but below characters, such as building foundations and door steps. These are still part of the floor presentation, not standing structures. The current `test_village` keeps this list empty to avoid adding rough placeholder slabs in front of buildings.
- Floor decoration layer: non-blocking details placed on top of the floor without changing floor meaning, such as flower patches, small stones, grass clumps, flower pots, mailboxes, buckets, and extra road pebbles.
- Structure / object layer: things standing on the floor. This includes building walls, doors, windows, fences, signposts, counters, beds, workbenches, save points, shop counters, and other interactive or blocking objects.
- Roof layer: visual-only building roofs. Roofs do not define collision or interaction, and they disappear when the player is inside their configured hidden area.

The render order follows that model: floors, floor overlays, and floor decorations are drawn below objects and characters. Structures and roofs are drawn above the floor layers.

After the modular NPC presentation pass, standing structures and roofs are split into separate scene renderers:

- `StructureRenderer` draws walls, doors, windows, signs, fences, and other standing structures below characters.
- `Characters` is a dedicated y-sorted layer above structures.
- `BuildingRenderer` draws roofs above characters.

This keeps taller character sprites readable in front of building walls while preserving roof occlusion. It also gives character-to-character overlap the expected order: lower characters render above upper characters.

The library groups scene drawing into semantic components:

- Ground components: grass, path, plaza stone, house floor, workshop floor, shop floor, tavern floor, building wall, door floor, field plot, training ground, and exit marker.
- Building components: grid-aligned building bodies, rectangular roofs, facade strip, door, sign label, and roof-open hint when the player is inside a building.
- Prop components: windows, flower pots, mailbox, workbench, anvil, tool rack, material crates, shop sign, shelf, counter, goods crate, table set, barrel, stove, scarecrow, bucket, farm tool, fence, fountain, notice board, bench, signpost, target, training dummy, weapon rack, stump, grass clump, and stone.
- Zone hints: lightweight area outlines for residential, workshop, shop, tavern, farm, plaza, wilderness gate, and training zones.

`DebugTileRenderer` now delegates ground tile drawing to the component library.

`BuildingRenderer` now delegates floor decoration, structure, roof, and zone hint drawing to the component library. It supports dedicated `floor`, `structures`, and `roofs` render modes in addition to compatibility modes. This lets a location split lower building structure and upper roof occlusion without changing the data format or interaction system.

`LocationGrid` now supports structure blockers generated from explicit `structures` rows. This keeps floor tiles and movement collision separated:

- `tiles` describe the floor layer, including indoor building floors.
- `floor_overlays` describe optional floor-like visual overlays such as foundations and steps. The key exists even when the current scene does not use overlays.
- `floor_decorations` describe non-blocking visual details.
- `structures` describe walls, windows, doors, fences, signposts, and other things standing on the floor.
- Structure rows may opt into movement and sight blocking with `blocks_movement` and `blocks_sight`.
- `wall_ring` is available for simple building perimeter walls. It draws and blocks the outer ring while `exclude_cells` opens door cells.
- `roofs` describe visual roofs and their `hide_bounds`.

## test_village Update

`data/locations/test_village.json` was rebuilt as a larger 28x17 village layout.

The `tiles` rows now describe all floor materials. Building floors remain in `tiles` because they are still floor. Building walls and fences were removed from terrain and moved to `structures`, where their collision is explicit.

The top row contains four larger layered buildings. Each building now uses one `wall_ring` for its perimeter wall instead of mixing a wall ring with duplicate one-off wall cells:

- Residential house: house floor tiles, one wall ring, windows, door, roof hide bounds, flower pot, mailbox, and bed interaction.
- Workshop: workshop floor tiles, one wall ring, window, door, roof hide bounds, anvil, material crates, and crafting interaction.
- Shop: shop floor tiles, one wall ring, window, door, roof hide bounds, shop sign, goods crate, and shop interaction.
- Tavern / dining hall: tavern floor tiles, one wall ring, window, door, roof hide bounds, barrel, table, and paid inn rest interaction.

The lower and center areas are separated by function:

- Farm: field plots, fence line, scarecrow, bucket, farm tool, and test seed pickup.
- Plaza: stone ground, fountain, notice board, benches, and save point.
- Wilderness gate: road extension, signpost, fence gap, exit marker, and return entrance from the wild.
- Training area: packed dirt, weapon rack, target, stump, visual dummy, and combat test dummies.

Buildings are no longer just roof color swaps. Each functional area now has 1-3 visual anchors that communicate its purpose.

## Interaction Safety

Interactive facilities are still defined in `objects`.

Floor-like visual overlays can be defined in `floor_overlays`. Decorative floor details are defined in `floor_decorations`. Both are only drawn by the lower renderer, so they stay below the player and do not accidentally block movement or become usable facilities. `test_village` currently leaves `floor_overlays` empty because the placeholder foundation and step blocks made the building fronts visually noisy.

Wall and fence collision is generated from explicit `structures` rows rather than from terrain characters or guessed building bounds. If a visible structure should block the player, it says so directly. Doors remain non-blocking. This keeps beds, workbenches, counters, and indoor NPC schedule points reachable while still preventing the player from walking through walls and fences.

Building walls currently use a simple gray placeholder block. Detailed brick, beam, and pixel-art wall variants are intentionally deferred to phase 41.

The existing systems remain in place:

- Player movement
- NPC display and schedules
- E / Enter investigation and facility interaction
- Shop opening
- Crafting workbench opening
- Save point
- Bed and inn rest
- Scene exit to the wild
- B inventory, J quests, C character, ESC system menu

## Not Done Yet

This phase does not add:

- AI-generated towns
- Procedural town generation
- External art assets
- Final tile art
- Image-based sprite assets
- New UI systems
- Complex NPC schedules
- New save data structures
- Large architecture rewrites

The purpose is to establish a reusable code-generated visual grammar for scenes, not to finish final production art.

The project direction remains code-drawn art. Future phases can refine these draw functions into more detailed pixel-style components without switching to imported image assets.
