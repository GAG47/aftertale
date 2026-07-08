# Aftertale 地图生成架构

## 1. 总体目标

Aftertale 的地图生成采用“语义编译式地图生成”。地图不是由单个算法一次性产出，也不是在玩家移动时临时拼接，而是由职责明确的多个阶段逐层生成、校验并固化。

核心流程为：

```text
World Frame
  -> Region Layer
  -> Semantic Roles
  -> Location Nodes
  -> Edge Contracts
  -> Location Graph Snapshot
  -> Runtime
  -> Location Scene
```

这条流程遵守三个基本边界：

- 生成阶段负责创造、校验和固化世界结构。
- 运行阶段只读取已经固化的结构并执行状态迁移。
- 场景阶段只表现 Location Node 与 Edge Contract 已经规定的空间事实。

Location Node 是地图结构的基本单位。Region 只为 Location Node 的生成提供上下文、命名空间和局部生成边界。Edge 连接 Location Node，不连接 Region。Scene 和 Runtime 都不能反向创造地图结构。

## 2. 分层职责

### World Frame

World Frame 是粗尺度世界底板，用于表达跨越大范围空间仍然稳定成立的世界事实。

它负责：

- 大陆、海洋、大山脉、大河流、大平原、大森林带等粗尺度地貌。
- 国家范围、文化圈、世界级地标和少数核心城市。
- 提供低精度语义查询。
- 为局部生成提供稳定、可重复查询的粗语义背景。

它不负责：

- 普通城镇。
- 普通森林。
- 小溪、小丘、农田、道路和村口。
- 区域内部结构。
- 地点节点。
- 通行边。
- TileMap。
- NPC 站位。
- 任务点。

World Frame 的输出不是可玩地图，也不是 Location Graph，而是供后续阶段查询的粗语义背景。

### Region Layer

Region Layer 是局部生成上下文。Region 用于限定一次局部生成所依赖的空间范围、语义范围和命名范围，但不是地图图结构的基本单位。

它负责：

- 接收 World Frame 的粗语义背景。
- 建立局部坐标系。
- 生成区域尺度事实。
- 生成局部 feature maps。
- 规划具有真实地点意义的语义角色。
- 为生成结果提供命名空间和来源追踪范围。

它不负责：

- 声明外部连接。
- 制造边界占位节点。
- 生成通行边。
- 生成 TileMap。
- 生成玩家出口。
- 生成跨区域关系。

Region 的意义是帮助生成真实 Location Node。Region 不是边的端点，也不因连接需求决定任何 Location Node 是否存在。

“同一区域内”和“不同区域之间”只能在 Edge 生成后，根据两端 Location Node 的归属信息进行判定。该判定是 Edge 的派生属性，不是 Region 预先声明的连接事实。

### Semantic Roles

Semantic Role 是从区域局部事实中抽出的地点功能角色。它描述局部空间中需要存在什么性质的地点，以及该地点应满足什么语义约束。

例如：

- 生活核心。
- 农业外围。
- 普通林地。
- 深林。
- 特殊地标。
- 隐居点。
- 资源点。
- 市场。
- 神龛。
- 林中空地。

Semantic Role 不是最终地点，但必须对应真实地点意义。每个角色都应能够说明它为何作为一个地点存在，以及它从哪些局部事实和规则中产生。

不允许存在只为未来连边服务的角色，也不允许以入口、边界或连接需求为理由制造没有独立地点意义的角色。

### Location Nodes

Location Node 是地图结构的基本单位。它表达一个能够被图结构引用、能够被运行时定位、能够由场景表现的真实地点。

每个 Location Node 必须满足：

- 有稳定 ID。
- 有唯一且稳定的节点 slug。
- 有明确地点类型。
- 有可追溯的来源角色。
- 有标签或语义属性。
- 有独立地点意义。
- 即使暂时没有任何 Edge，也不是占位物。

Location Node 的存在由地点语义决定，不由未来可能出现的连接决定。节点可以属于某个 Region 的生成结果，但 Region 归属只是来源和命名信息，不改变节点作为基本单位的地位。

