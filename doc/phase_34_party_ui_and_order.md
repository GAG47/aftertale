# Phase 34 - Party UI and Order Management

## Goal

This phase completes party management in the `C` character screen.

Party order does not define fixed battle spawn cells. Battles can begin on many kinds of terrain, and fixed formation cells can collide with walls, narrow paths, event cells, or occupied units.

The party screen only represents the current traveling party. It does not maintain a remote reserve roster. Characters outside the current party are not shown in the character screen, and they cannot be remotely equipped or used as inventory targets.

## Implementation Scope

- Reworked the left character panel into a scrollable current-party member list.
- Each member entry shows name, HP, follow order, and battle priority.
- Selecting a member refreshes the profile, attributes, equipment, and skill details.
- Party members can be moved up, moved down, or removed from the party.
- The leader is fixed in the first slot and cannot be moved or removed.
- The current party size limit is 5 members. Recruiting fails with feedback when the party is full.
- Party order directly drives follow order: earlier members follow closer to the leader.
- Party order participates in battle turn tie-breaking: if speed is equal, earlier party members act first.
- Removed members are released from follower state in the current map and return to normal NPC behavior.
- Removing a member saves that character's runtime state. Their inventory and equipment stay with that character and are not transferred to the player.

## Non-Goals

- No default battle spawn formation or fixed formation cells are provided.
- No reserve companion roster is provided.
- No remote management for characters outside the current party.
- Party UI ordering does not forcibly reposition map characters, avoiding sudden map movement caused by menu operations.
- Battle entry still uses party members that actually exist in the current map.

## Related Files

- `scripts/systems/party/party_system.gd`
- `scripts/ui/character_panel.gd`
- `scripts/systems/battle/battle_state.gd`
- `scripts/systems/scenes/location_root.gd`
