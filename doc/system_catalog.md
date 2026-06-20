# Aftertale 当前系统目录清单

本文档按目录总结当前系统职责、主要文件、相关系统、当前状态和可能扩展方向。它以当前代码事实为主；无法从文件名和代码中完全确认的职责会明确标注。

## scripts/core/

当前职责：项目核心运行入口、全局状态、场景加载、定义加载和输入管理。

主要文件或类型：

- `main.gd`：启动流程、UI 绑定、新游戏、存档读档信号、smoke test 启动入口。
- `game_state.gd`：session、模式、玩家 id、世界事实、场景上下文和角色运行时状态。
- `scene_loader.gd`：场景加载、location 切换、入口、返回 location、pending context、相机缩放状态。
- `definition_loader.gd`：JSON 加载、定义缓存、location materialize、生成型 location 和 generated interior 注册。
- `input_manager.gd`：输入动作注册和输入信号分发。

相关系统：所有 Autoload、`LocationRoot`、UI、存档、测试启动流程。

当前状态：核心骨架已经成形，并承担全局系统协作入口。

后续可能扩展方向：更明确的启动状态机、存档恢复流程细化、数据索引或校验工具、更稳定的 scene context 合同。

## scripts/systems/actions/

当前职责：统一表达玩家或 NPC 行为，提供 check / execute / result 的行动规则结构。

主要文件或类型：

- `action_system.gd`：创建 action、提交 action、发出 action 信号、记录历史。
- `game_action.gd`：行动基类。
- `action_result.gd`：行动结果和 world changes。
- 具体 action：移动、对话、检查、拾取、使用物品、使用技能、装备、卸装、种植、浇水、收获、攻击、交易、休息、制作、接任务、招募同伴、unsupported。

相关系统：`LocationRoot`、`CharacterEntity`、`CropSystem`、`CraftSystem`、`BusinessSystem`、`BattleSystem`、`DialogueRunner`、`QuestSystem`、`PartySystem`。

当前状态：已成为交互和玩法系统之间的重要中介。部分 action 仍是早期或桥接性质，例如 `AttackAction` 当前继承 `UnsupportedAction`，战斗启动主要由场景交互进入 `BattleSystem`。

后续可能扩展方向：统一 action type 命名、补齐 NPC 行动复用、强化失败原因和 world changes 的结构化合同。

## scripts/systems/battle/

当前职责：战术战斗状态、单位、技能执行、格子状态、元素反应、状态效果、AI 决策和战斗摘要。

主要文件或类型：

- `battle_system.gd`：Autoload 战斗入口，启动战斗、移动当前单位、攻击、使用技能、战术预览、战斗摘要。
- `battle_state.gd`：战斗状态、当前单位、单位查询、格子状态、回合顺序和摘要。
- `battle_unit_state.gd`：战斗单位、状态效果、冷却、防御和摘要。
- `battle_tile_state.gd`：战斗格子状态。
- `battle_effect_resolver.gd`：技能和战斗效果结算。
- `battle_element_reaction_system.gd`：元素反应。
- `battle_tile_unit_effect_system.gd`：格子状态对单位的影响。
- `battle_ai_planner.gd`、`battle_ai_profile_registry.gd`：AI profile 与战斗决策。

相关系统：`SkillSystem`、`LocationRoot`、`BattleGridOverlay`、`CharacterEntity`、`PartySystem`、`ActionSystem`。

当前状态：战斗系统已经具备较完整的战术基础，包括单位、技能、格子、效果和 AI。表现层通过 overlay 和角色战斗表现接入场景。

后续可能扩展方向：战斗行动与通用 `GameAction` 的进一步统一、更多敌人 AI 策略、战斗存档与重放、UI 反馈细化。

## scripts/systems/business/

当前职责：商店、货币、买卖报价和交易执行。

主要文件或类型：

- `business_system.gd`：商店加载、货币增减、市场摘要、买卖报价、交易失败原因和交易执行。

相关系统：`TradeAction`、`Inventory`、`RelationSystem`、`data/shops/`、UI facility 面板。

当前状态：已有基础交易闭环，并能与关系系统的价格修正协作。

