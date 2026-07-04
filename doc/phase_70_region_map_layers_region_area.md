# v70 RegionMap 多层地貌事实与 RegionArea 语义迁移

v70 修正的是世界地貌数据的层级问题。

旧路径把 `sea / coast / plain / forest / riverbank / foothill / rocky` 压进同一个世界级标签，再把这个标签同时交给区域、地点、地图 UI 和生成器使用。这个做法把水体关系、地形形态、植被覆盖、地表材质和局部特征混成了一层，所以会出现“山脚区域”“河岸区域”这类尺度错误。

v70 后，世界级 `RegionMap` 不再生成 `biome_map`。主路径只保存多层地貌事实。

## RegionMap

`RegionMap` 现在包含基础事实层：

- `elevation_map`：海拔。
- `moisture_map`：湿度。
- `water_map`：水体强度。
- `forest_map`：森林密度。
- `rock_map`：岩石强度。
- `slope_map`：坡度。
- `water_distance_map`：到水体距离。

并从这些事实层派生语义层：

- `hydro_context_map`：水体关系，例如海、近海、近水、干地。
- `landform_class_map`：地形形态，例如低地、平原、丘陵、高地、山地、河谷。
- `vegetation_class_map`：植被覆盖，例如森林、草地、湿地、稀疏植被。
- `surface_class_map`：地表材质，例如土壤、沙地、岩地、混合地表。
- `local_feature_map`：局部特征，例如山脚、河岸、溪流边、岩坡、林中空地。

这些层不是调试标签。它们是世界生成事实，会进入世界数据。

## RegionArea

`RegionArea` 是大尺度区域块，只使用 `area_type` 表示区域主类型。

允许的 `area_type` 包括：

- `plain`
- `forest`
- `hills`
- `highland`
- `mountain`
- `river_valley`
- `wetland`
- `lake_region`
- `coastland`
- `rocky_wilds`
- `settlement_area`

小尺度词不能作为 `RegionArea.area_type`。例如 `foothill`、`riverbank`、`creek_side`、`clearing`、`entrance`、`path`、`rocky_slope` 只能进入 `features`、`local_features` 或 `WorldLocationNode.local_role`。

## WorldLocationNode

`WorldLocationNode` 是真实可访问地点。

每个生成野外节点现在记录：

- `parent_region_id`
- `area_type`
- `local_role`
- `region_position`
- `region_cell`
- `region_patch`
- `region_context`
- `generator_profile_id`

`generator_profile_id` 由 `area_type + local_role` 派生。配置项为 `area_role_profile_map`。

不再使用：

- `region_biome`
- `biome_profile_map`
- `local_roles_by_biome`
- `local_role_profile_map`

## WorldTransitionEdge

世界边仍然只连接真实地点，不连接 `RegionArea`。

边现在记录：

- `from_area_type`
- `target_area_type`
- `area_relation`
- `transition_kind`

不再使用：

- `from_biome`
- `to_biome`
- `biome_relation`

## 地图 UI

区域地图显示层不再读取 `biome_map`。

底图颜色由多层事实合成：

- 水体层影响水域、近水、海岸倾向。
- 植被层影响森林和湿地表现。
- 地形层影响丘陵、高地、山地表现。
- 地表层影响岩地和沙地表现。

区域信息面板显示 `area_type`，地点信息面板显示所属区域、区域类型、`local_role` 和生成模板。

不保留“粗略地貌标签”调试展示。

## 仍未做

v70 不做玩家可操作的大地图传送。

v70 不做跨场景边缘无缝拼接。

v70 不重写野外局部瓦片生成器。

注意：局部野外生成器内部仍有 tile 级 `biome_map` 缓存，这是 v62/v63 的局部瓦片生成数据，不是世界级 `RegionMap.biome_map`。v70 删除的是世界主路径上的单标签地貌，不直接删除局部瓦片生成内部缓存；但调试摘要不再暴露 `biome_counts`，自然物件的 `source_layers` 也不再写出 `biome` 字段，避免把粗略地貌标签重新变成展示层事实。
