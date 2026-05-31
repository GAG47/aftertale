# Phase 10: Lightweight Definition Loader

This phase adds a thin definition-loading layer without changing the current content format.

JSON remains the current content source. Gameplay systems should not own JSON parsing or file-open logic.

## Goal

- Keep current JSON files.
- Centralize loading, caching, and error messages.
- Avoid forcing gameplay systems to depend on file parsing details.
- Leave room for future Godot Resource, editor tool, or table-import migration.

## Runtime Entry

`DefinitionLoader` is an autoload:

```text
res://scripts/core/definition_loader.gd
```

It exposes small semantic helpers:

- `load_location(path)`
- `load_character(path)`
- `load_item(path)`
- `load_dialogue(path)`
- `load_quest(path)`
- `load_faction(path)`
- `load_relation_data(path)`
- `load_json_resource(path, expected_kind)`

All helpers currently return a duplicated `Dictionary`.

## Current Scope

The loader only does:

- open JSON files
- parse JSON objects
- cache loaded definitions
- return deep duplicates
- provide consistent error messages

It does not do:

- schema validation
- editor UI
- Resource migration
- database behavior
- gameplay rules

## Refactored Systems

The following systems now load content through `DefinitionLoader`:

- `LocationRoot`
- `LocationObject`
- `CharacterEntity`
- `DialogueRunner`
- `QuestSystem`
- `NpcScheduleSystem`
- `RelationSystem`

Validation remains in `tools/validation/validate_locations.ps1`, because it checks project data offline rather than serving runtime gameplay.

## Design Boundary

Gameplay systems ask for definitions:

```gdscript
var definition: Dictionary = DefinitionLoader.load_character(path)
```

They should not parse JSON directly.

If content later moves from JSON to `.tres` resources, the first migration point is `DefinitionLoader`, not every gameplay system.
