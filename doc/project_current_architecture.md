# Aftertale 当前项目架构总结

本文档总结 Aftertale 在当前代码事实中已经形成的项目结构、系统层次、数据目录、运行流程和模块关系。它描述的是当前状态，不把尚未完成或仍在演化的方向写成已经完成的功能。

## 1. 项目当前定位

Aftertale 当前是一个 Godot 2D 俯视角 RPG 项目。项目重点已经从单一 demo 逐步扩展为多系统 RPG 框架：有全局运行骨架、JSON 数据定义、location / scene / object / grid 场景结构、玩家输入与交互解析、ActionSystem 行动规则层，以及物品、技能、战斗、作物、制作、商店、任务、对话、队伍、关系、NPC 日程、时间、存档和程序生成聚落等基础系统。

当前项目更接近“规则层和玩法框架已经初步成形”的阶段。AI 是后续增强方向，适合进入 NPC 表达、叙事文本、任务草案、地点描述、NPC 意图候选、聚落风味等内容层能力；当前代码中不应把 AI 视为已经接管规则层或核心运行层的能力。

## 2. 当前系统总览

项目启动入口由 `project.godot` 指向 `res://scenes/boot/main.tscn`。`scripts/core/main.gd` 在启动后配置 `SceneLoader` 的世界根节点，绑定 UI 与全局管理器，初始化新游戏，并加载当前默认场景 `res://scenes/locations/generated_settlement.tscn`。

`project.godot` 中的 Autoload 构成当前项目的全局运行骨架：

```text
GameState
SceneLoader
DefinitionLoader
TimeManager
InputManager
CropSystem
SkillSystem
ActionSystem
CraftSystem
BusinessSystem
DialogueRunner
QuestSystem
PartySystem
NpcScheduleSystem
RelationSystem
BattleSystem
SaveManager
```

这些系统大致分为几类：核心运行与状态、定义加载、输入与场景切换、行动规则、玩法规则、角色社会系统、战斗系统、时间推进、存档和调试测试支撑。

## 3. 当前 9 层项目结构

### 3.1 核心运行层

核心运行层主要位于 `scripts/core/`。

代表文件包括：

- `main.gd`：启动场景脚本，配置 `SceneLoader`，绑定输入、UI、存档、标题菜单和新游戏流程。
- `game_state.gd`：维护当前 session、玩家 id、当前模式、场景上下文、世界事实和角色运行时状态。
- `scene_loader.gd`：负责场景实例化、卸载、location 切换、入口 id、返回 location、pending context 和相机缩放状态。
- `definition_loader.gd`：负责 JSON 定义加载、缓存、location materialize、生成型 location 编译和 generated interior 注册。
- `input_manager.gd`：注册默认输入动作，发出移动、交互、休息、UI 开关、存档读档、相机控制等信号。

当前代码中，核心运行层已经是全局系统协作的入口。它不直接承载具体玩法规则，而是把输入、状态、场景、数据和系统入口连接起来。

### 3.2 数据定义层

数据定义层主要位于 `data/`。当前实际存在的数据目录包括：

- `data/appearance/`：角色外观部件定义。
- `data/battle/`：战斗 AI profile 等战斗相关定义。
- `data/characters/`：玩家、村民、守卫、训练假人等角色定义。
- `data/crops/`：作物定义。
- `data/dialogues/`：调试对话定义。
- `data/economy/`：当前为占位目录。
- `data/factions/`：玩家和中立阵营定义。
- `data/generation/`：当前为占位目录。
- `data/items/`：调试物品、种子、工具、装备、素材包等物品定义。
- `data/locations/`：手写 location、生成聚落 location、生成室内 location 定义。
- `data/quests/`：调试任务定义。
- `data/recipes/`：制作配方定义。
- `data/relations/`：初始关系定义。
- `data/settlement_policies/`：聚落生成 policy 定义。
- `data/shops/`：商店定义。
- `data/skills/`：基础攻击、调试技能、治疗、守护、强力攻击等技能定义。
- `data/world/`：当前为占位目录。

