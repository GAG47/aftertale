# Phase 49: Portrait Badge Map Tokens

## Goal

Use character portraits as the source of identity art, while the map renders compact circular portrait badges. This keeps map readability high and avoids forcing unfinished modular character sprites into production use.

## Runtime Modes

`appearance.display_mode = "badge"` renders a map badge:

- `appearance.portrait.full`: full portrait for character panels and dialogue-style UI.
- `appearance.portrait.badge`: circular transparent map badge generated from the full portrait.
- `appearance.badge_source`: explicit map badge source used by the map renderer.
- `appearance.badge_ring`: outer ring color.
- `appearance.badge_highlight`: inner highlight color.
- `appearance.badge_size`: map badge size in world pixels. The current one-tile default is `28` for a 32px tile.
- `appearance.badge_offset`: optional `{ "x": 0, "y": 0 }` map badge center offset.

`appearance.display_mode` omitted or set to `"modular"` keeps the Phase 48 modular layer renderer.

## Current Test Assignments

- `debug_player`: `player_mage_001`
- `debug_villager`: `npc_merchant_001`
- `debug_guard`: `npc_guard_001`

## Asset Layout

```text
assets/art/characters/portraits/full/
assets/art/characters/portraits/badges/
```

Expected full portrait filenames:

```text
assets/art/characters/portraits/full/player_mage_001.png
assets/art/characters/portraits/full/npc_merchant_001.png
assets/art/characters/portraits/full/npc_guard_001.png
```

Generated badge filenames:

```text
assets/art/characters/portraits/badges/player_mage_001_badge.png
assets/art/characters/portraits/badges/npc_merchant_001_badge.png
assets/art/characters/portraits/badges/npc_guard_001_badge.png
```

## Badge Generation

The crop config lives at:

```text
tools/art/catalogs/portrait_badge_crops.json
```

Generate badges after adding full portraits:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\generate_portrait_badges.ps1
```

For temporary visible placeholders when full portraits are missing:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\generate_portrait_badges.ps1 -CreateMissingPlaceholders
```

Each crop entry uses:

- `center.x`, `center.y`: normalized portrait coordinate of the face center.
- `crop_size`: square crop size as a fraction of the source image's smaller dimension.
- `ring`, `highlight`: badge frame colors.

Adjust these values when a portrait's face is not centered correctly in the generated badge.

## Visual Badge Fitter

Use the Godot tool scene for fast manual cropping:

```text
scenes/tools/portrait_badge_fitter.tscn
```

Workflow:

1. Open `scenes/tools/portrait_badge_fitter.tscn` in Godot and run the scene.
2. Select a portrait entry from the right-side list.
3. Drag the crop square on the source portrait, or tune `Center X`, `Center Y`, and `Crop Size`.
4. Check the circular badge preview.
5. Click `Save + Regenerate`.

The fitter writes back to `tools/art/catalogs/portrait_badge_crops.json` and directly regenerates the badge PNG under `assets/art/characters/portraits/badges/`. The PowerShell generator remains useful for batch regeneration, but normal crop fitting should use this scene.
