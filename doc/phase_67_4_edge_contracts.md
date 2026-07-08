# Phase 67.4 Edge Contracts

## 目标

v67.4 将一个或多个有效 `LocationNodeResult` 编译为 `EdgeContractResult`：

```text
LocationNodeResult[]
-> EdgeContractProfile
-> EdgeContractResult
-> EdgeContractResultValidator
-> v67.5 Location Graph Snapshot boundary
```

本阶段只生成 Location Node 之间的边契约，不生成图快照、起始地点、运行时状态、场景出口或 TileMap。

## 输入边界

`EdgeContractGenerator` 接收节点结果数组，而不是单个 Region：

```text
generate_edges_result(location_node_results, profile_path)
```

每个节点结果仍保留自身的 `region_id` 作为来源信息，但生成器不会先按 Region 划分内部连接和外部连接。所有节点共同组成候选集合，边规则只读取节点已有事实。

单个 RegionInput 仍然只通过原有入口生成自己的 `LocationNodeResult`。`RegionLocationGraphCompiler.compile_edge_contracts_result()` 负责将多个 RegionInput 分别编译成节点结果，再把节点结果数组交给边生成器。

## EdgeContractProfile

默认规则文件位于：

```text
data/location_graph/edge_contract_profiles/default.json
```

规则使用以下节点事实选择端点：

- `location_types`
- `source_role_types`
- `required_tags`
- `excluded_tags`

规则不允许使用 `region_id`、`region_type`、外部连接意图、场景出口或运行时字段选择端点。

支持的激活方式：

- `required`：某一侧节点已经出现时，另一侧也必须存在。
- `when_both_present`：两侧都存在时生成边，否则该规则不产生边。

当两侧都不存在时，规则不属于当前节点集合，不会失败。这使同一个全局 profile 可以同时容纳城镇、森林及其他地点类型规则，而不需要由 Region 选择 profile。

支持的匹配方式：

- `unique_pair`：两侧都必须唯一。
- `one_to_each`：一个来源节点连接每个目标节点。
- `each_to_one`：每个来源节点连接一个目标节点。

不支持模糊候选的自动排序、随机选择或默认配对。候选数量不符合匹配方式时明确失败。

## EdgeContractResult

结果包含：

```text
schema_version
compiler_version
stage
profile_id
profile_path
location_node_set_hash
source_location_node_hashes
edge_contracts
result_hash
```

`location_node_set_hash` uses canonical ordering of its
`LocationNodeResult` inputs. `result_hash` covers the complete canonical
`EdgeContractResult` with the `result_hash` field excluded.

每条边包含：

```text
edge_id
from_location_id
to_location_id
edge_type
bidirectional
access_rule
traversal_tags
source_rule_id
endpoint_region_relation
validation_flags
```

`edge_id` 由规则 ID、端点 ID 和方向性稳定生成。

`endpoint_region_relation` 在端点确定后根据两个节点的来源计算，只能是：

```text
same_region
cross_region
```

该字段是边生成后的派生属性，不能参与 profile 的端点选择。

`validation_flags` 是规则声明的真实约束，不保存“阶段通过”一类解释性报告。

## 生成行为

生成顺序为：

```text
校验节点结果集合
-> 检查全局 location_id 唯一
-> 加载显式 EdgeContractProfile
-> 根据节点事实匹配规则
-> 校验激活条件和候选数量
-> 生成稳定边 ID
-> 派生端点 Region 关系
-> 校验完整 EdgeContractResult
```

生成器不执行以下行为：

- 不创建 Semantic Role。
- 不创建 Location Node。
- 不创建默认边。
- 不创建最小生成树。
- 不要求所有节点全连通。
- 不把 `is_boundary` 解释为必须连接其他 Region。
- 不按 Region 预先划分边。

没有被任何规则匹配的真实节点可以保持无边状态。只有 profile 明确声明的必需规则缺少端点时才失败。

## 校验

`EdgeContractResultValidator` 校验：

- 输入节点集合和来源哈希一致。
- 所有 `location_id` 全局唯一。
- 所有边 ID 唯一。
- 所有边端点引用已有 Location Node。
- 不存在自环。
- 不存在重复端点对。
- 边类型、访问规则、通行标签和校验标记被 profile 支持。
- `source_rule_id` 引用真实规则。
- 每条边的字段与来源规则完全一致。
- `endpoint_region_relation` 与端点来源一致。
- profile 应生成的边没有缺失或多余。
- 未知字段明确失败。

## 编译边界

`RegionLocationGraphCompiler` 新增：

```text
compile_edge_contracts_result(inputs, edge_profile_path)
compile_edge_contracts_from_location_nodes_result(location_node_results, edge_profile_path)
```

v67.4 交付给后续阶段的产物是：

```text
EdgeContractResult
```

该产物不包含 Snapshot、Runtime 或 Scene 数据。

## 验证

无界面验证脚本：

```text
scripts/tests/v67_4_edge_contracts_test.gd
```

它验证：

- 城镇与森林节点共同生成有效边契约。
- 跨 Region 属性只在端点确定后派生。
- 相同输入产生相同结果。
- Region 字段不能进入端点选择器。
- 必需端点缺失明确失败。
- 多个等价候选明确失败。
- 未匹配节点不会获得默认边。
- 未知端点被结果校验器拒绝。
- 编译主链明确停在 v67.5 快照边界。

该验证脚本由 Godot 直接执行，不保留只用于承载脚本的测试场景。
