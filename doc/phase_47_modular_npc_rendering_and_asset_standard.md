# Phase 47: Modular NPC Rendering And Asset Standard

## Goal

Phase 47 turns character presentation from one procedural token into a modular appearance framework.

This phase is the foundation for NPC art work. It does not attempt to finish the common NPC art library. Phase 48 will build that library and use tags to select parts for ordinary NPCs.

## Implemented Scope

Implemented in this phase:

- `CharacterEntity` now accepts optional `appearance_profile` and `appearance` dictionaries from character definitions or spawn overrides.
- `CharacterEntity.get_summary()` exposes both dictionaries for debug inspection.
- `CharacterAppearanceRenderer` draws characters through a fixed layer order.
- The renderer has procedural fallback layers, so the game still runs without PNG assets.
- Individual layers can already be replaced by 64x64 transparent PNGs through `appearance.layers`.
- Activity state can influence the procedural held item layer.
- Existing training dummy rendering remains special-cased.
- External transparent PNG parts can be normalized into the shared 256x256 standard canvas with `tools/art/standardize_character_part.ps1`.
- Location cameras now support scene zoom for art inspection: mouse wheel or `+` zooms in, `-` zooms out, and `0` resets to the scene default zoom.
- Keyboard camera panning updates the camera target for both taps and held input; the camera position reaches that target through the shared smoothing path.

## Runtime Layer Order

The renderer uses this order:

```text
shadow
body
outfit
head
face
hair
accessory
held_item
status_overlay
```

`status_overlay` remains partly handled by `CharacterEntity` for battle, interactable, combatable, and facing markers.

## Scene Layering

The character layer is now a separate scene layer with y-sort enabled.

Current scene presentation order:

```text
DebugTileRenderer           z -100
FloorDecorationRenderer     z -50
Objects                     z 0
StructureRenderer           z 5
Characters                  z 10, y-sort enabled
BuildingRenderer / roofs    z 30
```

`StructureRenderer` draws walls, doors, windows, signs, fences, and other standing structures that should sit behind the visible height of characters. This prevents taller 1.3-grid character sprites from having their heads hidden by front walls.

`BuildingRenderer` now draws roofs only in `test_village`, so roofs can still sit above characters and preserve building occlusion.

Characters use the same child `z_index` under `Characters`, so y-sort determines character-to-character overlap. Lower characters render above upper characters, avoiding the feeling that upper characters stand on top of lower characters.

## Asset Standard

Current maps use `tile_size: 32`.

Character art should use:

```text
source canvas: 512x512 px or 1024x1024 px
standard part canvas: 256x256 px
runtime display canvas: 64x64 px
standard grid anchor: (128, 184)
runtime grid anchor: (32, 46)
display footprint: one 32x32 grid cell
primary direction for v47/v48: down/front
background: transparent
normal visual height: 42-46 px
head height: 14-16 px
body and outfit height: 28-30 px
```

The standard part canvas is four times the runtime display canvas. Pixel `(128, 184)` in the 256x256 source corresponds to runtime pixel `(32, 46)` and aligns to `LocationGrid.grid_to_world(cell)`.

Collision and pathfinding still use one grid cell. The sprite can extend above that cell to create a standing character silhouette.

Recommended visual allocation inside a 64x64 part:

```text
y  2-8: tall hair, hats, or special accessories
y  8-24: head and hair mass
y 24-28: neck and shoulder transition
y 28-50: body, outfit, armor, robe, apron
y 46: grid anchor
y 48-54: lower outfit, shadow, small props
```

The target body proportion is not a large-headed chibi token. The intended ratio is roughly:

```text
head : body/outfit = 1 : 1.8 to 1 : 2
```

This gives clothing enough readable space while keeping the character compact on a 32px tile map.

Every part should keep the same 256x256 canvas, even if the visible pixels are small. Stable full-canvas parts are easier to layer than tightly cropped sprites.

## Standardization Tool

AI or external art does not need to hit the Aftertale anchor perfectly. It should have a transparent background and be roughly centered. Before entering the game, run the standardization tool:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\standardize_character_part.ps1 `
  -Source source.png `
  -Output assets\art\characters\head\example_head_std256.png `
  -Part head
```

Supported part types:

```text
body
head
hair
outfit
accessory
held_item
```

The tool:

- preserves the full source canvas;
- scales the full source canvas into the 256x256 standard canvas;
- applies optional batch/asset `offset_x`, `offset_y`, and `scale` values;
- writes a 256x256 transparent PNG using the shared `(128, 184)` anchor standard.

This is the intended bridge between AI-generated art and the strict in-game layering format.

The tool does not split a complete character illustration into separate layers. Hair, head, outfit, held items, and accessories should be exported or cut out as separate transparent PNGs first. Runtime rendering only stacks already-prepared parts.

The current Ratkin test parts are examples of this flow:

```text
assets/art/characters/body/body_axolotl_male_01_south.png
assets/art/characters/head/rk_test_head_01_south.png
assets/art/characters/hair/rk_test_hair_long_b_south.png
assets/art/characters/outfits/rk_test_garden_wear_south.png
```

Their standardized runtime sources are:

```text
assets/art/characters/body/body_axolotl_male_01_south_std256.png
assets/art/characters/head/rk_test_head_01_south_std256.png
assets/art/characters/hair/rk_test_hair_long_b_south_std256.png
assets/art/characters/outfits/rk_test_garden_wear_south_std256.png
```

The standardization tool no longer crops to non-transparent pixels. If a hair asset sits too high or low after standardization, adjust the source batch or asset offset, then regenerate the `*_std256.png` file.

## Supported Texture Override Format

An important NPC or future asset resolver can override individual layers:

```json
{
  "appearance": {
    "layers": {
      "hair": {
        "source": "res://assets/art/characters/hair/hair_short_01.png"
      },
      "outfit": {
        "source": "res://assets/art/characters/outfits/outfit_guard_militia_01.png"
      },
      "held_item": {
        "source": "res://assets/art/characters/held_items/held_spear_01.png"
      }
    }
  }
}
```

Layer source files should follow the 256x256 standard part canvas and `(128, 184)` anchor standard. The renderer displays the full standard part canvas inside the 64x64 runtime character canvas.

## Appearance Profile

`appearance_profile` describes who the character is. It is intended for Phase 48 tag-driven part selection.

Example:

```json
{
  "appearance_profile": {
    "importance": "common",
    "role": "guard",
    "gender_hint": "neutral",
    "age_hint": "adult",
    "wealth": "common",
    "culture": "village",
    "neatness": "high",
    "faction": "militia"
  }
}
```

If a character does not define a profile, `CharacterEntity` fills defaults from `identity` and `character_kind`.

## Appearance Data

`appearance` describes the selected parts or custom parts.

For v47, ids are mostly documentation and procedural hints. In Phase 48, they should resolve to actual part definitions.

Example:

```json
{
  "appearance": {
    "body_id": "body_common_01",
    "head_id": "head_round_01",
    "hair_id": "hair_short_neat_01",
    "outfit_id": "outfit_guard_militia_01",
    "accessory_ids": [],
    "held_item_id": "held_spear_01",
    "palette": {
      "skin": "#e8c49d",
      "hair": "#2f2c28",
      "outfit": "#65717d",
      "trim": "#cfc08a"
    }
  }
}
```

If `held_item_id` is omitted, the procedural renderer may infer simple activity props:

- `work` -> hoe;
- guard `patrol` or `train` -> spear;
- `shopkeep` -> ledger;
- `social` or `eat` -> tray.

This is only a visual hint. It does not change inventory or equipment.

## Naming Standard

Recommended ids and filenames:

```text
body_common_01
body_slim_01
body_short_01

head_round_01
head_soft_01

hair_short_01
hair_short_neat_01
hair_bangs_01
hair_long_01
hair_twin_tail_01

outfit_villager_common_01
outfit_farmer_work_01
outfit_guard_militia_01
outfit_merchant_common_01
outfit_clergy_plain_01
outfit_scholar_common_01

accessory_glasses_round_01
accessory_hat_farmer_01

held_hoe_01
held_spear_01
held_book_01
held_broom_01
held_tray_01
held_bag_01
```

Texture files should live under:

```text
assets/art/characters/body/
assets/art/characters/head/
assets/art/characters/hair/
assets/art/characters/outfits/
assets/art/characters/accessories/
assets/art/characters/held_items/
```

## AI Asset Guidance

AI may be used to generate candidates, but final in-game parts must be standardized:

- transparent background;
- 256x256 standardized part;
- same `(128, 184)` standard anchor;
- ordinary character body proportion near `head : body/outfit = 1 : 2`;
- front/down direction only for v47/v48;
- consistent outline and shading;
- no unrelated background, text, watermark, or UI ornament;
- no tightly cropped sprite canvases.

Important NPCs may use custom generated parts, but they must still follow this same canvas and anchor standard.

For practical AI workflows, a good prompt/output target is "one isolated transparent-background part, centered on canvas" rather than "a complete character sprite". The alignment does not need to be exact at generation time; the standardization tool is the place where Aftertale-specific anchors are applied.

## Scene Zoom For Art Review

Scene zoom is a development convenience added alongside the modular character art pass so small character details can be checked in game.

Controls:

```text
Mouse wheel up / + / keypad +: zoom in
Mouse wheel down / - / keypad -: zoom out
0: reset to the current scene default zoom
```

The zoom is applied to the active location `Camera2D` only. It does not change map tile size, collision, pathfinding, character scale, or asset standards.

## Phase 48 Boundary

Phase 48 should add:

- a small common NPC asset catalog;
- part definitions with tags;
- deterministic tag-based selection for ordinary NPCs;
- role/activity mapping for held items;
- optional validation for missing part ids or missing texture paths.