Location Node 不包含：

- `edge_id`。
- `target_location_id`。
- `target_region_id`。
- `scene_path`。
- `spawn_id`。
- `tilemap`。
- `exit_id`。
- `travel_type`。
- `access_rule`。
- `direction_hint`。

这些字段属于连接、场景或运行阶段。把它们写入 Location Node 会混淆节点事实与后续消费事实。

### Edge Contracts

Edge Contract 负责表达 Location Node 之间的通行关系。每条边的两个端点都必须是已经存在的 Location Node。

边连接节点，不连接区域。边生成不能要求 Region 预先声明连接，也不能为了获得端点而补造 Location Node。

Edge Contract 可以在生成后被判定为：

- 同一区域内的节点连接。
- 不同区域之间的节点连接。
- 主路径连接。
- 隐藏连接。
- 条件连接。

这些分类均来自边和两端节点已经形成的事实。它们不能反过来决定节点是否存在，也不能成为 Region 生成占位节点的依据。

Edge Contract 应保存可验证的来源规则和通行语义，使后续阶段能够判断边为何存在、如何通行以及需要满足什么条件。

### Location Graph Snapshot

Location Graph Snapshot 是完成校验并固化后的图结构，是 Runtime 消费地图结构的唯一权威来源。

它应该保存：

- Location Nodes。
- Edge Contracts。
- 图校验结果。
- 生成源信息。
- 输入哈希。
- 规则哈希。
- 编译器版本信息。

Snapshot 必须能够证明其节点、边、规则和来源属于同一次一致的生成结果。Runtime 读取 Snapshot，不重新推理节点或边，也不在加载过程中补齐缺失结构。

### Runtime

Runtime 只消费固化结果。

它负责：

- 维护当前 Location 状态。
- 查询由 Edge Contract 给出的可达目标。
- 发出场景加载请求。
- 执行玩家从一个 Location 到另一个 Location 的状态切换。
- 将持久状态差异应用到对应的 Location Scene。

它不负责：

- 生成新节点。
- 生成新边。
- 静默补配置。
- 自动转入另一套地图路径。
- 在玩家移动时临时规划地图。
- 接管任何生成阶段的失败。

Runtime 遇到 Snapshot 缺失、结构不兼容或引用无效时必须明确失败，不能把运行时行为当作地图生成器的兜底。

### Location Scene

Location Scene 是 Location Node 的可玩具体空间。它消费节点事实和与该节点相关的 Edge Contract，并将图结构表现为可行走、可交互的场景。

它负责：

- 根据 Location Node 和 Edge Contracts 生成或加载 TileMap。
- 根据图边生成对应出口。
- 放置场景对象、NPC 站位和交互物。
- 校验出口、出生点、关键物件和 NPC 站位可达。
- 固化可重复加载的 Scene Result，或保存能够稳定重建表现层的种子。

Scene 不能新增 Location Node。

Scene 不能新增 Edge。

Scene 不能制造 Location Graph 中不存在的出口。

如果场景无法表现图结构要求的出口或关键路径，结果必须是场景生成失败，而不是改变 Location Graph。

## 3. 数据流

完整数据流为：

```text
World Source
  -> World Query Result
  -> Region Input
  -> Region Local Facts
  -> Semantic Role Result
  -> Location Node Result
  -> Edge Contract Result
  -> Location Graph Snapshot
  -> Runtime Location State
  -> Location Scene Result
```

各阶段的数据责任如下：

