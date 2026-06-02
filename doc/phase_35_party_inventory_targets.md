# Phase 35 - Party Inventory Targets

## Goal

This phase adds explicit party-member targets to inventory actions so item use and equipment actions no longer always affect the player character.

## Implementation Scope

- Added a current-party target selector to the inventory detail area.
- Food and consumables are consumed from the currently opened actor's inventory and applied to the selected party member.
- Food and consumables restore HP by default. Item definitions can override the amount with `heal_amount` or a `heal` entry in `effects`.
- Equipment is selected from the currently opened actor's inventory and assigned onto the selected party member.
- Assigned equipment remains visible in the player inventory and shows who is currently using it.
- NPC default equipment is character configuration, not a movable inventory item.
- Player equipment temporarily overrides a party member's default equipment.
- Reassigning player equipment automatically clears its previous party-member override and applies it to the new target.
- Retrieving player-provided equipment clears the override; the item was already retained in the player inventory.
- Removing a player-provided override restores the target character's default equipment display and bonuses.
- Equipment retrieval is handled from the character screen's equipment section, not from the inventory screen.
- When an NPC leaves the party, all player-provided equipment overrides are cleared and the NPC restores default equipment.

## Rules

- The currently opened inventory owner is the item source.
- The selected target character is the effect or equipment target.
- The target character must be a current party member and must exist in the current map.
- Non-food and non-consumable items are not directly used from the inventory. Keys and similar items should still be handled by map interaction.
- The inventory screen should not display character equipment slots or unequip controls.
- The character screen is responsible for inspecting current effective equipment and retrieving player-provided overrides.
- NPC default equipment cannot be taken, transferred, or placed into the player inventory.
- Player-provided equipment remains in the player inventory while assigned, so reassignment does not require a separate unequip step.

## Related Files

- `scripts/ui/inventory_panel.gd`
- `scripts/ui/character_panel.gd`
- `scripts/systems/items/equipment_slots.gd`
- `scripts/systems/party/party_system.gd`
- `scripts/systems/actions/use_item_action.gd`
- `scripts/systems/actions/equip_item_action.gd`
- `scripts/systems/actions/unequip_item_action.gd`
