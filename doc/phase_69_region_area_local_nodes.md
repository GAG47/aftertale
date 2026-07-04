# v69 区域块与局部可访问节点

v69 做的是世界数据层级拆分。它把“区域地图上的抽象区域”和“玩家能进入的真实地点”分开，避免把“北部森林”这类区域名直接当成可进入场景。

## 已真实接入

- 新增 `RegionAreaBuilder`，从 `RegionMap` 的连续地貌上构建 `RegionArea`。
- `WorldGraphGenerator` 主路径先生成 `RegionMap`，再生成 `RegionArea`，最后从区域块中放置真实 `WorldLocationNode`。
- 每个 generated_wild 地点节点写入：
  - `parent_region_id`：所属区域块。
  - `area_type`：所属区域的大尺度类型。
  - `local_role`：局部角色，例如入口、小路、空地、溪流边、深处、遗迹。
  - `region_position`、`region_cell`、`region_patch`、`region_context`：来自区域母图的多层上下文。
- 每条世界边写入：
  - `from_region_id`、`target_region_id`
  - `edge_scope`：`internal_region` 或 `between_regions`
  - `from_area_type`、`target_area_type`、`area_relation`
- `WorldGraphBlueprint` 和 `WorldLocationGraph` 会拒绝把 `RegionArea` 当成真实地点或转场目标。
- `WorldTransitionService` 的区域地图数据会返回 `region_areas` 和 `current_region_id`。
- `WorldLocationRegistry` 生成野外场景时会把 `parent_region_id` 和 `local_role` 传入局部生成上下文。
- `RegionMapView` 显示区域块标签，并在地点信息中显示所属区域和节点角色。

## 数据层级

```text
WorldData
  ├─ RegionMap：区域地貌母图
  ├─ RegionArea：抽象区域块，不可进入
  ├─ WorldLocationNode：真实可访问地点
  └─ WorldTransitionEdge：真实地点之间的连接
```

`RegionArea` 不是场景。玩家不会进入“森林区域 03”。玩家进入的是“森林入口 00”“森林小路 02”这类真实地点。

## 局部节点生成

世界节点现在不是直接独立随机成某种野外。流程是：

```text
区域地貌母图
→ 连续地貌切成区域块
→ 区域块提供候选位置和节点预算
→ 节点取得 parent_region_id 和 local_role
→ area_type + local_role 决定可用的 generated_wild profile
```

如果某个区域类型没有局部角色，或者某个局部角色没有可用生成模板，生成会明确失败，不会自动退回平原。

## 边的含义

世界边只连接真实地点，不连接区域块。

```text
正确：森林入口 → 林间小路
正确：深林区 → 山脚入口
错误：森林区域 → 山脚区域
```

边上的 `edge_scope` 用来说明它是同一区域内部连接，还是两个区域之间的连接。

## 与 v68 地图的关系

v68 区域地图现在能显示区域块标签。地图显示层仍然不修改世界数据，不传送玩家，不生成地点，也不改变入口规则。

## 未支持

- 还没有生成“区域内部 5 到 15 个节点”的完整局部子网络规模。
- 还没有 `RegionArea` 的手工命名系统；目前使用地貌通用中文名。
- 还没有道路跨区域的真实地形投射。
- 还没有区域之间的精细入口类型，例如山口、渡口、林门。
- 还没有玩家可缩放或分层查看的正式大地图 UI。

## 验证

新增 `scripts/tests/v69_region_area_local_nodes_smoke.gd`，验证：

- 生成世界包含 `region_areas`。
- `RegionArea` 不会进入 `locations`。
- 真实地点都有 `parent_region_id` 和 `local_role`。
- 真实地点的位置属于自己的区域块。
- 地点生成模板来自“区域类型 + 局部角色”的映射。
- 世界边只连接真实地点，并记录区域关系。
- 区域块不能作为可物化场景或转场目标。
- 不支持的局部角色模板会明确失败。
