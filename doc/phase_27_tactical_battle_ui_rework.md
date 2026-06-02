# Phase 27 Tactical Battle UI Rework

This phase changes battle UI from a bottom information bar into a tactical, menu-driven layout inspired by Fire Emblem, Tactics Ogre, and FFT-style battle screens.

## Goal

The battle map should remain the primary read. UI panels should appear in corners or as small menus, and only show information needed for the current decision.

## Layout

- The battle HUD root is now a transparent full-screen control layer.
- The current unit card is anchored at the lower left.
- The command menu is anchored at the lower right.
- Skill and status menus replace the command menu when opened.
- The large bottom dock and all-unit text list are removed.

## Current Unit Card

The left card shows only the current acting unit:

- Battle round.
- Unit display name.
- Player/enemy action state.
- HP and AP bars.
- HP, AP, speed, and active status text.

Enemy HP and AP are no longer listed in the player card. Enemy state is read through map token HP bars and later target inspection panels.

## Command Menu

The right command menu exposes the tactical choices:

- Move.
- Skills.
- Wait.
- Status.
- Flee.

The buttons still call existing UI signals. Wait and flee continue to use `BattleSystem` through `UIRoot`.

## Skill Menu

The skill menu is a second-level panel:

- It lists skills vertically with name and AP cost.
- The selected skill is marked.
- Cooldowns are shown when present.
- Skill description, target type, range, area, and failure reason appear in a detail label.

Selecting a skill still calls `BattleSystem.select_skill_for_current_unit` through the existing `skill_selected` signal.

## Boundaries

- This phase does not change battle resolution, AP spending, damage, rewards, defeat, fleeing, or target validation.
- Map range previews remain owned by `BattleGridOverlay`.
- Token HP/AP rings and floating battle feedback from Phase 26 remain active.
- Target detail inspection is intentionally left as the next small battle UI step.
