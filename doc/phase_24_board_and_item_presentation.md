# Phase 24 Board And Item Presentation

This phase improves the board-facing presentation before AI-generated NPC portraits and chibi art are available.

## Scope

- Keep the current rule grid and scene data model.
- Replace flat color tiles with soft board-style terrain rendering.
- Replace generic object dots with readable front-facing icons.
- Do not introduce portrait or chibi-token dependencies yet.

## Tile Rendering

`DebugTileRenderer` now draws terrain through reusable terrain-style branches:

- Grass has soft inset variation and small grass strokes.
- Path tiles have warmer inset tones and small pebble marks.
- Water tiles have light wave strokes.
- Field plots have horizontal soil furrows.
- Stone tiles have muted block detail.
- Exit tiles keep terrain readability and draw a clear arrow marker.

Grid lines remain visible for movement and tactical combat, but they are softer and less visually dominant.

## Object Rendering

`LocationObject` now draws simple icon-like objects:

- Apple drops use a red apple icon.
- Seed drops use a small pouch icon.
- Stick drops use crossed branch strokes.
- Signs and markers use a front-facing sign board.
- Crates use a small wooden box icon.
- Switches use a stone/metal switch icon.

The yellow pickup marker and blue usable marker remain as interaction badges. These are presentation-only indicators and do not change rules.

## Boundaries

This is still a visual layer over existing world facts:

- Terrain data still comes from location JSON.
- Objects still come from location object records.
- Picking up, inspecting, and using objects still goes through actions.
- The renderer does not mutate scene, inventory, crop, quest, or battle state.

Future art can replace these procedural icons and tile details without changing the gameplay contracts.
