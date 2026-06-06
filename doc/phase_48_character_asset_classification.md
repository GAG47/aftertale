# Phase 48: Character Asset Classification

## Goal

This pass prepares character source art for Phase 48 NPC art selection. The active workflow is now batch-first: keep raw source art grouped by import batch, tune the whole batch against the shared body/head base, then perform final classification and runtime naming after visual calibration is stable.

It does not standardize every raw source file into final runtime `std256` textures yet. Batch previews and staging output are used first; the curated common NPC pool can be promoted later.

## Generated Tables

The active JSON files under `tools/art/catalogs/` are:

```text
tools/art/catalogs/character_source_catalog.json
tools/art/catalogs/character_batch_adjustments.json
tools/art/catalogs/character_asset_adjustments.json
```

`character_source_catalog.json` is rebuilt from `assets/art/source`. It includes:

```text
asset_id
source_path
source_kind
batch_id
original_name
standard_part
layer
category
status
review_status
runtime_path
notes
```

`character_batch_adjustments.json` stores shared visual parameters for each `batch_id + standard_part` pair.

`character_asset_adjustments.json` stores only per-asset exceptions. It should stay small; default tuning should happen at batch level first.

Adjustment precedence:

```text
part default target region
  -> batch_id + standard_part adjustment
    -> asset_id adjustment
```

The default target region is the full 256x256 canvas. The pipeline preserves the source canvas instead of cropping to visible pixels, because source batch alignment is meaningful and should not be destroyed by automatic fitting.

## Source Directory Layout

Raw source assets now live under:

```text
assets/art/source/
  apparel/Apparel_v10_/
  body/bodies_v1/
  hair/Hair_v2/
  head/head_v10_/
  weapon/Weapon_v3/
```

Source directories preserve import batch identity. Runtime output remains game-facing and can be renamed later:

```text
assets/art/characters/_staging/
assets/art/characters/hair/
assets/art/characters/outfits/
assets/art/characters/accessories/
```

Rebuild source and batch tables:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\build_character_source_catalog.ps1
```

Update a batch parameter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\set_character_batch_adjustment.ps1 `
  -BatchId "hair/Hair_v2" `
  -Part hair `
  -OffsetY 8 `
  -Scale 0.88
```

Preview a batch without saving temporary values:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "hair/Hair_v2" `
  -Part hair `
  -OffsetY 8 `
  -Scale 0.88 `
  -MaxItems 40
```

Save the same values while generating the preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "hair/Hair_v2" `
  -Part hair `
  -OffsetY 8 `
  -Scale 0.88 `
  -Save
```

After a batch looks correct, write the standardized runtime staging images:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\standardize_character_batch.ps1 `
  -BatchId "hair/Hair_v2" `
  -Part hair
```

The default output comes from `character_source_catalog.json` and currently points to:

```text
assets/art/characters/_staging/hair/
assets/art/characters/_staging/outfits/
assets/art/characters/_staging/accessories/
```

Use `-MaxItems` for a small test run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\standardize_character_batch.ps1 `
  -BatchId "hair/Hair_v2" `
  -Part hair `
  -MaxItems 5
```

The Godot `Character Asset Fitter` reads both `character_batch_adjustments.json` and `character_asset_adjustments.json`. Sliders load the effective values, meaning batch values first and per-asset overrides second. Saving in the fitter writes a per-asset override for the selected source asset.

## Hair Classification

All hair assets are treated as front/down direction source art for now.

Current hair categories:

```text
bangs_heavy
bob
braid
long
medium
short
side_swept
side_tail
special
twin_tail
very_long
```

Current hair counts:

```text
bangs_heavy: 2
bob: 6
braid: 5
long: 15
medium: 6
short: 11
side_swept: 1
side_tail: 5
special: 1
twin_tail: 6
very_long: 1
```

Most hair sources are grayscale or near-grayscale white-hair templates, so the catalog marks them as:

```text
dye_mode: tint
```

This means future runtime or standardization code may recolor them with a hair palette. A few visually black or special hair sources can be changed to `fixed` after manual review if tinting looks wrong.

The current hair files are `single_piece_hair` sources. Aftertale currently has one runtime `hair` layer only. Long hair may need authored shape cleanup later if it should appear to pass behind the body.

## Apparel Classification

Apparel files are split by intended runtime layer:

```text
accessory
back_item
effect
headgear
outfit
```

Current apparel counts:

```text
accessory/head_accessory: 8
back_item/bag: 7
effect/effect: 4
headgear/hat: 19
headgear/helmet: 23
headgear/hood: 2
outfit/armor: 24
outfit/coat_travel: 19
outfit/daily: 29
outfit/robe_dress: 16
outfit/special: 6
outfit/workwear: 19
```

Layer meanings:

```text
outfit: body clothing, robes, armor, dresses, coats
headgear: hats, helmets, hoods, masks
accessory: glasses, hair ornaments, crowns, small head accessories
back_item: backpacks, bags, sacks
effect: shields, banners, visual effects, unusual equipment overlays
```

The first pass is based on filename patterns and visual inspection. The catalog should be manually reviewed before the assets become part of the common NPC random pool.

## Runtime Preparation Flow

Use this order:

```text
raw classified source
-> manual catalog review
-> standardize selected files to 256x256 std canvas
-> place standardized files under assets/art/characters/<layer>/
-> create part definitions for Phase 48 resolver
-> assign by appearance_profile tags
```

Example:

```powershell
cd D:\godotproject\aftertale

