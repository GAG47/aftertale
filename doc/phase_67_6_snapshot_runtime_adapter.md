# Phase 67.6 Snapshot Runtime Adapter

## 目标

v67.6 将 v67.5 已经验证通过的 `LocationGraphSnapshot` 接入运行时：

```text
LocationGraphSnapshot
-> LocationGraphRuntimeAdapter
-> current location view
-> adjacent location views
-> placeholder Location scene
```

本阶段只证明 Snapshot 能够驱动当前地点状态和相邻地点切换。占位 Location 场景不是最终游戏场景。

## Runtime Adapter

核心实现：

```text
scripts/systems/regions/location_graph_runtime_adapter.gd
```

`load_snapshot(snapshot_value)` 接收 `Variant`，因此非 Dictionary 输入能够返回明确错误，而不是被参数类型系统截断。

加载顺序：

```text
清空旧 Runtime 状态
-> 确认输入是 Dictionary
-> 调用 LocationGraphSnapshotValidator
-> 建立 locations_by_id
-> 建立 edges_by_location_id
-> 选择稳定 current_location_id
```

Adapter 不调用 `normalize_snapshot()`，不修改调用方传入的 Snapshot。内部 Snapshot、Location Node、Edge Contract 和所有查询结果均使用深复制数据。

加载失败后 Adapter 保持未加载状态，不继续使用先前 Snapshot 的 current location 或索引。

## 起始地点

v67.5 Snapshot 不包含 `start_location_id`。v67.6 也不读取或兼容该字段。

起始地点规则固定为：

```text
所有 location_id 按字典序排序
-> 选择第一个 location_id
```

未来的指定起点必须来自 Snapshot 之外的 Runtime 启动配置，不能写回图结构。

## Runtime 索引

`locations_by_id`：

```text
location_id -> Location Node copy
```

`edges_by_location_id`：

```text
location_id -> Array[edge_runtime_view]
```

每个运行时边视图包含：

```text
edge_id
from_location_id
to_location_id
target_location_id
target_location_name
target_location_type
target_location_tags
edge_type
bidirectional
reverse_traversal
access_rule
traversal_tags
source_rule_id
display_label
```

边方向严格服从契约：

```text
from_location_id -> to_location_id 始终建立
bidirectional == true -> 再建立反向视图
bidirectional == false -> 不建立反向视图
```

相邻地点按 `target_location_id`、`edge_id` 稳定排序。

## 当前地点视图

`get_current_location_view()` 返回只读运行时视图：

```text
graph_id
snapshot_id
current_location_id
current_location_name
current_location_type
current_source_role_type
current_source_role_slug
current_location_tags
neighbors
```

Location Node 尚无正式 `display_name`。占位名称只从已有字段中选择：

```text
source_role_slug
-> node_slug
-> location_type
-> location_id
```

该名称只用于 Runtime UI，不写入 Snapshot。

## 地点切换

`travel_to_location(target_location_id)` 只允许切换到当前地点的直接邻接地点。

以下情况明确失败且不改变 `current_location_id`：

- Adapter 尚未加载 Snapshot。
- 当前 Location 不存在。
- 目标 Location 不是当前地点的邻接地点。
- Edge 使用 v67.6 不支持的访问规则。

v67.6 只执行：

```text
access_rule == always
```

其他访问规则不会被静默绕过。本阶段不接任务、物品或条件系统。

成功切换只更新 Adapter 内存中的 `current_location_id`，并发出 `location_changed` 信号。Snapshot、节点和边保持不变。

## 占位 Location 场景

生产场景：

```text
scenes/locations/snapshot_runtime_location.tscn
```

场景显示：

- `graph_id`
- `snapshot_id`
- 当前 `location_id`
- 当前地点类型、来源角色和标签
- 每个相邻地点的目标 ID、Edge ID、Edge 类型和通行标签

相邻地点使用 Button 列表。点击可通行按钮调用 Adapter 的 `travel_to_location()`，成功后通过 `location_changed` 刷新显示。

该场景不读取或修改 Adapter 私有索引，不生成 Location Node、Edge、出口、Spawn 或地图内容。

## 主启动

主启动流程现在是：

```text
compile_to_location_graph_result()
-> LocationGraphSnapshot
-> 原始 Snapshot 调试显示
-> LocationGraphRuntimeAdapter.load_snapshot()
-> snapshot_runtime_location.tscn
```

新游戏开始和返回标题时会清理旧 Adapter 与占位场景，避免重复加载保留旧状态。

主启动继续使用本次编译得到的内存 Snapshot：

- 不调用 SnapshotStore。
- 不读取默认 Snapshot。
- 不写 `user://`。
- 不自动保存。

## 错误处理

Adapter 明确处理：

- Snapshot 不是 Dictionary。
- SnapshotValidator 拒绝输入。
- `location_nodes` 为空。
- Location 缺少 ID。
- Edge 引用未知 Location。
- 当前 Location 不存在。
- 非邻接切换。
- 未加载时查询或切换。

非法 Snapshot 的主路径由 v67.5 Validator 拒绝，Adapter 返回 Validator 错误。索引构建仍保留防御性引用检查，但不绕过 SnapshotValidator。

## 验证

无承载场景测试：

```text
scripts/tests/v67_6_snapshot_runtime_adapter_test.gd
```

覆盖：

- 合法 Snapshot 加载。
- 稳定起始地点。
- Location 和 Edge 索引数量。
- 当前地点与邻接视图。
- 相邻切换成功。
- 非邻接切换失败。
- SnapshotValidator 错误传播。
- 空节点防御性失败。
- 未加载查询和切换失败。
- 重复加载重置 current location。
- 失败重载清空旧 Runtime 状态。
- 单向边不建立反向邻接。
- 切换不修改原始或内部 Snapshot。
- 占位场景显示与按钮切换。

真实项目主启动单独通过 Godot 启动命令验证，因为独立 `--script` 测试环境不建立完整项目 Autoload 编译上下文。

## 明确排除

v67.6 不实现：

```text
TileMap
真实地图或建筑布局
房屋内部
NPC 或 NPC 移动
任务
战斗
存档 diff
Snapshot 保存
spawn_id
exit_id
真实门
玩家自由移动或寻路
```

Runtime 状态不写回 Snapshot。
