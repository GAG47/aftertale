# Phase 67 Region Location Graph Completion

This file is retained only as a superseded record.

The Region Location Graph completion path was withdrawn after its node, edge,
snapshot, runtime, and scene responsibilities were separated into independent
compiler products.

The active boundary is now:

```text
RegionInput[]
-> SemanticRoleResult[]
-> LocationNodeResult[]
-> EdgeContractResult
-> LocationGraphSnapshot
-> LocationGraphRuntimeAdapter
-> placeholder Location scene
```

The current implementation supports Runtime-only current-location state and
adjacent Edge Contract traversal. It does not create scene exits, TileMaps,
NPCs, save diffs, or generated playable Location Scenes.

The current v67.3 record is:

```text
doc/phase_67_3_location_nodes.md
doc/phase_67_4_edge_contracts.md
doc/phase_67_5_location_graph_snapshot.md
doc/phase_67_6_snapshot_runtime_adapter.md
```
