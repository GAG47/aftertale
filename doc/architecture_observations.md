# Aftertale 当前架构观察

本文档是对当前代码结构的经验性观察，不是严格规则文档。它的目标是帮助后续开发者理解项目现状、已有协作路径和继续演化时值得注意的边界。

## 1. 当前项目已经形成的架构倾向

当前看来，Aftertale 已经从单一 demo 发展成多系统 RPG 框架。项目中已经存在全局运行骨架、数据定义入口、场景运行结构、行动规则层、多个玩法系统、存档基础、调试表现和阶段 smoke tests。

比较明显的倾向是：

- 运行入口集中在 Autoload 和 `scripts/core/`。
- 规则能力集中在 `scripts/systems/`。
- 可配置内容主要来自 `data/` 下的 JSON。
- 可实例化表现主要来自 `scenes/` 与场景脚本。
- 玩家行为尽量通过 `ActionSystem`、`GameAction` 和 `ActionResult` 表达。
- 手写 location 和生成 location 正在汇入同一套 `DefinitionLoader` / `SceneLoader` / `LocationRoot` / `LocationGrid` / `LocationObject` 运行结构。

这说明新增能力前，值得先检查是否已有系统入口。很多能力已经有基本位置，即使还不完整，也比另起一套平行结构更容易保持项目一致。

## 2. 当前代码中比较重要的协作路径

### 启动和场景路径

`project.godot` 指向 `scenes/boot/main.tscn`，`main.gd` 配置 `SceneLoader`，再加载默认 location。这个路径是当前所有运行状态的起点。

值得注意的是，`main.gd` 同时也承担 smoke test flag 检查。如果 `data/run_v*_smoke.json` 存在，主流程会转入对应测试脚本。这使测试入口和正常启动入口共享同一个 boot 场景。

### 数据到运行场景路径

`DefinitionLoader` 是数据定义进入运行系统的关键入口。普通 JSON 会被直接加载和缓存，生成型 location 会根据 generator 类型转入 `VillageRoadGenerator` 或 `TileSceneCompiler`。生成室内 manifest 也会被注册成可通过 location id 解析的 location。

这条路径意味着生成内容最终必须满足 location 数据合同，否则 `LocationRoot` 和 `LocationGrid` 无法稳定运行。

### 输入到行动路径

玩家输入先进入 `InputManager`，然后由当前 `LocationRoot` 解释为移动、交互、休息、相机、战斗选择或 UI 操作。探索中的交互会经过候选解析，再进入 `ActionSystem` 创建和提交具体 `GameAction`。

当前看，`ActionResult` 是世界变化、反馈和表现层刷新的共同语言。后续新增 action 时，建议认真设计 `world_changes`，因为场景表现、UI 反馈和测试都可能依赖它。

### 玩法系统路径

物品、作物、制作、商店、任务、对话、队伍、关系、日程和战斗系统都已经有系统入口。它们通常不直接由 UI 改世界，而是通过 action、系统 API 和 save state 协作。

这条路径已经能支撑基础 RPG 闭环，但不同系统的边界还在逐步稳定。例如战斗有自己的请求接口，部分战斗行为还没有完全纳入通用 action 结构。

### 程序生成路径

聚落生成已经形成 policy / session / agent / proposal / resolver / blueprint / compiler 的流程。当前它不只是地图随机生成，而是在输出可运行地点、建筑、室内、对象 hook、schedule targets 和生成摘要。

这条路径是当前项目最复杂的协作路径之一。后续修改时应优先阅读 `SettlementGenerationSession`、各类 agent、`ProposalResolver` 和 `TileSceneCompiler`，同时查看 v60 到 v65 的阶段文档和 smoke tests。

## 3. 当前已经暴露过的结构性问题

当前代码中可以观察到几个结构性压力点：