`DefinitionLoader` 是当前定义加载和定义访问的核心入口。它可以读取通用 JSON，也提供角色、物品、配方、商店、技能、作物、对话、任务、阵营、关系和 location 的加载方法。对 location，它还会根据 `generator.type` 将 `village_road`、`settlement_blueprint` 或 `settlement` 等生成型定义 materialize 为运行时 location 数据。

### 3.3 世界 / 场景 / 地图层

场景运行层主要位于 `scripts/systems/scenes/` 和 `scenes/locations/`。

代表系统包括：

- `LocationRoot`：当前 location 的运行时入口，读取 location 数据，创建 grid、对象、角色、作物标记、战斗 overlay、交互 overlay，并连接输入、行动结果、队伍、作物、战斗和 NPC 日程系统。
- `LocationGrid`：承载格子、地形、阻挡、入口、出口、锚点、对象和角色索引。
- `LocationObject`：表示 location 中的可交互或可表现对象，提供交互 action、transition、facility 等数据。
- `SceneComponentLibrary`、`BuildingRenderer`、`DebugTileRenderer`、`BattleGridOverlay`、`InteractionTargetOverlay`：提供场景组件、建筑表现、调试 tile 渲染、战斗格子表现和交互目标提示。
- `VillageRoadGenerator`：较早的村路生成器，当前与新的 settlement 生成链并存。

当前场景层已经支持手写 location 和生成型 location 共用运行结构。`scene transition`、interior / exterior、building entrance、return point 等概念已经通过 `LocationObject`、`SceneLoader` pending context 和 `DefinitionLoader` generated interior 注册进入当前场景运行结构。

### 3.4 行动规则层

行动规则层主要位于 `scripts/systems/actions/`。

核心结构包括：

- `ActionSystem`：统一接收 `GameAction`，执行 check / execute，记录最近结果和 action history，并发出请求、检查、成功、失败信号。
- `GameAction`：行动基类，承载 actor、target、context、check 和 execute 结构。
- `ActionResult`：行动结果结构，承载成功状态、反馈、目标和 world changes。

当前已存在的 action 包括 `MoveAction`、`TalkAction`、`InspectAction`、`PickUpAction`、`UseItemAction`、`UseSkillAction`、`EquipItemAction`、`UnequipItemAction`、`PlantAction`、`WaterAction`、`HarvestAction`、`AttackAction`、`TradeAction`、`RestAction`、`CraftAction`、`AcceptQuestAction`、`RecruitCompanionAction` 和 `UnsupportedAction`。

行动规则层是玩家或 NPC 行为进入玩法系统的关键结构。它不自己完成所有玩法，而是把行动检查和执行委托给对应系统，例如移动依赖场景 grid，种植依赖 `CropSystem`，交易依赖 `BusinessSystem`，制作依赖 `CraftSystem`，技能和攻击依赖战斗与技能系统。

### 3.5 角色 / NPC / 社会层

角色与社会层分散在 `scripts/systems/characters/`、`dialogues/`、`quests/`、`party/`、`relations/` 和 `schedules/`。

代表系统包括：

- `CharacterEntity`：运行时角色节点，承载角色 id、显示、位置、朝向、背包、装备、属性、战斗表现等。
- `CharacterAppearanceResolver`、`CharacterAppearanceRenderer`：角色外观解析与渲染辅助。
- `DialogueRunner`：根据对话定义启动和推进对话，保存当前对话状态和最近摘要。
- `QuestSystem`、`QuestState`：管理任务定义、任务状态、完成进度和保存状态。
- `PartySystem`：管理队伍成员、同伴、队列顺序、跟随偏移、战斗成员和队伍保存状态。
- `RelationSystem`：管理角色关系、阵营关系、关系摘要、近期事件和交易价格修正。
- `NpcScheduleSystem`、`NpcMovementAgent`、`NpcActivityAgent`、`NpcAutonomyAgent`：管理 NPC 日程、离屏状态、可见移动、活动与轻量自主行为。

