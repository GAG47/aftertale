# Phase 67.5 Location Graph Snapshot

## 目标

v67.5 固化并复验已经生成完成的节点和边，不继续生成地图内容：

```text
LocationNodeResult[]
+ EdgeContractResult
+ graph_id
-> LocationGraphSnapshot
-> LocationGraphSnapshotValidator
-> explicit save/load
-> v67.6 Runtime boundary
```

v67.5 的责任是固化和复验上游结构；任何结构性缺陷都必须通过失败暴露，不能在 Snapshot 阶段修补。

## 上游完整性

`LocationNodeResult` 和 `EdgeContractResult` 均新增：

```text
result_hash
```

哈希计算排除自身的 `result_hash` 字段。节点展开器和边生成器声明结果哈希，各自的校验器重新计算并比对。

SnapshotBuilder 再次复核：

```text
LocationNodeResult.result_hash
EdgeContractResult.result_hash
EdgeContractResult.location_node_set_hash
```

缺少声明哈希、规范化失败或重新计算不一致都会终止构建。该完整性契约不改变节点和边的生成语义。

## 统一规范化编解码

所有结果哈希、Snapshot 内容哈希、保存文本和加载后复验共同使用：

```text
CanonicalDataSerializer
```

规范化区分三类数组：

- 集合数组：仅在契约明确声明时排序并去重。
- 实体数组：按契约指定的稳定 ID 排序。
- 列表数组：保持原始语义顺序。

当前实体数组规则：

```text
LocationNodeResult[] 按 region_id
location_nodes 按 location_id
role_node_bindings 按 source_role_id、location_id
edge_contracts 按 edge_id
node_sources 按 location_id
source_manifest 按 source_kind、source_id
rule_manifest 按 profile_kind、profile_path
```

当前集合数组规则：

```text
node_tags
traversal_tags
validation_flags
```

Dictionary 键按字典序序列化。普通数组默认保持顺序。只允许 JSON 可表达的数据类型，拒绝非字符串 Dictionary 键、非有限浮点数和引擎对象。

规范化文本使用 SHA-256：

```text
content_hash = SHA-256(
    canonical_snapshot
    - content_hash
    - snapshot_id
)

snapshot_id = stable_id(graph_id + content_hash)
```

`content_hash` 与 `snapshot_id` 不参与自身内容哈希。

## 构建输入

构建入口：

```text
build_snapshot_result(
    graph_id,
    location_node_results,
    edge_contract_result
)
```

`graph_id` 必须由调用方明确提供，不能从第一个 Region 推断。

主编译器提供：

```text
compile_location_graph_snapshot_result(
    inputs,
    edge_profile_path,
    graph_id
)
```

该函数只返回内存中的 Snapshot。它不创建目录、不打开输出文件、不写入 `user://`，也不自动保存。

## Snapshot 契约

`LocationGraphSnapshot` 包含：

```text
schema_version
compiler_version
stage
graph_id
snapshot_id
content_hash
location_nodes
edge_contracts
node_sources
source_manifest
rule_manifest
```

`location_nodes` 是上游节点的规范化并集，不增加、不删除节点。

`edge_contracts` 是上游边契约的规范化固化，不重新运行边规则。

`node_sources` 记录：

```text
location_id
source_region_id
location_node_result_hash
```

Region 只作为节点来源，不是图的所有者或边端点。

`source_manifest` 记录每份 `LocationNodeResult.result_hash` 和唯一一份 `EdgeContractResult.result_hash`。

## 规则清单

`rule_manifest` 记录所有参与生成的：

```text
semantic_role_profile
location_node_profile
edge_contract_profile
```

每行包含：

```text
profile_kind
profile_path
profile_content_hash
```

SnapshotBuilder 在构建时读取 profile，要求文件存在、内容是 JSON Object、能够规范化并能够计算 SHA-256。任一 profile 失败都会终止 Snapshot 构建，不能只保留路径。

