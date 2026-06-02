# Phase 33 Party Follow And Formation

This phase connects recruited companions to the map so the party can visibly travel together before entering battle.

Implemented scope:

- `PartySystem` now stores member source paths and default formation slots.
- Recruited companions keep enough source data to be spawned on later maps.
- `LocationRoot` syncs party companions after normal map characters spawn.
- Existing party members on the map are converted into non-interactable combat companions.
- Missing party companions are spawned near the player using their formation offset.
- Companions follow the player after successful exploration movement.
- Followers rotate their default formation around the player's facing direction.
- Party members are skipped by NPC schedule updates while they are in the party.
- Facing a party member no longer starts attack or dialogue interactions.
- Battle still uses the existing rule: only party members with live entities on the current map join battle.

Deferred scope:

- Manual formation editing UI.
- Pathfinding for long-distance catch-up.
- Per-member follow behavior settings.