- `LocationRoot` 职责较重：它同时处理 location 加载、对象和角色生成、输入响应、交互候选、相机、NPC、作物、战斗 overlay、反馈表现和 scene transition。后续继续扩展时，可能需要提炼更清晰的子模块或合同。
- `scripts/systems/combat/` 与 `scripts/systems/battle/` 命名并存：实际战斗实现位于 `battle/`，`combat/` 目前只有占位。后续应避免把新战斗逻辑误放到占位目录。
- 生成内容合同仍在演化：`TileSceneCompiler` 已经输出很多运行时字段，但这些字段与手写 location 的共同 schema 还值得继续固化。
- action type 命名有两层表达：`ActionSystem.create_action()` 使用类似 `MoveAction` 的类名字符串，而交互候选和 overlay 中也存在 `pickup`、`talk`、`scene_transition` 等较语义化类型。后续可以观察是否需要统一映射层。
- 部分 UI、场景表现和系统摘要互相依赖：例如战斗预览、交互 overlay、debug panel 都依赖系统摘要结构。摘要结构变化时要同步检查 UI 和测试。
- 编码和文档历史可能不完全一致：部分早期文档在当前终端中显示为乱码，后续维护时应注意统一 UTF-8 文档编码。

这些不是必须立刻重构的问题，但值得在新增功能时保持警觉。

## 4. 后续增量开发时值得优先检查的地方

新增玩法能力前，建议优先检查：

- 是否已有 Autoload 入口或系统目录可以承接能力。
- 是否需要新增或扩展 `data/` 下的 JSON 定义。
- 是否应该通过 `ActionSystem` 进入，而不是直接从 UI 或场景改世界。
- 是否需要 `ActionResult.world_changes` 支撑反馈、测试和表现。
- 是否需要接入 `SaveManager` 和各系统 `get_save_state()`。
- 是否影响 `LocationRoot` 的交互候选、overlay、scene transition 或 facility 逻辑。
- 是否影响 `DefinitionLoader` 对手写 location 和生成 location 的共同解析。
- 是否需要新增 smoke test 或扩展现有 v60-v65 测试。

对聚落生成相关改动，建议额外检查：

- `data/settlement_policies/`
- `SettlementPolicy`
- `SettlementGenerationSession`
- 具体 agent 的 proposal
- `ProposalResolver`
- `SettlementBlueprint`
- `TileSceneCompiler`
- generated interiors、building contracts、schedule targets、gameplay hooks
- `scripts/tests/v63`、`v64`、`v65` 相关 smoke tests

## 5. 当前仍在演化、不宜过早固定的地方

目前代码中有些边界仍在演化，不建议过早写死为最终架构：

- NPC 自主、日程、活动和玩家交互打断的优先级。
- 战斗行为是否完全归入通用 `GameAction`。
- 手写 location 与生成 location 的完整共同 schema。
- 生成聚落中建筑、室内、facility、schedule target 和 NPC 内容的最终合同。
- UI 对系统摘要的依赖形态。
- `data/economy/`、`data/generation/`、`data/world/` 等预留目录的实际职责。
- AI 增强层的接入位置和数据边界。

当前项目处于原型到框架之间的阶段。保持适度弹性比过早固化所有边界更重要，但这种弹性应建立在当前已有系统入口之上。

## 6. 未来 AI 接入时需要观察的边界

AI 接入更适合从内容层和候选层开始，而不是替代现有规则层。当前比较合适的进入点包括：

- 对话文本变体和 NPC 表达。
- 地点、建筑、公告、传闻和摘要描述。
- 任务草案和任务文本候选。
- NPC 意图候选或日程活动解释。
- 聚落生成结果的风味包装。
- 名称、短描述、候选计划等可被规则系统校验的内容。

需要特别注意的边界：

- AI 可以生成候选，但最终能否执行应由 `ActionSystem`、具体玩法系统和数据 schema 决定。
- AI 文本不应直接改写 `GameState` 或绕过 `SaveManager`。
- 生成内容如果要持久化，应有明确 JSON 结构或保存状态。
- AI 输出需要可调试、可回放、可审计，尤其是任务、关系和聚落生成相关内容。
- 如果 AI 为 NPC 提供意图，也应先进入候选列表，再由 NPC 日程、自主系统或行动规则做确定性筛选。

目前看来，Aftertale 已经有足够多的确定性规则入口，未来 AI 的价值更可能体现在“让已有规则系统产生更丰富的表达和候选”，而不是替代这些规则系统。
