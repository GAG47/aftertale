# Phase 32 Party Battle

This phase connects the party foundation to battle startup while keeping map following, deployment UI, and party formation out of scope.

Implemented scope:

- Battle startup now builds the player side from `PartySystem.get_battle_members()`.
- Only party members with live `CharacterEntity` nodes on the current map enter battle.
- Party members absent from the current map remain in the party but do not join the battle.
- Enemy startup supports multiple combatable enemy units near the targeted opponent.
- Enemy AI now chooses the nearest active player-side unit instead of always attacking the first player unit.
- Party-side defeat events no longer set `player_defeated` unless the defeated unit is the actual player character.
- `test_clearing` now spawns two training dummies: one melee dummy and one ranged dummy.

Deferred scope:

- Map following.
- Battle deployment and formation selection.
- Party configuration UI.
