# Phase 2 Scene System

本文档记录阶段 2 已建立的场景系统。当前阶段使用调试瓦片表现，不引入正式美术，不实现角色系统、行动系统或战斗系统。

## 已建立内容

```text
瓦片地图场景结构：scripts/systems/scenes/location_root.gd
场景元数据：data/locations/*.json
场景入口 / 出口：data/locations/*.json 的 entrances / exits
场景坐标体系：scripts/systems/scenes/location_grid.gd
格子占用规则：LocationGrid.can_enter / register_object
场景内对象注册：LocationRoot 根据 objects 数据生成并注册 LocationObject
场景切换：SceneLoader.load_location
调试瓦片表现：scripts/systems/scenes/debug_tile_renderer.gd
```

## 测试场景

```text
data/locations/test_field.json
scenes/locations/test_field.tscn

data/locations/test_clearing.json
scenes/locations/test_clearing.tscn
```

项目启动后会进入 `test_field`。可用 `WASD` 或方向键移动白色调试点。移动到黄色出口格会通过 `SceneLoader` 切换到目标地点，并落在目标入口。

调试点只是验证场景坐标、占用和切换的工具，不是玩家角色系统。正式玩家和 NPC 会在后续角色实体系统中接入。

## Location JSON 结构

```text
id              场景唯一 ID
display_name    显示名
size            width / height
tile_size       单格像素尺寸
default_entrance 默认入口
tiles           瓦片字符矩阵
terrain         字符到地形定义的映射
entrances       入口定义
exits           出口定义
objects         场景对象定义
state           场景状态占位
```

`tiles` 决定基础地形是否可通行。`objects` 可以注册阻挡占用。最终通行判断由 `LocationGrid.can_enter` 统一处理。

## 规则边界

场景系统负责回答：

```text
当前在哪个场景。
场景有多大。
某个格子是什么地形。
某个格子能不能进入。
某个格子有没有阻挡对象。
某个格子是不是出口。
场景内有哪些对象和状态。
```

场景系统不负责：

```text
角色属性
NPC 逻辑
任务推进
物品发放
战斗结算
AI 生成
```

这些系统后续必须通过规则层和明确接口接入，不能直接从表现层改写世界事实。

## 美术替换原则

当前调试瓦片由 `DebugTileRenderer` 用颜色块绘制。正式美术进入后，可以把表现层替换为 Godot TileMap / TileMapLayer 或其他瓦片渲染方案，但应继续依赖 `LocationGrid` 的坐标、通行和占用规则。
