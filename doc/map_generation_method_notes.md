# Aftertale 地图生成方法笔记

这份文档是长期方法参考，不是实现清单。它描述各层适合采用的生成方法、数据形态、校验方式和失败边界。

## 1. 方法总览

Aftertale 使用语义编译式地图生成：

```text
粗语义输入
  -> 区域局部语义场
  -> 语义角色
  -> 地点节点
  -> 地点图
  -> 场景空间
  -> 校验固化
```

这套方法不依赖一个算法生成所有地图。不同层面对不同尺度的问题，应使用适合该尺度的表示和生成方法：

- World 处理粗尺度地貌与世界语义。
- Region 处理局部语义场与角色规划。
- Location Node 将语义角色展开为稳定地点。
- Edge Contract 将已有地点组织为可通行图。
- Scene 将节点和边表现为可玩空间。
- Snapshot 固化结构，Runtime 只消费结果。

每层先产出自身职责范围内的结构并完成校验，再交给下一层消费。任何阶段失败都停在该阶段，不允许下游通过补造对象使流程继续。

## 2. World Frame：低精度语义采样

World Frame 使用低精度几何和语义标记表达大尺度、稳定的世界背景。

可使用：

- polygon。
- mask。
- polyline。
- anchor。

这些数据可以表达：

- 大型平原。
- 大型森林带。
- 国家范围。
- 世界级大河。
- 王都。
- 世界级地标。
- 海岸线。
- 山脉。

World 查询应根据请求范围和采样参数给出：

- 国家或势力背景。
- 大地貌类型。
- 大型水体距离。
- 大型森林带距离。
- 核心城市距离。
- 边境、内陆、海岸等粗关系。

World 查询结果应保持低精度。它不返回普通城镇布局、普通森林结构、小型道路、农田、地点节点或场景对象，也不承担区域细节生成。

查询方法应满足：

- 相同输入得到稳定结果。
- 查询范围和采样精度显式记录。
- polygon、polyline、anchor 的语义类型可验证。
- 查询结果能够追溯到 World Source。
- 不因局部生成需要而向 World Source 写入细节。

## 3. Region：局部 feature map + 语义角色规划

Region 建立局部坐标系，并在 World Query Result 的粗语义约束下生成局部 feature maps。Region 是地点生成的局部上下文，不是图连接主体。

可用 feature maps：

- 可建造度。
- 坡度。
- 水系。
- 林地密度。
- 中心性。
- 道路倾向。
- 资源倾向。
- 特殊影响区。
- 占用图。
- 可达性估计。

Region 使用这些语义场选择角色点。每张 feature map 都应具有明确的坐标范围、采样分辨率、数值含义和来源规则。

角色选择方法：

- 每个角色具有 suitability score。
- 在 feature maps 上寻找高分候选。
- 选中后写入 claim map。
- 后续角色根据依附、避让、距离约束继续选择。
- 如果无法满足约束，生成失败。

suitability score 应由数据化规则计算。规则需要明确使用哪些 feature、权重或约束，不能把特定测试数据的结论写死为系统行为。

示例：

生活核心：

```text
高可建造度 + 高中心性 + 接近道路倾向
```

农业外围：

```text
平坦 + 接近水 + 接近生活核心
```

林中空地：

```text
中低林地密度 + 可达 + 与普通林地相邻
```

隐居小屋：

```text
低中心性 + 高林地密度 + 远离主路径倾向
```

特殊地标：

```text
高显著性 + 与其他角色保持合理距离
```

角色规划只创建有真实地点意义的 Semantic Role。它不规划外部连接，不生成连接端点，也不以未来连边为理由占用一个角色位置。

## 4. Location Nodes：语义角色展开

Semantic Role 转换为 Location Node。Location Node 是地图结构的基本单位。

转换原则：

- 一个 Location Node 必须来自一个真实语义角色。
- 节点类型由角色类型、区域类型和 profile 规则共同决定。
- 节点可以继承角色标签。
- 节点 ID 必须稳定。
- 节点 slug 应能反映来源语义。
- 节点必须保留 `source_role_id` 以支持追溯。
- 节点不携带边、场景、出口或目标地点。
- 节点即使没有边，也必须具有独立地点意义。

节点展开应采用显式 profile 映射。角色类型没有对应映射、映射数量不受支持或节点类型不合法时，生成必须失败。

示例：

```text
生活核心 -> town_center
农业外围 -> farmland
特殊地标 -> landmark_site
普通林地 -> common_woods
林中空地 -> forest_clearing
隐居小屋 -> hut_site
神龛 -> shrine_site
```

稳定 ID 应由稳定输入构成，例如作用域、来源命名空间、节点类型和稳定 slug。不得使用加载顺序、遍历偶然顺序或不可控随机值作为身份依据。

