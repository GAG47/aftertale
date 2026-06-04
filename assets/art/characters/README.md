# Character Art Asset Standard

NPC modular parts use a fixed 64x64 transparent canvas.

Required standard:

```text
game canvas: 64x64 px
grid anchor: (32, 46)
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

Every exported PNG should keep the full 64x64 canvas. Do not crop parts to visible pixels.

The source drawing or AI generation canvas can be 512x512 or 1024x1024, but the file that enters the game should be exported to 64x64 and aligned to the shared anchor.

Use a readable standing proportion rather than an oversized chibi head:

```text
head : body/outfit = about 1 : 2
```
