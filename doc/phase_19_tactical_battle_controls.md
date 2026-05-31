# Phase 19 Tactical Battle Controls

This phase improves tactical combat from keyboard-only rule testing into a clearer playable loop.

## Scope

- Adds movement range calculation from the current unit's remaining action points.
- Adds adjacent attack targeting.
- Adds click-to-move and click-to-attack behavior in combat mode.
- Adds a grid overlay for movement and attack highlights.
- Adds a battle HUD with round, active unit, unit status, Wait, and Flee.

## Controls

- Click a blue highlighted cell to move there.
- Click a red highlighted enemy cell to attack it.
- `E` or `Enter` still attacks the facing target.
- `WASD` or arrow keys still move one cell at a time.
- `R` or the HUD Wait button ends the current unit turn.
- `Esc` or the HUD Flee button attempts to flee.

## Rule Boundary

Combat UI and scene clicks do not directly mutate battle state. They call `BattleSystem`, which applies rules and publishes `ActionResult` entries.

Movement uses current action points as range. A multi-cell click consumes one action point per traversed cell. Basic attacks still use one action point and adjacent range.

## New Files

- `scripts/systems/scenes/battle_grid_overlay.gd`
- `scripts/ui/battle_hud_panel.gd`