slug 冲突应明确失败。生成器不应通过追加数字、`copy` 或 `auto` 等后缀静默消解冲突，因为这种处理会掩盖来源角色或命名规则的问题。

## 5. Edge Contracts：节点之间的通行契约

Edge Contract 从 Location Node Result 生成。它读取已经存在的节点，并根据节点类型、角色来源、标签、局部关系和图 grammar 生成边。

边连接的是 Location Node。Region 归属只可用于边生成后的关系判定，不能成为边的端点，也不能要求 Region 提供连接占位物。

Edge Contract 应包含：

- `edge_id`。
- `from_location_id`。
- `to_location_id`。
- `edge_type`。
- `access_rule`。
- `traversal_tags`。
- `source_rule`。
- `validation_flags`。

每条边都应能够说明：

- 两端为何适合连接。
- 使用了哪条图 grammar 或显式规则。
- 通行是否带有条件。
- 该边是否参与主路径、隐藏路径或其他图语义。

Edge Contract 不应要求 Region 预先声明外部连接。同一区域或不同区域只是边生成后，根据两端节点来源信息得到的关系判定。

边生成规则示例：

小镇：

- 生活核心通常连接市场、神龛、农田和地标。
- 农田通常连接生活核心或道路类地点。
- 隐藏地点不直接挂到生活核心。
- 危险地点不直接连接生活核心，除非存在明确规则。

森林：

- 入口类地点通常连接普通林地。
- 普通林地可以连接空地、溪流和深林。
- 深林可以连接遗迹、隐居点和隐藏林地。
- 隐藏林地不能作为默认主路径节点。

图校验：

- 必需节点存在。
- 必需边存在。
- 所有非隐藏必需节点可达。
- 没有孤立任务节点。
- 条件边有明确条件。
- 隐藏边不会破坏主路径结构。
- 边两端节点都存在。

如果现有节点无法满足图 grammar，边生成失败。Edge 阶段不能增加角色，也不能补造节点端点。

## 6. Scene：按 Location 类型分派生成

Scene 读取 Location Node 和与该节点相关的 Edge Contract，将已固化的地图结构表现为可玩的具体空间。

生成顺序：

1. 读取节点和边。
2. 放置出口需求。
3. 生成主路径骨架。
4. 放置核心结构。
5. 填充地形、建筑、物件和装饰。
6. 校验出口、出生点、关键物件和 NPC 站位可达。
7. 固化 Scene Result。

不同 Location 类型使用不同生成器：

`town_center`：

```text
道路骨架 + 广场 + 建筑锚点 + 商店/井/公告板
```

`farmland`：

```text
田块网格 + 水渠 + 农舍 + 田间路
```

`forest_entrance`：

```text
林缘 + 主路 + 树墙 + 采集点
```

`forest_clearing`：

```text
密度场 + 空地中心 + 草丛/石头/采集物
```

`hut_site`：

```text
固定 prefab + 周边林地 + 小径
```

`shrine_site`：

```text
中心物件 + 仪式空间 + 可达路径 + 周边装饰
```

Scene 必须保证：

- Graph 有几条与当前节点相连的边，Scene 就有对应出口。
- Scene 不生成 Graph 没有的出口。
- 出口目标与 Edge Contract 一致。
- 玩家出生点不会堵死。
- 关键交互物可达。
- NPC 站位可达。

场景空间无法满足上述约束时应返回 Scene 生成失败。Scene 不能通过新增 Location Node、Edge 或无来源出口解决空间生成问题。

## 7. 聚落类 Scene 方法

聚落类 Scene 使用 feature maps 与 planning agents。

planning agents 不是 NPC，而是只在生成阶段运行的规划器。

可用 agent：

- `road_agent`。
- `house_agent`。
- `farm_agent`。
- `market_agent`。
- `shrine_agent`。
- `landmark_agent`。
- `decoration_agent`。

每个 agent 做三件事：

1. 提出候选位置。
2. 计算分数。
3. 成功后写入 claim map。

agent 的输入应包括场景边界、已有 claim、适用的 feature maps、节点语义和出口约束。agent 的输出应是可校验的放置提案，而不是直接无条件写入最终场景。

聚落生成顺序：

```text
道路倾向
  -> 主路骨架
  -> 广场或中心空间
  -> 建筑地块
  -> 农田或外围功能
  -> 装饰与细节
  -> 可达性校验
```

道路骨架优先连接 Edge Contract 要求的出口和节点核心空间。建筑、农田和装饰只能在不破坏主路径及关键可达性的前提下写入 claim map。