后续可能扩展方向：经济数据从 `data/economy/` 扩展、商店库存刷新、价格曲线、阵营或地点经济差异。

## scripts/systems/characters/

当前职责：角色运行时实体、角色外观解析和渲染。

主要文件或类型：

- `character_entity.gd`：角色节点、格子位置、朝向、背包、装备、属性、运行时状态、战斗表现。
- `character_appearance_resolver.gd`：从角色定义和外观数据解析外观。
- `character_appearance_renderer.gd`：渲染角色外观。

相关系统：`LocationRoot`、`LocationGrid`、`Inventory`、`EquipmentSlots`、`PartySystem`、`BattleSystem`、`NpcScheduleSystem`、`data/characters/`、`data/appearance/`。

当前状态：基础角色实体已经承担探索、队伍、战斗和 UI 摘要所需的数据。

后续可能扩展方向：更稳定的角色属性模型、外观资源标准化、NPC 状态与日程行为的边界细化。

## scripts/systems/combat/

当前职责：当前代码中未承载实际战斗实现。

主要文件或类型：

- `.gitkeep`

相关系统：实际战斗系统位于 `scripts/systems/battle/`。

当前状态：占位目录。当前代码中无法确认有独立 combat 子系统。

后续可能扩展方向：如果保留该目录，需要明确它与 `battle/` 的区别；否则后续可以继续把战斗能力集中在 `battle/`。

## scripts/systems/crafting/

当前职责：配方、材料检查和制作执行。

主要文件或类型：

- `craft_system.gd`：配方加载、已知配方、配方摘要、失败原因、执行制作、材料与产物详情。

相关系统：`CraftAction`、`Inventory`、`data/recipes/`、`data/items/`、UI facility 制作视图。

当前状态：基础制作系统已经可用，并与 action 和 UI 形成闭环。

后续可能扩展方向：制作台类型、技能或设施限制、批量制作、配方解锁。

## scripts/systems/crops/

当前职责：种植、浇水、生长、收获和作物表现标记。

主要文件或类型：

- `crop_system.gd`：作物定义加载、地块作物状态、种植 / 浇水 / 收获检查与执行、保存状态。
- `crop_marker.gd`：场景中的作物表现节点。

相关系统：`PlantAction`、`WaterAction`、`HarvestAction`、`LocationRoot`、`LocationGrid`、`TimeManager`、`Inventory`、`data/crops/`。

当前状态：基础农作系统已经进入运行闭环，场景会响应作物变化刷新 marker。

后续可能扩展方向：更多成长阶段、季节天气、土地状态、作物品质、批量操作。

## scripts/systems/dialogues/

当前职责：对话启动、对话状态和对话摘要。

主要文件或类型：

- `dialogue_runner.gd`：根据 actor、speaker 和 dialogue source 启动对话，维护当前状态和最近摘要。

相关系统：`TalkAction`、`CharacterEntity`、`QuestSystem`、UI 对话面板、`data/dialogues/`。

当前状态：基础对话入口已经存在，当前内容以调试对话为主。

后续可能扩展方向：分支条件、任务触发、关系影响、AI 文本变体接入。

## scripts/systems/items/

当前职责：物品堆叠、背包和装备槽。

主要文件或类型：

- `item_stack.gd`：单个物品堆叠。
- `inventory.gd`：添加、移除、查询、摘要和运行时状态。
- `equipment_slots.gd`：装备槽、默认装备、玩家覆盖装备、属性加成和摘要。

相关系统：`CharacterEntity`、`UseItemAction`、`EquipItemAction`、`UnequipItemAction`、`CraftSystem`、`BusinessSystem`、`CropSystem`、`data/items/`。

当前状态：物品和装备基础已经支撑背包、制作、交易、种植和角色 UI。

后续可能扩展方向：物品类型系统、耐久度、稀有度、装备限制、消耗品效果。

## scripts/systems/party/

当前职责：队伍成员、同伴、队列顺序、跟随偏移和战斗成员选择。

主要文件或类型：

- `party_system.gd`：队伍初始化、成员增删、同伴列表、队伍摘要、战斗成员和保存状态。