powershell -ExecutionPolicy Bypass -File tools\art\standardize_character_part.ps1 `
  -Source assets\art\source\characters\hair\long\hair_long_001_south.png `
  -Output assets\art\characters\hair\hair_long_001_south_std256.png `
  -Part hair
```

The catalog `standard_part` column tells the intended standardization target for each source asset.

## Per-Asset Adjustments

Per-asset adjustments are stored in:

```text
tools/art/catalogs/character_asset_adjustments.json
```

Columns:

```text
asset_id: matches character_source_catalog.json or a hand-authored runtime asset id
source_path: original classified source path
standard_part: intended -Part value
offset_x / offset_y: final placement offset on the 256x256 standard canvas
scale: multiplier applied to the full preserved source canvas
target_x / target_y / target_width / target_height: optional override for the full-canvas mapping region
align: optional override for center/bottom placement
review_status: pending, runtime_needs_visual_review, adjusted, approved
notes: human review notes
```

All offset and target values are in the 256x256 standard canvas coordinate space. A movement of 4 pixels in the table equals about 1 pixel in the 64x64 runtime display.

Example JSON row values:

```text
asset_id: hair_bob_005
offset_x: 0
offset_y: 8
scale: 0.95
review_status: adjusted
notes: move lower, reduce face cover
```

Apply adjustments while standardizing:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\standardize_character_part.ps1 `
  -Source assets\art\source\characters\hair\bob\hair_bob_005_south.png `
  -Output assets\art\characters\hair\hair_bob_005_south_std256.png `
  -Part hair `
  -AssetId hair_bob_005 `
  -AdjustmentsPath tools\art\catalogs\character_asset_adjustments.json
```

## Character Preview Tool

Use `tools/art/preview_character.ps1` to inspect the resolved modular appearance of a character without launching Godot.

Basic preview:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\preview_character.ps1 `
  -CharacterId debug_villager
```

The tool:

- resolves the same common NPC body, outfit, head, hair, and accessory choices as `CharacterAppearanceResolver`;
- renders a 64x64 runtime composite scaled to 4x;
- lists every resolved layer with `asset_id`, runtime texture path, source asset path, dye mode, and modulate color;
- writes preview sheets under `tools/art/previews/`.

Temporary layer tuning can be previewed without changing runtime assets:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\preview_character.ps1 `
  -CharacterId debug_villager `
  -Layer hair `
  -OffsetY 8 `
  -Scale 0.88 `
  -Output tools\art\previews\debug_villager_hair_tune_preview.png
```

When the preview looks right, add `-Save -Regenerate` to write the values into `character_asset_adjustments.json` and regenerate the selected runtime `*_std256.png`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\preview_character.ps1 `
  -CharacterId debug_villager `
  -Layer hair `
  -OffsetY 8 `
  -Scale 0.88 `
  -Save `
  -Regenerate
```

For interactive tuning, use `tools/art/character_art_tuner.ps1`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\character_art_tuner.ps1 `
  -CharacterId debug_villager
