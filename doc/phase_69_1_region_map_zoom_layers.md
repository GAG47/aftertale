# v69.1 区域地图缩放层级

## 目标

v69.1 解决区域地图显示层级混乱的问题。

v69 后，区域块和局部地点都已经存在于世界数据中：

- RegionArea：区域块，表示一片地理范围。
- WorldLocationNode：真实可访问地点，玩家可以进入的地点节点。

这两个概念不能在同一层级里全量混合显示。v69.1 将地图改为缩放式单视图：

- 缩小时看区域。
- 放大时看当前聚焦区域内部地点。
- 中间用透明度渐变，不做按钮式硬切换。

## 缩放状态

`RegionMapView` 现在维护这些只读 UI 状态：

- `zoom_level`：当前缩放倍率。
- `region_layer_alpha`：区域层透明度。
- `location_layer_alpha`：地点层透明度。
- `focused_region_id`：当前聚焦区域。
- `selected_region_id`：当前选中区域。
- `selected_location_id`：当前选中地点。
- `selection_type`：选择类型，值为 `region_area`、`location_node` 或 `none`。

缩放输入：

- 鼠标滚轮上滚：放大。
- 鼠标滚轮下滚：缩小。
- `+`：放大。
- `-`：缩小。
- `M` / `Esc`：关闭区域地图。

## 层级规则

远景只显示区域层：

- RegionArea 名称。
- RegionArea 范围。
- 大尺度区域类型颜色。
- 当前玩家所在区域高亮。
- 区域之间的弱化邻接关系。

远景不显示：

- WorldLocationNode。
- 局部地点名。
- 区域内部边。

近景只显示当前聚焦区域内部地点：

- `parent_region_id == focused_region_id` 的 WorldLocationNode。
- 两端都属于 `focused_region_id` 的区域内部边。
- 当前玩家所在地点，如果它位于当前聚焦区域内。

近景不显示：

- 其他区域的地点。
- 其他区域的内部边。
- 区域之间的边。
- 全世界地点全集。

## 平滑过渡

区域层和地点层通过缩放区间内的透明度渐变切换。

这避免了旧式硬切：

```text
小于阈值只显示区域
大于阈值只显示地点
```

当前规则是：

```text
缩放较小时：region_layer_alpha 接近 1，location_layer_alpha 接近 0
过渡区间：两个透明度连续变化
缩放较大时：region_layer_alpha 接近 0，location_layer_alpha 接近 1
```

## 聚焦区域

地点层只展开一个聚焦区域。

聚焦区域选择优先级：

1. 鼠标所在 RegionArea。
2. 当前玩家所在 RegionArea。
3. 当前选中的 RegionArea。
4. 任意有效 RegionArea。

这样地图不会在放大后展开所有区域的地点。

## 选择与信息面板

点击 RegionArea：

- 只选择区域。
- 显示区域信息。
- 不转场。
- 不加载场景。

点击 WorldLocationNode：

- 只选择地点。
- 显示地点信息。
- 不转场。
- 不加载场景。

区域信息包含：

- 区域名称。
- 区域类型。
- 包含地点数量。
- 相邻区域。
- 区域特征。
- 是否为当前玩家所在区域。

地点信息包含：

- 地点名称。
- 所属区域。
- `local_role`。
- `area_type`。
- `generator_profile_id`。
- 是否为当前地点。
- 区域内连接地点。

## 数据边界

v69.1 不改变世界生成主逻辑。

RegionArea 仍然不是可进入地点：

```text
RegionArea 只用于区域显示和聚焦。
WorldLocationNode 才是可访问地点。
```

地图 UI 不会调用场景加载，也不会绕过世界转移服务。

## 本轮不做

v69.1 不做：

- 地图点击传送。
- 加载界面。
- 世界图生成规则修改。
- 区域生成算法修改。
- 局部场景生成修改。
- TileMapLayer 地面渲染修改。
- 区域之间边在近景层展开。

## 测试

新增 `scripts/tests/v69_1_region_map_zoom_layers_smoke.gd`。

测试覆盖：

- 地图有 `zoom_level`。
- 远景区域层高、地点层低。
- 近景区域层低、地点层高。
- 过渡区透明度连续变化。
- 远景只暴露 RegionArea。
- 近景只暴露 `focused_region_id` 内部地点。
- 近景只暴露当前聚焦区域内部边。
- 鼠标所在区域优先成为聚焦区域。
- 没有鼠标区域时使用当前玩家所在区域。
- 点击 RegionArea 不触发转场。
- 点击 WorldLocationNode 不触发转场。
- `M` / `Esc` 可以关闭地图。

该测试不要求固定区域名，不要求固定地点名。
