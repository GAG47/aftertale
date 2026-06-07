# Phase 55: Battle UI Information Architecture

## Status

Complete.

## Goal

Make the battlefield the visual focus by reducing persistent overlays and
keeping battle facts on the map whenever the map can communicate them.

## Layout

The former four-panel battle HUD was replaced with:

- a background-free portrait-only turn order rail on the left that shows only
  the current round;
- a compact badge-portrait character card in the lower-left corner;
- a four-slot skill, MP, AP, and end-turn dock in the lower-right corner;
- an AI scoring drawer that is closed by default.

Turn portraits use faction borders, a gold current-turn highlight, and detailed
tooltips. AP and speed are no longer repeated in every turn-order row.

The character card uses the same head crop as the turn-order badge. It shows
the name, a white level badge, HP bar, attack, defense, and speed in a shallow
lower-left strip. Active unit statuses appear as compact colored icons to the
right of the name; no placeholder is shown when there are no statuses. All
character text uses high-contrast white.

The skill dock always places Basic Attack in slot 1 and allows at most three
additional equipped skills. Explicit bottom-right anchors keep the four skill
buttons, MP/AP resources, round counter, AI toggle, and end-turn command inside
the viewport at supported widths.

## Battlefield Presentation

Battle tile states now use a weak surface tint plus a compact Chinese state
badge and remaining-round number. Movement, skill, and hovered area ranges keep
the stronger full-cell colors.

The old map-adjacent target popup, center context preview, and full-width bottom
frame were removed. Tile state, range, and affected area remain map-rendered
facts, so the center-bottom battlefield stays empty.

## AI Debugging

The AI drawer reads `BattleState.recent_ai_decisions` and displays:

- selected action and total score;
- candidate count;
- weighted score breakdown;
- the top five candidate actions.

It can be toggled with the `AI` debug button or `F4`. No AI score is recomputed
inside the UI.

## Verification

- Godot 4.6.3 parses the updated HUD, battle preview, and overlay scripts.
- The normal project main scene passes a headless startup check.
- A v55 UI smoke scene covers the portrait rail, viewport-bound bottom docks,
  status icons, absence of a center preview, and AI drawer structure. In the restricted automation
  environment, running a standalone Control test scene triggers a Godot 4.6.3
  native shutdown crash before a reliable screenshot can be captured; the
  normal project startup and editor filesystem scan complete without script
  parse errors.
