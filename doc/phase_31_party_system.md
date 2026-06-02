# Phase 31 Party System

This phase adds the rule-layer party foundation without adding map following, battle deployment, or formation management yet.

Implemented scope:

- `PartySystem` autoload stores the leader, member ids, and member summary snapshots.
- New sessions reset the party to the player leader.
- Save/load persists party state.
- `RecruitCompanionAction` lets dialogue and other rule callers recruit an NPC through `ActionSystem`.
- Dialogue conditions now support `party_member` and `not_party_member`.
- Debug villager and debug guard have test dialogue options that recruit them into the party.
- `CharacterPanel` reads `PartySystem.get_party_summary()`, shows real party slots, and lets the player click a party member to view their character details.

The party system deliberately does not mutate map following, battle teams, or formation positions in this phase. Those systems can later consume `PartySystem.member_ids` and `PartySystem.get_party_summary()` as their stable source.
