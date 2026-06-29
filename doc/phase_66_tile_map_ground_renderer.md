# v66 正式瓦片地面渲染

## 目标

v66 解决的是正常运行时的地面渲染压力，不是进场生成耗时。

此前 location 地面由 `DebugTileRenderer` 在 `_draw()` 中遍历整张 `LocationGrid` 绘制。地图扩大后，镜头移动、窗口刷新和 redraw 都会让整图绘制成本变得明显。v66 将正式地面改为 Godot 的瓦片地图层，由 `TileMapLayer` 持有地面单元。

## 已真实接入

- 新增 `TileMapGroundRenderer`，继承 `TileMapLayer`。
- `LocationRoot` 加载 location 时创建 `GroundRenderer` 节点。
- `LocationRoot` 从 `LocationGrid` 读取每格 terrain id，并一次性写入 `TileMapLayer`。
- `generated_wild_location.tscn`、测试村庄、测试野外、生成聚集地、生成室内等正式 location 场景不再默认挂载 `DebugTileRenderer`。
- 玩家移动、镜头移动、镜头缩放不会触发地面全量 rebuild。
- `set_cell_terrain(cell, terrain_id)` 支持单格地形更新，并同步修改 `LocationGrid`。
- `TileMapLayer.clear()` 保留为 Godot 原生清空单元接口；`clear_renderer_state()` 额外清理 v66 渲染器状态，避免覆盖原生 `clear()` 触发 warning-as-error。
- `get_ground_render_summary()` 暴露运行时统计，包括地图尺寸、映射格数、未知地形数、全量重建次数、单格更新次数和 debug renderer 状态。

## 数据化映射

地形到瓦片的映射放在：

```text
data/rendering/terrain_tile_map.json
```

映射使用 `terrain_id -> source_id / atlas / color`。当前项目还没有正式美术 tileset，所以 v66 使用配置中的颜色生成运行时 atlas，再交给 `TileMapLayer`。这不是继续使用调试绘制；正式地面主路径已经是瓦片地图层。

未知 terrain id 不会自动变成 grass。渲染器会记录未知 id，报错，并让本次 rebuild 失败。

## 调试层分离

`DebugTileRenderer` 没有删除，但它不再是正式地面渲染器。

当前规则：

- 默认不创建 `DebugTileRenderer`。
- `LocationRoot.set_debug_presentation_visible(true)` 时才临时创建调试地面节点。
- 关闭 debug 时释放该节点。
- `WildTerrainDebugOverlay` 仍是 debug overlay，默认隐藏。

## 分层

当前 location 场景分层为：

```text
ground layer：TileMapGroundRenderer / TileMapLayer
floor decoration / structure / roof：现有 building renderer
object layer：树、石头、采集物、门、设施
character layer：角色和 NPC
debug layer：DebugTileRenderer、WildTerrainDebugOverlay，仅 debug 开启时显示
```

树、石头、采集物、门、NPC 本轮没有塞入 TileMap，仍走现有对象系统。

## 本轮未做

- 不做加载界面。
- 不做相邻地图地貌连续性。
- 不重写野外生成器。
- 不重写世界图。
- 不做战斗高低差规则。
- 不做正式美术 tileset 导入。

## 风险

- 运行时 atlas 只是占位瓦片来源，之后接正式美术 tileset 时需要把 `terrain_tile_map.json` 的 `source_id / atlas` 指向真实资源。
- 进场生成和编译仍可能耗时，v66 只处理进入场景后的正式地面绘制路径。
- 如果后续新增 terrain id，必须同步更新 `terrain_tile_map.json`，否则 location 加载应失败并暴露错误。