目标是生成具有功能、道路和生活感的聚落，而不是随机堆放建筑。

## 8. 自然类 Scene 方法

自然类 Scene 使用 density field。

适用于：

- 森林。
- 平原。
- 溪边。
- 山脚。
- 沼泽。
- 荒地。

生成顺序：

```text
基础地貌场
  -> 出口间主路径骨架
  -> 植被密度场
  -> 障碍物分布
  -> 空地采样
  -> 资源点采样
  -> 装饰细节
  -> 可达性校验
```

density field 应表达空间概率或倾向，不应绕过碰撞、可达性和节点语义约束。采样结果写入场景前需要经过占用检测和规则校验。

森林示例：

- 路径周围降低树密度。
- 远离路径提高树密度。
- 空地降低障碍密度。
- 深处提高遮挡和危险倾向。
- 采集点放在路径边或空地边。
- 小屋、遗迹和神龛需要局部清理可达空间。

主路径骨架来自当前节点关联边所形成的出口需求。自然场景生成器只能决定出口之间的空间表现，不能借此新增图连接。

## 9. 校验体系

每层都有独立校验。校验器只判断输入或结果是否符合契约，不负责补齐缺失对象。

World 校验：

- polygon 合法。
- polyline 合法。
- anchor 唯一。
- 查询结果稳定。
- 查询结果能够追溯到 World Source。

Region 校验：

- 局部事实不违背 World 粗语义。
- 必需角色存在。
- 角色距离合理。
- claim map 无冲突。
- unsupported 字段失败。
- 不包含连接声明或连接占位角色。

Location Node 校验：

- 节点 ID 唯一。
- 节点 slug 唯一。
- `source_role_id` 存在。
- 节点类型被 profile 支持。
- 禁止 edge、scene、spawn、tilemap 字段进入节点结果。
- 禁止占位节点。
- 每个节点具有可说明的独立地点意义。

Edge 校验：

- 边 ID 唯一。
- 两端节点存在。
- 图结构满足适用的 grammar。
- 必需节点可达。
- 隐藏边不破坏主路径。
- 条件边有明确条件。
- 不存在以 Region 为端点的边。

Scene 校验：

- 出口数量与边一致。
- 出口目标与边一致。
- 玩家出生点可达。
- 关键物件可达。
- NPC 站位可达。
- 碰撞不堵死主路。
- Scene 没有新增 Graph 不存在的出口。
- Scene Result 不包含新增 Location Node 或 Edge。

校验结果应具有稳定错误类别、对象标识和数据路径，以便日志、自动测试和生成工具准确定位失败来源。

## 10. 失败策略

失败停在对应阶段。

Region 失败：

```text
返回 Region 编译失败
```

Semantic Role 失败：

```text
返回角色生成失败
```

Location Node 失败：

```text
返回节点展开失败
```

Edge 失败：

```text
返回图结构失败
```

Scene 失败：

```text
返回场景生成失败
```

禁止跨层补洞：

- Scene 失败不能新增节点。
- Edge 失败不能新增角色。
- Node 失败不能新增默认 role。
- Region 失败不能伪造 World 背景。
- Runtime 不能接管生成失败。

缺失配置、缺失 profile、缺失映射、不支持字段、不支持类型、引用无效和约束无法满足都必须明确失败。生成器不得用默认对象、默认边、默认场景或空结果冒充成功。

## 11. 保存与运行

结构层保存 snapshot：

- Region Result。
- Semantic Role Result。
- Location Node Result。
- Edge Contract Result。
- Location Graph Snapshot。

结构 snapshot 应携带输入哈希、规则哈希、生成源信息和编译器版本信息，使加载方能够验证结构的一致性与兼容性。

表现层可以使用 seed 重建：

- TileMap 基础结构。
- 植被。
- 装饰。
- 非持久对象。

状态变化保存 diff：

- 交互物状态。
- NPC 状态。
- 门锁状态。
- 任务状态。
- 资源采集状态。
- 场景破坏状态。

运行时只读取：

- 当前 Location。
- Location Graph Snapshot。
- Scene Result 或 Scene 生成种子。
- Save diff。

运行时不生成世界结构。它不增加 Location Node，不增加 Edge，不规划新的图关系，也不在 Snapshot 不完整时猜测结构。

加载过程应先验证 Snapshot，再定位当前 Location，随后加载或重建 Scene Result，最后应用 Save diff。任一环节失败都应停止加载并暴露原因。

## 12. 总结

先生成语义结构，再生成空间表现。

World 提供粗背景。

Region 生成局部语义角色。

Location Node 成为基本地图单位。

Edge Contract 连接节点。

Scene 表现节点与边。

Snapshot 固化结构。

Runtime 只消费结构。
