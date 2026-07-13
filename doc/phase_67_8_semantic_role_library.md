# Phase 67.8 Semantic Role Archetypes and Forms

v67.8 defines semantic locations at one consistent level. It separates the
stable purpose of a place from the concrete form that purpose takes in a region:

```text
RegionNeed
-> LocationCapability
-> LocationArchetype
-> LocationForm
-> SemanticRoleResult
-> LocationNodeResult
```

It remains a bounded map-generation stage. It does not implement the v67.9
combination planner, world politics, economy networks, factions, quests, NPCs,
ecology, scenes, or tile maps.

## Layer Ownership

`RegionInput` and `RegionTypeProfile` declare what the region needs. A need is
a controlled capability such as `public.gathering`, `production.food`,
`travel.access`, or `resource.water`; it is not a location.

`SemanticRoleLibrary` is the sole owner of two definition sets:

```text
archetype_definitions
-> stable location purpose and planning capabilities

form_definitions
-> concrete semantic place, regional conditions, and environmental affinity
```

An archetype may have several forms. For example:

```text
trade_place
-> market_square
-> caravan_stop

religious_place
-> roadside_shrine
-> sacred_grove

access_point
-> road_gate
-> forest_trailhead
```

A form cannot declare `satisfies`. Planning capabilities belong to the
archetype, so adding a new environmental presentation cannot silently change
the need model.

## Removed Mixed-Level Roles

The corrected library does not retain structural placeholders or category-only
roles such as:

```text
settlement_core
support_area
landmark
common_woods
inner_area
```

It also removes environment-prefixed duplicates such as `shrine` versus
`forest_shrine`, and `main_exit` versus `entrance`. Their stable purpose is an
archetype; their actual regional meaning is a form.

The former circular fact `has_farmland` is removed. The `farmland` form requires
the pre-existing regional fact `arable_land`. Water-source forms do not satisfy
`travel.crossing`; the `ford` form does.

## SemanticRoleLibrary v2

The library is stored at:

```text
res://data/regions/semantic_role_libraries/core.json
```

Each archetype defines:

```text
archetype_definition_id
satisfies
properties
gameplay_affordances
narrative_affordances
category
allowed_sources
allow_multiple
```

Each concrete form defines:

```text
form_definition_id
archetype_id
properties
affinity
gameplay_affordances
narrative_affordances
requires_traits / excludes_traits
requires_facts / excludes_facts
requires_context / excludes_context
```

Hard requirements decide legality. Affinity is a soft preference only.
Archetype and form definitions receive separate canonical SHA-256 hashes, and
the complete library receives a content hash.

Gameplay affordances describe supported player actions. Narrative affordances
describe what a future narrative system may place there. They are passive,
controlled metadata in v67.8: they do not influence selection and do not create
quests or events.

## Controlled Vocabulary

The vocabulary keeps these dimensions separate:

```text
region needs / archetype capabilities
role properties
environment affinities
role categories
gameplay affordances
narrative affordances
region traits
region facts
coarse-context keys and values
```

Unknown values fail. A valid token in one dimension is invalid in another.
`role_tags` remains a non-planning annotation channel for explicit forced
instances.

## Region Contracts

`RegionInput.schema_version` is `3`. A forced role specification uses:

```text
archetype_id
form_id          # optional
role_slug
role_tags        # optional
```

If `form_id` is omitted, the expander chooses a legal form of the requested
archetype. If it is supplied, it must belong to the archetype and satisfy the
region's hard conditions. The old `role_type` forced-input field fails.

`RegionTypeProfile.schema_version` is `4`. It declares typed semantic scope and
may explicitly exclude a small number of forms through `excluded_form_ids`. It
does not contain `allowed_form_ids`, concrete weights, or a concrete candidate
pool.

## Lightweight Selection Boundary

The current expander performs:

```text
effective region needs
-> legal archetypes and forms
-> hard-condition filtering
-> semantic context weighting
-> one concrete form per selected archetype
```

Forced roles are resolved first so a forced concrete form can satisfy a required
need instead of being duplicated by a default form. Required needs then use the
existing deterministic best-candidate rule. Optional roles retain seed-stable
weighted selection.

This is deliberately not the v67.9 combination planner. v67.8 establishes valid
candidate meaning and provenance; it does not claim globally optimal role sets.

## Result and Downstream Closure

`SemanticRoleResult.schema_version` is `3`. Every selected role records:

```text
role_id
role_type               # compatibility identity, equal to form_id
archetype_id
form_id
archetype_definition_id / archetype_definition_hash
form_definition_id / form_definition_hash
satisfies / matched_need_ids
properties / affinity / category
gameplay_affordances / narrative_affordances
role-library identity, path, and content hash
```

`LocationNodeProfile.schema_version` is `2` and maps
`form_to_location_rules`. A form, not an abstract archetype, expands to the real
location node.

`LocationNodeResult.schema_version` is `3`. Nodes preserve:

```text
source_role_id
source_archetype_id
source_form_id
gameplay_affordances
narrative_affordances
```

Required-need coverage is also represented as stable node tags for edge rules.
The edge profile now connects actual places such as a gathering place, road
gate, farmland, forest trailhead, foraging ground, and hunting ground. It no
longer relies on `town_center`, `settlement_support`, `common_woods`, or
`deep_forest` placeholder nodes.

`LocationGraphSnapshot.schema_version` is `3`. It carries both semantic
identities and both affordance sets, while its rule manifest continues to record
the role-library path and content hash. Runtime reads those fields but never
writes state back to the Snapshot.

## Verification

The carrier-free test is:

```text
scripts/tests/v67_8_semantic_role_library_test.gd
```

It rejects flat roles, structural placeholders, circular region facts,
form-owned planning capabilities, concrete candidate pools, forged archetype or
form hashes, missing form-to-node mappings, and loss of either semantic identity
between roles, nodes, Snapshots, and Runtime.
