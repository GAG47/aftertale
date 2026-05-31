# Phase 18 Business System

This phase adds a lightweight business layer that connects inventory, crafting, crops, saving, and the action system.

## Scope

- Adds a market definition format under `data/shops`.
- Adds `BusinessSystem` as the owner of shop definitions and player currency.
- Implements `TradeAction` through the action system.
- Adds a Business tab to the player menu.
- Persists business currency in save files.
- Lets locations declare available shops through their location data.

## Current Loop

1. The player gathers, crafts, or harvests items.
2. The player opens the menu and enters the Business tab in a location with a shop.
3. The menu asks `BusinessSystem` for available buy and sell offers.
4. Pressing Buy or Sell submits a `TradeAction`.
5. `BusinessSystem` checks requirements, changes inventory and currency, and returns an `ActionResult`.
6. Save/load stores and restores currency through `SaveManager`.

## Rule Boundary

The UI never edits money or inventory directly. It only submits `TradeAction`.

The current market uses unlimited stock and fixed prices because the goal is to establish a closed gameplay loop, not a full economy simulation. Future shopkeepers, stock limits, relation discounts, town demand, and business ownership can extend the same shop definition and `TradeAction` path.

## Test Data

- `data/shops/field_stall.json`
- `data/locations/test_field.json` declares the active test market.
- Sellable: apples, sticks, seeds, herbs, crafted tools, packed snacks.
- Buyable: seeds and packed snacks.