```

The tuner opens a Windows form. It runs the preview engine once, lists the resolved layers, and defaults to the first hair layer when one exists. A typical pass is:

```text
1. Select hair: hair_short_010.
2. Drag Scale to 0.88.
3. Drag OffsetY to 8.
4. Watch the preview refresh in the left panel.
5. Click Save + Regenerate when the result is correct.
```

`Save + Regenerate` writes the current values into `character_asset_adjustments.json` and regenerates only the selected runtime texture. Preview images and temporary adjustment tables are written under `tools/art/previews/` and are ignored by git.

## Character Asset Fitter

Use the Godot tool scene when the goal is to fit each source asset against the standard face and body, rather than preview one specific NPC.

```text
scenes/tools/character_asset_fitter.tscn
scripts/tools/character_asset_fitter.gd
```

Open and run the scene from the Godot editor. The tool loads `character_source_catalog.json`, lists source assets by `standard_part`, and previews the selected source asset on the shared body/head base.

The intended workflow is:

```text
1. Filter to hair, outfit, accessory, body, or head.
2. Select an asset, such as hair_short_010 or headgear_helmet_013.
3. Drag Offset X, Offset Y, and Scale.
4. Watch the preview update immediately in memory.
5. Click Save Adjustment to write character_asset_adjustments.json.
6. Click Save + Regenerate to write the adjustment and regenerate that asset's runtime std256 PNG.
7. Use Next / Previous to review the next source asset.
```

This tool does not call PowerShell while dragging sliders. It uses Godot `Image` operations in memory and only writes files when saving or regenerating. The preview is intentionally based on the standard body/head reference so every hair, outfit, and accessory can be calibrated before it enters a random NPC pool.

## Runtime Pool

The first runtime pool is stored in:

```text
data/appearance/common_appearance_parts.json
```

It contains:

```text
body: 1
hair: 13
outfit: 18
accessory/headgear: 7
```

Runtime textures generated in this pass:

```text
assets/art/characters/hair/hair_*_south_std256.png
assets/art/characters/outfits/outfit_*_south_std256.png
assets/art/characters/accessories/headgear_*_south_std256.png
```

The current runtime pool is intentionally small. It is meant to prove the pipeline and improve ordinary NPC readability, not to expose the entire source library at once.

Earlier runtime trials used part-specific target regions and automatic visible-pixel fitting. That approach was retired because it destroyed source batch alignment and produced inconsistent positions across assets from the same batch.

```text
current rule: preserve the complete source canvas
batch rule: tune a batch with shared offset/scale
asset rule: use per-asset overrides only for exceptions
```

Common NPCs now also receive the shared test head texture from the runtime pool, so automatic hair/outfit selection still leaves a visible face when the hair cutout allows it.

## Appearance Resolver

`CharacterAppearanceResolver` is implemented in:

```text
scripts/systems/characters/character_appearance_resolver.gd
```

It is called by `CharacterEntity.configure()` after definition and spawn appearance data are merged.

Resolver behavior:

- Important characters and the player keep authored `appearance.layers` unless `appearance.auto_resolve` is explicitly true.
- Common NPCs get missing runtime layers filled from `common_appearance_parts.json`.
- Existing authored layers are not overwritten.
- Part choice is deterministic from `character_id`, layer, and normalized role.
- Hair parts with `dye_mode: tint` receive the character hair palette through layer `modulate`.
- Guard roles prefer armor outfits and helmet accessories.
- Common guards with helmet accessories do not auto-apply a hair layer, avoiding hair strands leaking from under closed helmets.
- Non-guard roles avoid armor and may receive hats only occasionally.

This makes ordinary NPCs visually richer while keeping important NPC art fully author-controlled.

## Review Notes

- Hair recoloring should start with simple texture `modulate` or a small colorize shader.
- White or grayscale hair is generally safe for `tint`.
- Strongly colored or black hair may need `fixed`.
- Common NPC pools should prefer `rarity: common` and everyday outfit categories.
- Rare armor, royal, fantasy, space, and special equipment should be reserved for important NPCs, guards, enemies, or authored encounters.
- `effect` and `back_item` assets should not be added to ordinary NPC random outfits without an explicit role or activity reason.
- Long hair is still treated as a single `hair` layer in the first pool. Later passes may need authored cleanup for body overlap, but the runtime model remains one hair layer.
- The renderer still uses direct `Image.load()` for development-time PNG loading. Before export, runtime character textures should move to an import-safe resource loading path.

