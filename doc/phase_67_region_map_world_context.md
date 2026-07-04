# v67 区域地貌上下文

v67 建立了“局部地点来自同一张区域事实”的主路径。

v70 已经迁移 v67 的数据表达方式：世界级 `RegionMap` 不再保留单一地貌标签图，不再把不同尺度、不同维度的词压进一个字段。

## 当前主路径

```text
world_seed
-> RegionMap 多层事实
-> RegionArea 大尺度区域块
-> WorldLocationNode 真实可访问地点
-> area_type + local_role 派生局部生成模板
-> generated_wild 接收 RegionPatch / region_context
```

`RegionMap` 是世界数据的一部分，不是调试信息。

## RegionMap

当前 `RegionMap` 保存这些事实层：

- `elevation_map`
- `moisture_map`
- `water_map`
- `forest_map`
- `rock_map`
- `slope_map`
- `water_distance_map`

并保存这些派生层：

- `hydro_context_map`
- `landform_class_map`
- `vegetation_class_map`
- `surface_class_map`
- `local_feature_map`

不再保存世界级 `biome_map`。

## WorldLocationNode

生成野外地点记录：

- `parent_region_id`
- `area_type`
- `local_role`
- `region_position`
- `region_cell`
- `region_patch`
- `region_context`
- `generator_profile_id`

`generator_profile_id` 由 `area_type + local_role` 派生。缺少映射或模板不支持时明确失败，不回退平原。

## WorldTransitionEdge

世界边根据真实地点连接，并记录：

- `from_region_position`
- `to_region_position`
- `from_area_type`
- `target_area_type`
- `area_relation`
- `transition_kind`
- `region_distance`

世界边不连接 `RegionArea`。

## RegionPatch 进入野外生成

`generated_wild` 通过世界地点注册器接收 `RegionPatch` 和 `region_context`，再交给局部野外生成器。

这些上下文影响局部生成倾向，例如：

- 靠水区域提高水与湿地倾向。
- 森林区域提高树木和植被密度。
- 岩石和坡度较高区域提高岩石、坡地和高低差语义。

这是给现有野外生成器提供上游上下文，不是重写野外生成器。

## 明确失败

这些情况应失败：

- `RegionMap` 缺少任意多层事实图。
- `RegionArea` 缺少 `area_type`。
- `RegionArea.area_type` 使用山脚、河岸、入口、小路等小尺度词。
- `WorldLocationNode` 缺少 `area_type`、`local_role`、`region_patch` 或 `region_context`。
- `area_type + local_role` 没有可用生成模板。
- 世界边缺少区域类型关系。

## 不包含

v67/v70 不做：

- 跨地点边缘无缝拼接。
- 河流跨地点精确对齐。
- 地图点击传送。
- 重写局部野外生成器。