当前代码中，角色社会层已经具备基础骨架，并与场景、行动、时间和 UI 协作。部分 NPC 自主与活动逻辑仍在演化，后续可以继续观察行为边界、调度优先级和与玩家交互打断的关系。

### 3.6 玩法系统层

玩法系统层主要位于 `scripts/systems/items/`、`crops/`、`crafting/`、`business/`、`skills/`、`battle/` 和 `time/`。

当前系统包括：

- `Inventory`、`ItemStack`、`EquipmentSlots`：提供背包、堆叠、装备槽和装备属性加成基础。
- `CropSystem`、`CropMarker`：管理种植、浇水、生长、收获、作物保存状态和场景标记。
- `CraftSystem`：加载配方，检查材料，执行制作，输出材料和产物摘要。
- `BusinessSystem`：管理货币、商店、买卖报价、交易失败原因和交易执行。
- `SkillSystem`：加载技能，计算技能目标、范围、路径阻挡、影响单位和失败原因。
- `BattleSystem`、`BattleState`、`BattleUnitState`、`BattleTileState`、`BattleEffectResolver`、`BattleElementReactionSystem`、`BattleTileUnitEffectSystem`、`BattleAiPlanner`、`BattleAiProfileRegistry`：管理战斗状态、单位、格子状态、技能效果、元素反应、AI 决策和战斗摘要。
- `TimeManager`：提供天数、分钟、时段、暂停、推进和保存状态。

当前 `scripts/systems/combat/` 目录只有 `.gitkeep`，实际战斗实现集中在 `scripts/systems/battle/`。

### 3.7 程序生成层

程序生成层主要位于 `scripts/systems/settlements/` 和 `data/settlement_policies/`。

当前链路已经不是简单随机摆放，而是 policy / context / session / agent / proposal / resolver / blueprint / compiler 的生成流程：

- `SettlementPolicy`：从 generator data 或 policy 数据中解析聚落类型、道路风格、密度、权重、地标和 gameplay hook 规则。
- `SettlementContext`：承载地图尺寸、入口、障碍、水体、世界点、seed 等生成上下文。
- `SettlementGenerationSession`：组织一次生成流程，初始化 feature map、blueprint、resolver、evaluator、trace、demand ledger 和 agents。
- `SettlementBlueprint`、`SettlementRoadGraph`、`SettlementDemandLedger`、`FeatureMapStore`：承载蓝图、道路分析、需求账本和特征图。
- `SettlementAgent` 与各类 agent：`CoreSeedAgent`、`RoadEndpointAgent`、`RoadBranchAgent`、`RoadReconnectAgent`、`GenericPlotAgent`、`PlotDifferentiationAgent`、`BuildingFootprintAgent`、`InvalidProposalAgent`、`InvalidConflictAgent` 等负责提出生成 proposal。
- `ProposalResolver`：处理候选 proposal、冲突和提交。
- `SettlementEvaluator`、`GenerationTrace`：记录评估与生成追踪。
- `TileSceneCompiler`：将 session result 编译为可被 `LocationRoot`、`LocationGrid`、`LocationObject` 理解的 location 数据，并生成道路、地块、建筑、入口、锚点、对象、室内 manifest、building contract、schedule target 和 gameplay hook。
- `GeneratedSettlementStore`：将带持久化标记的 generated settlement 固化为 snapshot，并在再次进入同一 `settlement_id` 时读取已有 baseline。
- `PopulationPlanner`、`SchedulePlanner`：根据 `building_contracts`、`generated_interiors` 和 `schedule_targets` 生成 NPC definitions、spawn rows、role assignments 和当前日程系统可消费的 schedule entries。
- `SettlementDebugView`：用于观察生成结果。

当前这条线已经覆盖道路、地块、建筑、室内、对象 hook、可玩 location、居民、日程入口、调试摘要等内容。生成聚落现在可以从一次性的编译结果升级为带 snapshot baseline 的世界实体；runtime 变化仍由存档和各玩法系统保存。

### 3.8 存档 / 调试 / 测试层

