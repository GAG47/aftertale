# Phase 38 - Shop UI and Vendor Inventory

## Goal

Move the shop facility from the old mixed buy/sell list into a dedicated trading panel, and make the trading rules use the NPC as the actual vendor.

## Changes

- Rebuilt the shop section of `FacilityPanel` into separate buy and sell tabs.
- Added a two-column shop layout:
  - left side: scrollable item list for the current mode;
  - right side: selected item details, stock/ownership, price, quantity, total, and action button.
- Added `vendor_character_id` to shop facilities so a location object can bind to a real NPC.
- Updated `BusinessSystem` so vendor stock comes from the NPC inventory:
  - buying removes items from the NPC inventory and adds them to the player inventory;
  - selling removes items from the player inventory and adds them to the NPC inventory;
  - buying pays the NPC;
  - selling requires the NPC to have enough currency and then deducts that currency.
- Updated `TradeAction` to pass the selected vendor id through to `BusinessSystem`.
- Bound the test field stall to `debug_villager`.
- Gave `debug_villager` test stock and a small vendor wallet so stock and insufficient-money behavior can be checked in the test scene.
- Added daily shop restocking at 00:00:
  - each shop offer can define `restock_quantity`, `daily_stock`, or `stock`;
  - restocking fills the vendor inventory up to that target instead of stacking endlessly;
  - vendor currency is refilled to the shop's configured `vendor_currency` minimum;
  - the system records which day each shop has restocked so the same day cannot restock twice.

## Test Setup

The field stall now uses `debug_villager` as its vendor.

- `debug_seed` appears with real stock because the villager starts with it.
- `packed_snack` remains listed by the stall but shows stock `0` if the villager does not have it.
- Selling is blocked when the villager does not have enough currency for the selected quantity.
- After midnight, the stall refills to `3` `debug_seed` and `1` `packed_snack`.

## Verification

- Ran Godot headless startup check successfully.