相关系统：`RecruitCompanionAction`、`LocationRoot`、`CharacterEntity`、`BattleSystem`、UI 队伍 / 角色面板。

当前状态：队伍系统已经具备探索跟随和战斗成员基础。

后续可能扩展方向：队伍指令、成员 AI、队形规则、同伴任务和关系联动。

## scripts/systems/quests/

当前职责：任务定义、任务状态、目标进度和保存状态。

主要文件或类型：

- `quest_system.gd`：任务加载、接取、进度、摘要、保存状态。
- `quest_state.gd`：单个任务状态和目标计数。

相关系统：`AcceptQuestAction`、`DialogueRunner`、UI 任务面板、`data/quests/`。

当前状态：基础任务系统已经存在，当前任务内容以调试任务为主。

后续可能扩展方向：更多目标类型、对话触发、关系触发、AI 任务草案转结构化任务。

## scripts/systems/relations/

当前职责：角色关系、阵营关系、关系摘要、近期事件和交易价格修正。

主要文件或类型：

- `relation_system.gd`：读取初始关系，查询角色 / 阵营 stance，生成摘要，保存状态，计算交易价格修正。

相关系统：`BusinessSystem`、`DialogueRunner`、`QuestSystem`、NPC 系统、`data/relations/`、`data/factions/`。

当前状态：关系系统已有基础数据和查询入口。

后续可能扩展方向：关系事件来源统一、声望、阵营冲突、关系对 NPC 行为和对话的影响。

## scripts/systems/save/

当前职责：保存和读取游戏状态。

主要文件或类型：

- `save_manager.gd`：`save_game`、`load_game`，协调各系统保存状态。

相关系统：`GameState`、`SceneLoader`、`TimeManager`、`CropSystem`、`QuestSystem`、`PartySystem`、`RelationSystem`、`BusinessSystem`、`NpcScheduleSystem`。

当前状态：基础存档入口已经存在。

后续可能扩展方向：版本迁移、多个存档槽、生成内容持久化审计、战斗中存档策略。

v67.2 addendum:

- `save_manager.gd` also owns generated-content context: `active_save_path`, `active_save_slot_id`, `active_world_id`, and `generated_settlements`.
- `load_game()` restores active save/world context and the generated settlement index before scene load, then clears generated runtime caches.
- New game and slot/world changes clear generated runtime caches so resolved generated locations and `user://` generated JSON entries do not leak across save slots.

## scripts/systems/scenes/

当前职责：location 运行时、格子地图、对象、场景表现、建筑渲染、调试渲染、战斗与交互 overlay。

主要文件或类型：

- `location_root.gd`：当前 location 运行入口。
- `location_grid.gd`：格子、地形、对象、角色、入口、出口和锚点索引。
- `location_object.gd`：可交互对象和 facility / transition 数据。
- `scene_component_library.gd`：场景组件辅助。
- `building_renderer.gd`：建筑表现。
- `debug_tile_renderer.gd`：调试 tile 渲染。
- `battle_grid_overlay.gd`：战斗网格 overlay。
- `interaction_target_overlay.gd`：交互目标 overlay。
- `village_road_generator.gd`：较早的村路生成器。

相关系统：`SceneLoader`、`DefinitionLoader`、`ActionSystem`、`BattleSystem`、`CropSystem`、`NpcScheduleSystem`、`Settlement` 编译输出。

当前状态：场景运行结构已经是项目核心协作层之一。

后续可能扩展方向：更稳定的 interaction candidate 合同、场景表现与规则数据拆分、手写和生成 location 的共同校验。

## scripts/systems/schedules/

当前职责：NPC 日程、可见移动、离屏状态、活动和轻量自主行为。

主要文件或类型：

- `npc_schedule_system.gd`：日程状态、active entry、离屏角色状态、location root 注册和保存状态。
- `npc_movement_agent.gd`：根据日程请求移动。
- `npc_activity_agent.gd`：NPC 活动处理。
- `npc_autonomy_agent.gd`：轻量自主行为。

相关系统：`TimeManager`、`LocationRoot`、`CharacterEntity`、生成聚落 schedule targets。