| 阶段 | 明确输入 | 明确输出 | 核心校验 |
| --- | --- | --- | --- |
| World 查询 | World Source、查询范围、查询参数 | World Query Result | 几何合法、查询稳定、结果属于请求范围 |
| Region 编译 | World Query Result、Region Input、局部规则 | Region Local Facts | 输入完整、局部事实不违背粗语义 |
| 角色规划 | Region Local Facts、角色规则 | Semantic Role Result | 必需角色存在、角色来源明确、局部约束成立 |
| 节点展开 | Semantic Role Result、节点 profile | Location Node Result | ID 与 slug 唯一、来源角色有效、节点类型受支持 |
| 边生成 | Location Node Result、图 grammar | Edge Contract Result | 两端节点存在、边规则有效、图约束成立 |
| 图固化 | 节点结果、边结果、校验结果 | Location Graph Snapshot | 哈希一致、引用完整、结构兼容 |
| 运行状态 | Snapshot、存档状态 | Runtime Location State | 当前节点存在、可达查询只使用现有边 |
| 场景生成 | 当前节点、相关边、场景规则、种子与状态差异 | Location Scene Result | 出口与边一致、关键空间可达、没有新增图结构 |

每一步都必须具备明确输入、明确输出和明确校验。上游结果只有通过本层输入校验后才能被消费；本层结果只有通过本层输出校验后才能交给下一层。任何阶段都不能用自身职责之外的数据补洞。

## 4. 失败处理

所有失败必须在发生阶段明确暴露，并携带足以定位输入、规则和数据路径的信息。

必须明确失败的情况包括：

- 缺配置失败。
- 缺 profile 失败。
- 缺 role 映射失败。
- 不支持字段失败。
- 不支持类型失败。
- 校验失败。
- 哈希不匹配失败。
- Snapshot 不兼容失败。

失败结果至少应指出：

- 失败阶段。
- 失败对象的稳定标识。
- 违反的规则或缺失的配置键。
- 对应的数据来源。
- 可供日志和测试断言使用的稳定错误类别。

禁止：

- 自动补默认节点。
- 自动补默认边。
- 自动补默认场景。
- 自动跳过未知字段。
- 自动忽略缺失配置。
- 自动转入其他实现路径。
- 为了让流程完整而生成占位对象。

明确失败是生成契约的一部分。失败不能由下游阶段吞掉，也不能通过跨层创造对象来掩盖。

## 5. 保存策略

地图保存采用 seed 与 snapshot 混合策略。结构事实必须固化，允许确定性重建的表现数据可以由 seed 生成，玩家行为造成的持久变化保存为 diff。

结构层必须保存 snapshot：

- Region Result。
- Location Graph。
- Edge Contracts。

为保证结构来源可追溯，结构层还应保存输入哈希、规则哈希、编译器版本信息和必要的生成源标识。仅保存 seed 不能替代结构 snapshot，因为规则或数据环境发生变化时，同一个 seed 未必代表同一个结构。

表现层可以使用 seed 重建：

- TileMap 基础布局。
- 植被。
- 装饰。
- 非持久物件。

seed 重建必须满足确定性要求，并接受 Scene 校验。无法稳定重建或重建成本不合适的表现结果可以直接固化为 Scene Result。

发生状态变化后必须保存 diff：

- 箱子被打开。
- 门被解锁。
- NPC 搬家。
- 树被砍。
- 作物成长。
- 任务物品被拿走。

diff 必须引用已经存在的结构或场景对象，不能借由存档写入新的 Location Node 或 Edge。加载顺序应为：读取结构 snapshot，获得或重建 Scene Result，再应用持久状态 diff。

## 6. 架构禁令

- 禁止最小闭环。不能为了让整条流程看起来可运行而伪造尚未具备语义依据的结构。
- 禁止为了演示完整流程而硬造默认结果。
- 禁止 Region 主导跨区域连接。
- 禁止把 external intent 变成节点。
- 禁止 boundary placeholder node。
- 禁止 Scene 反向创建 Location。
- 禁止 Runtime 临时生成结构。
- 禁止编译器使用 `ensure_xxx_exists` 式逻辑补洞。
- 禁止把测试语义写进系统代码。
- 禁止未知字段静默通过。
- 禁止用连接分类决定 Location Node 是否存在。
- 禁止 Edge 生成阶段补造端点。
- 禁止 Scene 用额外出口扩展 Location Graph。
- 禁止 Runtime 在结构缺失时推测节点、边或目标。

任何实现只要违反其中一项，就越过了所属层的职责边界，不能作为地图生成主路径的一部分。
