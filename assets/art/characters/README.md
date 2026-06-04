# Character Art Asset Standard

NPC modular parts use a fixed 256x256 transparent standard canvas, then render into a 64x64 runtime character canvas.

Required standard:

```text
standard part canvas: 256x256 px
runtime display canvas: 64x64 px
standard grid anchor: (128, 184)
runtime grid anchor: (32, 46)
direction: down/front for the first version
footprint: one 32x32 grid cell
normal visual height: 42-46 px
head: 14-16 px
body and outfit: 28-30 px
```

Directory plan:

```text
body/
head/
hair_front/
hair_back/
outfits/
accessories/
held_items/
```

Every exported PNG should keep the full 256x256 standard canvas. Do not crop final in-game parts to visible pixels.

The source drawing or AI generation canvas can be 512x512 or 1024x1024. Before using it in game, standardize it with:

```powershell
powershell -ExecutionPolicy Bypass -File tools\art\standardize_character_part.ps1 -Source source.png -Output output_std256.png -Part head
```

The standardization tool reads the alpha channel, crops the visible content, and places it into the correct target region on a 256x256 transparent canvas.

The tool does not automatically split a complete character image. Prepare one transparent PNG per part first, then standardize each part separately.

Example:

```powershell
cd D:\godotproject\aftertale

powershell -ExecutionPolicy Bypass -File tools\art\standardize_character_part.ps1 `
  -Source assets\art\characters\hair_front\rk_test_hair_long_b_south.png `
  -Output assets\art\characters\hair_front\rk_test_hair_long_b_south_std256.png `
  -Part hair_front
```

If a layer needs manual vertical adjustment, edit the part target region in:

```text
tools/art/standardize_character_part.ps1
```

Then regenerate the affected `*_std256.png`.

Use a readable standing proportion rather than an oversized chibi head:

```text
head : body/outfit = about 1 : 2
```