当前状态：NPC 日程和可见行为已有基础，仍在演化。

后续可能扩展方向：日程优先级、玩家打断、室内外迁移、AI 意图候选与规则校验。

v67.3 addendum:

- `NpcScheduleSystem` still owns the v56-v59 offscreen settlement model; generated NPCs outside the current location are settled by active schedule/offscreen state rather than simulated through full cross-scene routes.
- Generated schedule entries now carry transition metadata that `LocationRoot` can consume through `transition_anchor_by_location`, while retaining the base `location_id + anchor_id` contract.

## scripts/systems/settlements/

当前职责：程序生成聚落，从 policy 和 context 到 blueprint，再编译成可运行 location。

主要文件或类型：

- `settlement_policy.gd`、`settlement_context.gd`：生成输入和上下文。
- `settlement_generation_session.gd`：组织生成流程。
- `settlement_blueprint.gd`、`settlement_road_graph.gd`、`settlement_demand_ledger.gd`、`feature_map_store.gd`：蓝图、道路、需求和特征图。
- `settlement_agent.gd`、`settlement_agent_spec.gd` 与各类 agent：提出生成 proposal。
- `plan_proposal.gd`、`proposal_resolver.gd`：proposal 表达与冲突处理。
- `settlement_evaluator.gd`、`generation_trace.gd`：评估与追踪。
- `tile_scene_compiler.gd`：编译道路、地块、建筑、入口、对象、室内、building contracts、schedule targets 和 gameplay hooks。
- `generated_settlement_store.gd`：读写 generated settlement snapshot，管理 baseline 路径、版本字段、generated character definitions，并登记 SaveManager index。
- `population_planner.gd`：根据 building contracts、generated interiors、schedule targets 和 policy 生成 NPC definitions、spawn rows、role assignments 和人口摘要。
- `schedule_planner.gd`：将 NPC role 与 home/work/social/rest target 转换成 `NpcScheduleSystem` 可消费的 schedule entries。
- `settlement_debug_view.gd`：生成调试视图。

相关系统：`DefinitionLoader`、`LocationRoot`、`LocationGrid`、`LocationObject`、`NpcScheduleSystem`、`data/settlement_policies/`、`data/locations/`。

当前状态：程序生成链路已经比较完整。v67 后，带持久化标记的 generated settlement 会被固化为 snapshot，并可包含居民、日程和可复访读取的 baseline。

后续可能扩展方向：生成结果校验、内容合同稳定、更多 policy 类型、手写内容与生成内容融合、长期历史演化。

v67.2 addendum:

- `generated_settlement_store.gd` now reads snapshot paths from the `SaveManager` generated settlement index before falling back to the expected path under the active slot/world root.
- Generated baseline files live under `user://saves/<slot_id>/worlds/<world_id>/generated/`.
- Snapshot identity distinguishes `settlement_template_id`, `settlement_instance_id`, `snapshot_id`, and `exterior_location_id`.
- Formal generated IDs are namespaced before snapshot write: buildings, source/parent building refs, interiors, shops, objects, schedule targets, NPCs, schedule entries, and role assignments.

v67.3 addendum:

- `tile_scene_compiler.gd` emits schedule target metadata for `target_type`, `capacity`, `target_key`, concrete `grid_position`, public/social `activity_cells`, generated interior entry/exit targets, and exterior building entrance/transition targets.
- Public plot hooks now also expose `public` schedule targets. They keep `source_plot_id` and fill the legacy `source_building_id` field so generated namespace and old target contracts remain stable.
- `population_planner.gd` performs capacity-aware target claims for home/work/social/rest. Single-capacity targets are not shared across NPCs; multi-capacity public/social targets use concrete activity-cell slots.
- `schedule_planner.gd` adds source/departure/arrival/target transition metadata without replacing schedule resolution by `location_id + anchor_id`.
- Generated NPC definitions now include concrete `appearance.display_mode = "map_sprite"` data using `res://assets/art/characters/map_sprites/npc_guard_001.png`.
- `generated_settlement_store.gd` namespaces public plot scoped schedule target IDs in addition to building/interior/shop/object references.

## scripts/systems/skills/

