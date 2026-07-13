# Phase 67.8 Semantic Role Library

v67.8 corrects ownership of semantic-role definitions. It does not make role
selection into a general planning system.

```text
RegionInput
-> region facts, traits, needs, and coarse context

RegionTypeProfile
-> region defaults, typed candidate scope, counts, and semantic preferences

SemanticRoleLibrary
-> global role identity, capabilities, properties, affinity, category,
   hard region conditions, multiplicity, and provenance

SemanticRoleExpander
-> the existing deterministic lightweight selection
```

The defining rule is:

```text
RegionTypeProfile does not own role definitions and does not name a normal
candidate pool. SemanticRoleLibrary is the sole owner of role definitions.
```

## Controlled Vocabulary

The map vocabulary is split into independent dimensions:

```text
needs and satisfies domains
role properties
role affinities
role categories
region traits
region facts
coarse-context keys and values
```

Every semantic field is checked against its own vocabulary. A valid token from
one dimension is invalid when placed in another dimension. Unknown tokens fail;
they are not accepted as free-form tags.

`role_tags` remains only as a non-planning annotation channel for explicit
`forced_role_specs`. The role library does not define role tags, and these tags
do not affect candidate filtering or weighting.

## SemanticRoleLibrary v1

The global library lives at:

```text
res://data/regions/semantic_role_libraries/core.json
```

Each role definition contains:

```text
role_definition_id
satisfies
properties
affinity
category
requires_traits / excludes_traits
requires_facts / excludes_facts
requires_context / excludes_context
allowed_sources
allow_multiple
```

Hard conditions have explicit meaning:

```text
requires_traits or requires_facts
-> every declared value must be present

excludes_traits or excludes_facts
-> any declared value makes the role illegal

requires_context
-> every declared context key must exist and match one allowed value;
   missing context fails the condition

excludes_context
-> any matching declared context value makes the role illegal

affinity
-> metadata for soft preference only; it is not a hard condition
```

The library validates unknown fields, duplicate values, contradictory required
and excluded conditions, unsupported context keys or values, and mixed semantic
dimensions. The library content and every individual role definition receive a
canonical SHA-256 hash.

## RegionTypeProfile v3

`RegionTypeProfile` no longer contains:

```text
role_definitions
role_weights
allowed_role_types
role_weight_overrides
```

Those fields fail validation instead of being translated.

The profile keeps:

```text
required_needs
optional_needs
scale_optional_counts
allowed_categories
allowed_satisfies_domains
required_properties
allowed_properties
excluded_role_types
context_semantic_modifiers
```

Candidate scope is semantic:

- the role category must be allowed;
- every capability domain declared by the role must be allowed;
- every role property must be inside the profile property range;
- every required profile property must be present on the role;
- a role in `excluded_role_types` is rejected.

`excluded_role_types` is an exception mechanism for a small number of explicit
prohibitions. It is not a source of candidates. The current profiles do not need
concrete exclusions.

Context modifiers may target only `satisfies`, `properties`, `affinity`, or
`category`. Every multiplier must be positive, so a soft preference cannot
silently become a hard eligibility rule. There is no concrete-role base weight
or concrete-role override.

## Selection Boundary

`SemanticRoleExpander` loads the region profile and the global role library,
then filters library roles by:

```text
selection source
-> typed RegionTypeProfile scope
-> role hard conditions against RegionInput
-> requested need coverage
```

Required needs still use deterministic best-candidate selection. Optional roles
still use the existing seed-stable weighted selection among legal candidates.
The weights come only from semantic context modifiers.

v67.8 does not implement combination search, dependency solving, exclusion-set
planning, economy chains, trade networks, factions, quests, or ecology. Those
are outside this ownership correction; combination planning belongs to v67.9.

## Provenance

`SemanticRoleResult.schema_version` is `2`. The result records:

```text
role_library_id
role_library_path
role_library_content_hash
```

Every selected role also records:

```text
role_definition_id
role_definition_hash
role_library_id
role_library_path
role_library_content_hash
```

`SemanticRoleResultValidator` reloads the declared library during compilation
and compares its identity, full content hash, each selected definition id and
hash, and the selected role's typed semantic fields. A syntactically valid but
forged hash is rejected.

`LocationNodeResult.schema_version` is `2` and carries the role-library source
forward without changing node semantics.

`LocationGraphSnapshot.schema_version` is `2`. Its `rule_manifest` contains
exactly one `semantic_role_library` row in addition to the participating region,
location-node, and edge profiles. Snapshot building reloads the library, checks
that its identity and actual content hash match the upstream declaration, and
fails on disagreement. Snapshot loading remains self-contained and does not
reload the current library.

## Downstream Boundary

v67.8 does not add node-profile keys, edge-rule ids, scene paths, spawn ids, or
runtime fields to the role library. Existing concrete roles continue through:

```text
SemanticRoleResult
-> LocationNodeResult
-> EdgeContractResult
-> LocationGraphSnapshot
-> Snapshot Runtime Adapter
```

Every role in the current global library has an existing LocationNodeProfile
mapping, and every resulting location type appears in the current edge-contract
selector vocabulary. Runtime remains generic and does not branch on role names.

## Verification

The carrier-free test script is:

```text
scripts/tests/v67_8_semantic_role_library_test.gd
```

It verifies ownership, rejection of old concrete-role fields, strict typed
vocabulary, hard context and profile-scope filtering, deterministic source
provenance, role-library content hashes, Snapshot rule-manifest inclusion, and
current downstream coverage.
