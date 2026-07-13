# Phase 67.7 Region Demand Contract

Note: the corrected v67.8 contract supersedes the concrete-role examples and
schema numbers in this historical record. Current inputs use schema 3 and
express needs; the global library resolves those needs through location
archetypes and concrete forms. See `phase_67_8_semantic_role_library.md`.

v67.7 is a foundation correction for the v67 Region-to-Location-Graph compiler.
It does not add world simulation and does not expand the map domain beyond the
current town, forest, plain, river, frontier, road, resource, public, dangerous,
landmark, and production concepts.

The phase changes the semantic-role input contract:

```text
RegionInput
-> region facts, region traits, required needs, optional needs

RegionTypeProfile
-> default needs and role capabilities

SemanticRoleExpander
-> existing real semantic roles selected from those needs
```

The important boundary is:

```text
v67 does not generate world background.
v67 turns given region facts, region needs, and coarse context into a legal,
traceable, downstream-expandable set of real semantic roles.
```

## Historical v67.7 Input Contract

v67.7 originally introduced `RegionInput.schema_version = 2`. The active v67.8
contract is schema `3`; it keeps the demand fields below and changes forced-role
identity from a concrete `role_type` to `archetype_id` plus an optional
`form_id`.

The main input fields are:

```text
region_traits
region_facts
required_needs
optional_needs
coarse_context
forced_role_specs
```

`required_roles` and `optional_role_pool` are no longer supported in the main
schema. If either field appears in a schema v2 input, validation fails.

`RegionInput` still accepts `forced_role_specs`, but forced roles remain explicit
input facts. They must not provide compiler-owned `role_id`. Under v67.8 they
must reference a valid library archetype and, when specified, one of that
archetype's concrete forms.

## Limited Vocabulary

v67.7 introduces a bounded vocabulary in:

```text
scripts/systems/regions/region_semantic_vocabulary.gd
```

This vocabulary covers only current map-generation ground:

```text
settlement, wilderness, plain, forest, river, frontier, kingdom, road,
resource, public place, danger, landmark, production, shelter, ritual.
```

Inputs outside this vocabulary fail. The compiler does not invent new semantic
domains such as empire politics, trade networks, NPC factions, quests, or
dynamic ecology.

## Region Type Profiles

v67.7 originally used `RegionTypeProfile.schema_version = 2`. The active v67.8
profile schema is `4`.

Profiles now define default needs:

```text
required_needs
optional_needs
```

In the historical v67.7 contract, role definitions declared what they could
satisfy:

```text
satisfies
role_tags
properties
affinity
category
allowed_sources
allow_multiple
```

Profiles also define context influence through:

```text
context_semantic_modifiers
```

These modifiers may only target semantic fields:

```text
satisfies
properties
affinity
category
```

They must not target concrete `role_type` ids. The old
`context_weight_modifiers` field is rejected because it encoded
`coarse_context -> role_type` coupling.

That first correction still reused mixed-level downstream role names such as:

```text
settlement_core
main_exit
farmland
market
entrance
common_woods
stream
hidden_grove
```

These names are not the active v67.8 role model. v67.8 removes structural
placeholders such as `settlement_core`, separates stable location archetypes
from concrete forms, and keeps external connections as edges between real
locations rather than as placeholder roles or nodes.

## Semantic Role Selection

`SemanticRoleExpander` no longer reads `optional_role_pool`.

It builds an effective demand contract from:

```text
RegionInput.required_needs
RegionInput.optional_needs
RegionInput.region_traits
RegionInput.region_facts
RegionInput.coarse_context
RegionTypeProfile.required_needs
RegionTypeProfile.optional_needs
```

Then it selects existing roles whose profile declarations satisfy those needs.

Required needs must be covered by roles that allow the `required` source. Optional
roles are selected from legal optional candidates using the existing stable seed
and context-weighted selection. Context weighting is calculated by matching
semantic modifiers against the candidate role's declared needs, properties,
affinity, and category, not by looking up the candidate's concrete role id.
Randomness is only used among legal candidates; it is not used to hide missing
required coverage.

This is intentionally not a complete planning system. Dependency solving,
large-scale economy, cross-region trade, NPC faction needs, quest generation, and
dynamic ecology remain outside v67.7.

## SemanticRoleResult Additions

The result still emits normal semantic roles for v67.3:

```text
role_id
role_type
role_slug
role_source
role_tags
```

v67.7 adds traceable demand facts:

```text
demand_contract
need_coverage
selected_roles[].satisfies
selected_roles[].matched_need_ids
```

These fields are data, not a validation report. They record why a role was
selected and which needs the selected role can cover.

## Failure Rules

v67.7 fails when:

- `RegionInput` uses old role-pool fields;
- `RegionTypeProfile` uses old context-to-role `context_weight_modifiers`;
- needs, traits, facts, or coarse context values are outside the limited
  vocabulary;
- context semantic modifiers point at unsupported semantic keys or unused
  semantic tokens;
- a required need has no required role candidate in the region type profile;
- an optional need has no optional role candidate in the region type profile;
- a forced role is unsupported or does not allow the forced source;
- a profile declares needs that no role can satisfy;
- the selected roles cannot cover all required needs.

The compiler does not silently translate old roles into needs and does not add
missing roles to make invalid input pass.

## Verification

Coverage lives in:

```text
scripts/tests/v67_7_region_demand_contract_test.tscn
```

The v67.2 semantic-role smoke test was also updated so its regression coverage
uses the v67.7 demand contract instead of the removed role-pool contract.
