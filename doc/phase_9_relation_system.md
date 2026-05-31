# Phase 9: Relation System

This phase adds long-term relationship state for characters and factions.

## Runtime Systems

- `RelationSystem` owns character relations, faction relations, and relation events.
- Other systems do not directly edit relation state.
- Actions, quests, and dialogues publish `relation_delta` world changes.
- `RelationSystem` consumes those changes and publishes a `RelationEvent` result through `ActionSystem`.

## Relation State

Character and faction relations use the same core fields:

```json
{
  "source_id": "debug_villager",
  "target_id": "debug_player",
  "affinity": 5,
  "trust": 0,
  "hostility": 0
}
```

Relations are directional. A villager trusting the player does not automatically mean the player trusts the villager.

Scores are clamped:

- `affinity`: `-100` to `100`
- `trust`: `-100` to `100`
- `hostility`: `0` to `100`

`stance` is derived:

- `friendly`: high affinity and trust, low hostility
- `neutral`: default
- `wary`: meaningful hostility or low affinity
- `hostile`: high hostility

## Data

- Factions live in `data/factions/`.
- Initial relation state lives in `data/relations/initial_relations.json`.
- Character definitions still own `faction_id`.

## Current Test Loop

The apple quest now has a relation requirement and grants a relation reward:

```json
{
  "type": "relation_at_least",
  "source": "debug_villager",
  "target": "actor",
  "metric": "affinity",
  "value": 0
}
```

```json
{
  "type": "relation",
  "scope": "character",
  "source_id": "debug_villager",
  "target_actor": true,
  "delta": {
    "affinity": 25,
    "trust": 15,
    "hostility": 0
  }
}
```

After the player completes the quest, the Debug Villager becomes friendly toward the player. A new dialogue option appears only when affinity and trust are high enough.

## Dialogue Conditions

Dialogue can check relations:

- `relation_at_least`
- `relation_below`
- `relation_stance`
- `faction_relation_at_least`
- `faction_relation_below`
- `faction_stance`

Dialogue results can also emit `relation_delta` changes.

## Quest Requirements

Quest definitions can gate acceptance with the same relation condition family used by dialogue:

- `relation_at_least`
- `relation_below`
- `relation_stance`
- `faction_relation_at_least`
- `faction_relation_below`
- `faction_stance`

## Trade And Combat Influence

The relation system exposes rule helpers for later trade and combat screens:

- `allows_trade(source_id, target_id)`
- `get_trade_price_modifier(source_id, target_id)`
- `allows_hostile_action(source_id, target_id)`

These are relation-layer rules only. Trade and combat presentation systems can call them without owning relation state.

## Debug

The debug panel shows visible NPC relations toward the controlled player:

```text
Relations: debug_villager friendly A30 T15 H0
```

## Validation

`tools/validation/validate_locations.ps1` now validates:

- faction JSON ids
- character `faction_id` references
- initial character relation references
- initial faction relation references
- quest relation rewards
- dialogue relation conditions
- dialogue relation result references