存档系统位于 `scripts/systems/save/save_manager.gd`，由 Autoload `SaveManager` 提供 `save_game` 和 `load_game`。它与 `GameState`、`TimeManager`、`CropSystem`、`QuestSystem`、`PartySystem`、`RelationSystem`、`BusinessSystem`、`NpcScheduleSystem` 等系统的 save state 协作。

调试和测试相关内容包括：

- `scripts/tests/`：v55、v60、v61、v62、v63、v64、v65 等 smoke tests，以及 tool scenes smoke。
- `scripts/tests/v67_persistent_generated_settlement_population_smoke.gd`：验证 persistent generated settlement snapshot、generated NPC definitions、spawn rows、schedule anchor 解析和二次加载稳定性。
- `scripts/debug/debug_panel.gd` 与 `scenes/ui/components/debug_panel.tscn`：运行时调试面板。
- `scenes/tools/settlement_debug_view.tscn` 和 `SettlementDebugView`：聚落生成调试视图。
- `DebugTileRenderer`、`BattleGridOverlay`、`InteractionTargetOverlay`：运行状态、战斗范围和交互候选的可视化辅助。
- `main.gd` 中根据 `data/run_v*_smoke.json` 标记文件启动对应 smoke test 的流程。

当前测试和调试层是项目持续扩展的重要护栏，尤其是聚落生成、室内合同、交互解析、生成居民和日程持久化相关 smoke tests 已经在多个阶段承担回归验证角色。v67 后需要区分 generated baseline 与 runtime save state：前者由 `GeneratedSettlementStore` 管理，后者仍由 `SaveManager` 和各系统 save state 管理。

### 3.9 未来 AI 增强层

AI 当前更适合作为内容增强层，而不是替代现有规则层。后续可能进入的位置包括：

- NPC 对话表达和变体文本。
- 叙事文本、地点描述、传闻、摘要、名称候选。
- 任务草案和任务文本候选。
- NPC 意图候选、活动解释和日程风味。
- 聚落生成结果的风味描述、公告、传闻和居民表达。
- 候选计划或候选行动的生成，但最终仍应由当前规则系统校验和执行。

当前代码事实中，AI 增强层还不是已完成运行系统。后续接入时需要清楚区分“候选内容生成”和“规则执行权”。

## 4. Autoload 系统总览

当前 Autoload 大致可以按职责理解：

- 运行状态：`GameState`
- 场景与数据：`SceneLoader`、`DefinitionLoader`
- 时间与输入：`TimeManager`、`InputManager`
- 行动规则：`ActionSystem`
- 玩法系统：`CropSystem`、`SkillSystem`、`CraftSystem`、`BusinessSystem`、`BattleSystem`
- 角色社会系统：`DialogueRunner`、`QuestSystem`、`PartySystem`、`NpcScheduleSystem`、`RelationSystem`
- 存档：`SaveManager`

这些 Autoload 使大多数运行系统拥有统一入口，但也意味着新增能力前应先确认是否已有系统入口、信号和保存状态，避免绕过既有规则链路。

## 5. 数据目录总览

当前 JSON 数据是角色、地点、物品、技能、作物、配方、商店、任务、对话、战斗 AI、关系、阵营和聚落 policy 的主要来源。`data/locations/` 中同时存在手写 location 和生成型 location。生成型 location 会经 `DefinitionLoader` 与 `TileSceneCompiler` materialize 后进入与手写 location 相同的运行结构。

需要特别注意的是，`data/economy/`、`data/generation/`、`data/world/` 当前主要是占位目录；文档中应把它们描述为已预留或早期结构，而不是已经有完整内容。

## 6. 核心运行流程

当前启动流程大致为：

1. Godot 根据 `project.godot` 加载 Autoload。
2. Godot 进入主场景 `scenes/boot/main.tscn`。
3. `scripts/core/main.gd` 的 `_ready()` 配置 `SceneLoader` 的 world root。
4. `main.gd` 检查是否存在 smoke test 标记文件；若存在则运行对应测试并退出。
5. 正常流程下，`main.gd` 连接输入、UI、存档和菜单信号。
6. `ui_root.bind_managers(...)` 将 UI 与全局管理器绑定。
7. `_start_new_game()` 初始化 `GameState`、`NpcScheduleSystem`、`PartySystem`、`TimeManager`。
8. `SceneLoader.load_location("res://scenes/locations/generated_settlement.tscn", "main_entrance")` 加载当前默认 location。
9. `LocationRoot` 读取 location 数据，建立 grid、对象、角色、作物、overlay 和 NPC agent，并注册到相关系统。