当前职责：技能定义加载、目标范围、目标选择规则、影响单位和技能失败原因。

主要文件或类型：

- `skill_system.gd`：技能查询、单位技能摘要、范围格、目标格、面积格、影响单位、target policy 和 path blocking。

相关系统：`BattleSystem`、`UseSkillAction`、`BattleEffectResolver`、`data/skills/`。

当前状态：技能系统已经服务于战斗技能和 UI 预览。

后续可能扩展方向：非战斗技能、更多目标策略、技能成长、AI 技能评估。

## scripts/systems/time/

当前职责：世界时间、时段、暂停、推进和保存状态。

主要文件或类型：

- `time_manager.gd`：时间标签、绝对分钟、日内分钟、时段、暂停、保存状态。

相关系统：`NpcScheduleSystem`、`CropSystem`、`RestAction`、UI、存档。

当前状态：时间系统已经作为作物、NPC 日程、休息和世界推进的基础。

后续可能扩展方向：日期、季节、天气、时间事件队列。

## scripts/tests/

当前职责：阶段性 smoke tests 和工具场景测试。

主要文件或类型：

- `v55_ui_smoke.gd`、`v60_1_road_skeleton_smoke.gd`、`v61_settlement_planning_smoke.gd`、`v62_general_settlement_generation_smoke.gd`、`v63_settlement_scene_compiler_smoke.gd`、`v64_generated_interiors_contract_smoke.gd`、`v64_policy_playable_settlement_smoke.gd`、`v65_unified_interaction_resolver_smoke.gd`。
- `v67_persistent_generated_settlement_population_smoke.gd`：验证 generated settlement snapshot、generated NPC definitions、spawn rows、schedule target 解析、二次读取和 SaveManager index。
- `v67_3_generated_npc_schedule_appearance_integrity_smoke.gd`：验证 generated NPC map_sprite、role target claims、single-capacity avoidance、schedule occupancy、multi-capacity public/social slots、transition metadata、entry/exit/door targets、LocationRoot spawn anti-overlap 和二次加载稳定性。
- 对应 `.tscn` 和 `.uid` 文件。

相关系统：`main.gd` smoke flag 流程、settlement、scene compiler、interaction resolver、UI。

当前状态：已经形成按阶段验证关键系统的测试基础。

后续可能扩展方向：更多自动化回归、数据定义校验、存档读档测试、战斗和 NPC 行为测试。

v67.2 addendum:

- `v67_2_generated_settlement_persistence_integrity_smoke.gd` verifies multi-slot generated settlement isolation, generated `user://` character definition reads, generated runtime cache switching, `load_game()` generated context restoration, and formal generated ID namespace integrity.

v67.3 addendum:

- `v67_3_generated_npc_schedule_appearance_integrity_smoke.gd` verifies generated NPC schedule and appearance integrity and should be run with the v67.2, v67, and v65 smoke regressions after generated settlement changes.

## data/

当前职责：JSON 数据定义和生成输入。

主要数据类型：

- 角色、外观、地点、物品、技能、作物、配方、商店、任务、对话、战斗 AI、阵营、关系、聚落 policy。
- `economy`、`generation`、`world` 当前主要是预留或占位目录。

相关系统：`DefinitionLoader` 和各 Autoload 玩法系统。

当前状态：项目已经从少量调试数据发展出覆盖多系统的定义目录。

后续可能扩展方向：数据 schema、定义校验、内容索引、手写和生成内容的统一合同。

## doc/

当前职责：阶段文档、项目方向、结构索引和当前架构总结。

主要文件或类型：

- `phase_*.md`：各阶段功能记录。
- `development_todo_progress.md`：开发进度记录。
- `project_direction_notes.md`：项目方向说明。
- `project_structure.md`：项目目录和文档索引入口。
- `project_current_architecture.md`、`system_catalog.md`、`architecture_observations.md`：v66 新增当前架构总结文档。

相关系统：所有开发阶段和后续维护。

当前状态：阶段文档丰富，v66 后新增更偏“当前整体结构”的入口文档。

后续可能扩展方向：保持阶段文档与当前架构文档同步，增加数据合同和运行流程图。