加载 Snapshot 时不读取当前磁盘 profile。规则清单已经被固化并受 `content_hash` 保护，Snapshot 加载不重新解释生成规则。

## Snapshot 校验

`LocationGraphSnapshotValidator` 验证：

- Schema 与编译器契约精确兼容。
- 没有未知字段、缺失字段或旧字段名。
- 所有实体数组和集合数组处于规范顺序。
- `content_hash` 与规范化内容一致。
- `snapshot_id` 与 `graph_id + content_hash` 一致。
- 节点 ID 与边 ID 唯一。
- 所有边端点存在。
- 不存在自环和重复端点对。
- 每个节点都有且只有一个来源。
- 节点来源哈希与 `source_manifest` 一致。
- `endpoint_region_relation` 与两个节点来源一致。
- 规则清单包含三种必需 profile，且内容哈希合法。
- 节点和边不包含 Runtime、Scene、Spawn 或 TileMap 字段。

v67.5 不负责补边、删节点或重新规划连通性。节点接入要求由 `EdgeContractResult` 的图约束决定。SnapshotBuilder 在固化前使用原始节点、边和 EdgeContractProfile 重新调用 v67.4 校验契约。

如果某项图约束需要脱离 profile 后继续复验，它必须先成为 `EdgeContractResult` 或 Snapshot 的规范化数据。仅保存 profile 哈希不能冒充已经复验其内容。

## 显式保存与加载

存储器入口：

```text
save_snapshot_to_path(snapshot, explicit_path)
load_snapshot_from_path(explicit_path)
```

不存在默认路径。空路径明确失败。

保存流程：

```text
复验 Snapshot
-> 使用 CanonicalDataSerializer 生成保存文本
-> 写入同目录临时文件
-> 替换目标文件
```

加载流程：

```text
读取显式路径
-> 解析 JSON
-> 校验 Schema、结构、规范顺序和 content_hash
-> 返回原始 LocationGraphSnapshot
```

Store 必须把解析后的原始 Dictionary 直接交给 Validator，不能在校验前调用 `normalize_snapshot()`。非规范数组顺序和重复集合项必须作为加载错误保留下来。

加载不读取 profile、不重新编译、不迁移旧格式、不修补结构、不注册 Runtime。

## 明确排除

v67.5 不包含：

```text
start_location_id
current_location_id
scene_path
spawn_id
exit_id
direction_hint
exit_style
tilemap
玩家移动
运行时邻接索引
场景加载
游戏存档 diff
旧 Snapshot 自动迁移
```

`start_location_id` 属于新游戏或运行时会话策略，不是图结构事实。

## 编译边界

`compile_to_location_graph_result()` 现在正式成功返回：

```text
LocationGraphSnapshot
```

主程序把原始 Snapshot 交给现有数据面板，然后明确停在：

```text
v67.6 Runtime adapter is not implemented
```

主启动不会保存 Snapshot 文件。

## 验证

无场景验证脚本：

```text
scripts/tests/v67_5_location_graph_snapshot_test.gd
```

它覆盖：

- 相同输入生成相同 `content_hash`。
- `LocationNodeResult[]` 输入顺序变化不改变结果。
- 上游节点或边被改动后 `result_hash` 复核失败。
- `content_hash` 排除 `content_hash` 与 `snapshot_id`。
- 篡改节点字段后加载失败。
- 篡改边端点后加载失败。
- 篡改 `content_hash` 后加载失败。
- 未知字段和不兼容 Schema 加载失败。
- 原始 JSON 中节点数组乱序时加载失败。
- 原始 JSON 中集合标签重复或乱序时加载失败。
- profile 内容变化导致 `rule_manifest` 和 Snapshot 哈希变化。
- 显式保存后加载得到完全相同的 Snapshot。
- 缺少显式保存路径时失败。

该脚本由 Godot 直接执行，不保留承载测试脚本的场景。