## 7. 玩家输入到世界反馈的大致流程

当前代码中，玩家输入到世界反馈可以概括为：

1. 玩家按键或鼠标输入进入 `InputManager`。
2. `InputManager` 将具体输入转换为信号，例如 `move_requested`、`primary_action_requested`、`rest_requested`、UI toggle、存档读档和相机控制。
3. 当前 `LocationRoot` 监听移动、交互、休息和相机信号。
4. 在探索模式下，`LocationRoot` 根据受控角色当前位置、面向格、脚下格、地图对象、NPC、地形、作物、facility、scene transition 等信息解析交互候选。
5. 对普通行动，`LocationRoot` 通过 `ActionSystem.create_action(...)` 创建对应 `GameAction`，并调用 `ActionSystem.submit(...)`。
6. `ActionSystem` 执行 `check()`，再执行 `execute()`，得到 `ActionResult`。
7. `ActionResult` 通过信号反馈给场景和 UI，可能改变 `GameState`、角色位置、物品、作物、任务、关系、战斗状态或场景显示。
8. 场景层刷新 interaction overlay、battle overlay、crop marker、角色表现、相机焦点和反馈提示。

战斗模式下，部分输入会绕过普通探索交互，进入 `BattleSystem` 的战术移动、攻击、技能目标选择和等待 / 逃离流程。

## 8. location / scene / object / action 的关系

当前代码中，这几个概念的协作关系比较清晰：

- `scene` 是 Godot 实例化的场景文件，例如 `scenes/locations/generated_settlement.tscn`。
- `location` 是 JSON 或生成器 materialize 后的地点定义，包含尺寸、地形、tiles、入口、出口、对象、角色、状态和生成摘要等。
- `LocationRoot` 是 scene 中承接 location 数据的运行时入口。
- `LocationGrid` 把 location 数据转为可查询的格子结构，并维护对象、角色、入口、出口和锚点索引。
- `LocationObject` 是 location 中对象的运行时节点，提供 inspect、pickup、facility、transition 等可交互信息。
- `ActionSystem` 和各类 `GameAction` 把玩家或 NPC 对 location / object / character 的意图转成可检查、可执行、可反馈的规则动作。

手写 location 和生成 location 最终都需要落到 `DefinitionLoader`、`SceneLoader`、`LocationRoot` 可以理解的数据与运行结构中，这是当前项目保持两类内容共用运行层的关键。

## 9. 玩法系统之间的大致关系

当前玩法系统大致围绕 `CharacterEntity`、`GameAction`、`ActionResult` 和 Autoload 系统协作：

- 物品和装备：角色持有 `Inventory` 与 `EquipmentSlots`，行动和 UI 通过它们读取背包与装备状态。
- 作物：`PlantAction`、`WaterAction`、`HarvestAction` 调用 `CropSystem`，`LocationRoot` 根据作物变化刷新 `CropMarker`。
- 制作：`CraftAction` 调用 `CraftSystem`，材料来自角色背包，产物回到背包。
- 商店：`TradeAction` 调用 `BusinessSystem`，关系系统可以影响价格修正。
- 技能和战斗：`SkillSystem` 负责技能定义、范围和目标规则，`BattleSystem` 负责战斗状态、单位轮次、移动、攻击、技能执行和 AI 决策。
- 对话和任务：`TalkAction` 进入 `DialogueRunner`，任务接取和进度由 `QuestSystem` 与 `QuestState` 维护。
- 队伍和关系：`PartySystem` 负责队伍成员、跟随与战斗成员选择，`RelationSystem` 负责角色与阵营关系。
- 日程和时间：`TimeManager` 提供时间基础，`NpcScheduleSystem` 根据时间管理 NPC 可见与离屏状态。

