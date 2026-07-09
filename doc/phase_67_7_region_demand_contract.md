# Phase 67.7 Region Demand Contract

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

## RegionInput v2

`RegionInput.schema_version` is now `2`.

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
input facts. They must not provide compiler-owned `role_id`, and they must still
be supported by the region type profile.

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

`RegionTypeProfile.schema_version` is now `2`.

Profiles now define default needs:

```text
required_needs
optional_needs
```

Role definitions now declare what they can satisfy:

```text
satisfies
role_tags
properties
affinity
category
allowed_sources
allow_multiple
```

The role type names are still the existing downstream role types, such as:

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

v67.7 does not introduce abstract external connection roles or placeholder
boundary roles.

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
and context-weighted selection. Randomness is only used among legal candidates;
it is not used to hide missing required coverage.

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
- needs, traits, facts, or coarse context values are outside the limited
  vocabulary;
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