这些系统当前已经形成基础闭环，但部分边界仍会随着玩法推进继续调整。

## 10. 程序生成系统在项目中的位置

程序生成系统当前位于数据定义层与场景运行层之间。`data/settlement_policies/` 和 `data/locations/` 的 generator 配置是输入，`SettlementGenerationSession` 组织生成，`TileSceneCompiler` 输出可运行 location 数据。输出内容不只是视觉地图，还包括 entrances、anchors、objects、generated interiors、building contracts、schedule targets 和 gameplay hooks。

这意味着生成聚落并不是独立于主游戏之外的工具结果，而是在逐步汇入 `DefinitionLoader`、`SceneLoader`、`LocationRoot`、`LocationGrid`、`LocationObject` 和 NPC 日程系统共同理解的运行结构。

## 11. 存档、测试和调试代码的位置

`SaveManager` 是当前存档入口。各系统通过 `get_save_state()` 或对应恢复接口参与保存与读取。当前文档范围没有修改存档代码，但从结构上看，新增可持久化玩法时应优先检查是否需要接入 `SaveManager`、`GameState` 和对应系统的保存状态。

`scripts/tests/` 中的 smoke tests 是阶段性验证入口。`main.gd` 会根据 `data/run_v*_smoke.json` 标记文件选择运行相关测试。聚落生成、场景编译、生成室内合同、policy playable hooks、统一交互解析等能力都有对应 smoke tests。

调试表现散落在 debug panel、overlay、tile renderer、settlement debug view 和 tool scenes 中。它们当前主要用于观察运行状态、生成结果、交互候选和战斗网格。

## 12. v67.2 生成聚落持久化一致性

v67.2 后，generated settlement baseline 不再依赖从最近存档路径猜测 slot。`SaveManager` 显式维护 `active_save_path`、`active_save_slot_id`、`active_world_id` 和 `generated_settlements`。`GeneratedSettlementStore` 通过这些字段确定正式生成根目录，并优先使用 save index 中记录的 snapshot path 读取 baseline。

当前生成 baseline 的正式路径形态为：

```text
user://saves/<slot_id>/worlds/<world_id>/generated/settlements/<settlement_instance_id>.json
user://saves/<slot_id>/worlds/<world_id>/generated/characters/<npc_id>.json
```

`load_game()` 的顺序已经调整为先读取存档、设置 active save/world context、恢复 generated settlement index、清理 generated runtime cache，再恢复系统状态和加载保存的场景。新游戏、slot/world 切换和 index 恢复都会清理 `DefinitionLoader` 的 generated runtime cache，避免不同存档槽之间复用 resolved location 或 `user://` generated JSON 缓存。

生成聚落 snapshot 中现在区分 `settlement_template_id`、`settlement_instance_id`、`snapshot_id` 和 `exterior_location_id`。building、interior、shop、object、NPC、schedule target、schedule entry、role assignment 等正式生成 ID 在写入 snapshot 前会进入 settlement namespace；location 内部 anchor 仍保持局部 ID，并继续通过 `location_id + anchor_id` 解析。

新增 `scripts/tests/v67_2_generated_settlement_persistence_integrity_smoke.gd` 覆盖多 slot 隔离、cache switch、`load_game()` 上下文恢复、generated `user://` definition 读取和生成 ID 命名空间完整性。

## 13. 未来 AI 增强层的当前位置

当前项目已经有较多确定性规则系统和数据入口，因此 AI 后续更适合作为候选内容、表达文本和风味生成层接入。比较自然的边界是：

- AI 生成候选文本或候选意图。
- 现有数据结构、规则系统和 action check 决定候选是否可用。
- 现有系统执行最终世界变化，并通过 `ActionResult`、`GameState`、`LocationRoot` 和 UI 反馈。

后续接入 AI 时，建议优先观察内容层边界、可回放性、存档稳定性、调试可解释性，以及 AI 候选内容与当前 JSON 定义和规则系统之间的转换接口。
