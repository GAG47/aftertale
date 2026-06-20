# Phase 67: Persistent Generated Settlement Population

中文目标：生成聚落持久化与居民日程接入。

本轮把当前生成器产出的聚落，从一次性的编译结果，升级成带建筑语义、室内、居民、日程、存储索引、可复访读取的正式世界实体。

## 目标

v67 的完整数据流是：

```text
settlement_id / world context / policy / seed
↓
TileSceneCompiler 生成 exterior、buildings、interiors、objects、anchors、schedule_targets
↓
GeneratedSettlementStore 固化 generated settlement baseline
↓
PopulationPlanner 根据 building_contracts / generated_interiors / schedule_targets / policy 生成 NPC definitions
↓
SchedulePlanner 根据 NPC role + home/work/social/service targets 生成 schedule
↓
NPC spawn rows 注入相关 exterior / interior locations
↓
DefinitionLoader / SceneLoader / LocationRoot 读取 generated locations
↓
NpcScheduleSystem 按 location_id + anchor_id 解析日程
↓
再次进入同一 settlement_id 时读取 snapshot，得到同一个聚落、建筑、室内、NPC 和日程
```

## 当前已有基础

- `TileSceneCompiler` 已经生成 `generated_interiors`、`building_contracts`、室内 anchors、facility objects 和 `schedule_targets`。
- `DefinitionLoader` 已经能 materialize generated settlement，并能注册 generated interiors。
- `LocationRoot` 已经根据当前 location 的 `characters` 列表、active schedule entry 和 offscreen state 决定 NPC 是否出现。
- `CharacterEntity` 已经支持从 definition 或 spawn data 读取 `schedule`。
- `NpcScheduleSystem` 已经按 `location_id + anchor_id` 解析 schedule target，并保存 offscreen state。
- `SaveManager` 已经有版本化存档结构，适合记录 generated settlement index。

## Snapshot 结构

`GeneratedSettlementStore` 写入的 snapshot 包含：

```text
schema_version
generator_version
settlement_id
policy_id
seed
exterior_location_id
locations
generated_interiors
building_contracts
schedule_targets
npc_definitions
npc_spawn_rows_by_location
npc_role_assignments
population_summary
created_at_game_time
history
```

`locations` 当前保存 exterior location 数据。`generated_interiors` 保存 concrete interior manifests。`npc_spawn_rows_by_location` 按 location id 记录该 location 可能出现的生成 NPC。

## GeneratedSettlementStore

新增文件：`scripts/systems/settlements/generated_settlement_store.gd`

职责：

- 管理 generated settlement baseline 的读写。
- 管理 snapshot 路径、character definition 路径和 version 字段。
- 在第一次生成时调用 `TileSceneCompiler`、`PopulationPlanner`。
- 写入 generated NPC character JSON。
- 将 snapshot 信息登记到 `SaveManager` 的 generated settlement index。
- 在再次进入同一 `settlement_id` 时直接读取已有 snapshot。

当前存储路径：

```text
user://saves/<slot_id>/generated/settlements/<settlement_id>.json
user://saves/<slot_id>/generated/characters/<npc_id>.json
```

当前默认 slot 来自 `SaveManager.get_current_slot_id()`；如果没有可用上下文，使用 `slot_1`。

## PopulationPlanner

新增文件：`scripts/systems/settlements/population_planner.gd`

职责：

- 读取 compiled location 中的 `building_contracts`、`schedule_targets` 和生成摘要。
- 根据建筑用途生成规则 NPC。
- 生成 `npc_definitions`、`npc_role_assignments`、`npc_spawn_rows_by_location` 和 `population_summary`。
- 将 NPC 只注入其日程会涉及的 location。

当前规则会根据 residential、commercial、production、public 等建筑生成 resident、merchant/shopkeeper、worker、traveler 等基础居民。若角色缺少某类目标，会使用同类 fallback target，并把未解析情况记录到 `population_summary.unresolved_targets`。

## SchedulePlanner

新增文件：`scripts/systems/settlements/schedule_planner.gd`

职责：

- 将 NPC role 和 home/work/social/rest target 转换成当前 `NpcScheduleSystem` 可消费的 schedule entry。
- 每条 schedule entry 使用 `location_id + anchor_id` 定位，不直接依赖写死坐标。
- schedule entry 包含 `start`、`end`、`location_id`、`anchor_id`、`facing`、`activity_type`、`activity`、`movement`。

## ID Namespace

v67 中 generated settlement 的正式实体 ID 使用 settlement namespace。

示例：

```text
generated_settlement__exterior
generated_settlement__building_00
generated_settlement__npc_merchant_001
generated_settlement__npc_worker_002
```

anchor 仍保持 location 内局部 ID，例如 `bed`、`counter`、`workstation`、`exterior_door_building_00`。日程解析依赖 `location_id + anchor_id`，因此局部 anchor ID 不需要全局化。

## DefinitionLoader 接入

`DefinitionLoader` 新增 persistent generated settlement 分支。带有以下字段的 generated location 会走 snapshot 流程：

```json
{
  "generator": {
    "type": "settlement",
    "persistent_generated_settlement": true,
    "settlement_id": "generated_settlement"
  }
}
```

读取逻辑：

```text
有 snapshot → 读取并注册 exterior / interiors
无 snapshot → 编译 settlement → 生成 population / schedule → 写 snapshot → 注册并返回 exterior
```

`SceneLoader` 和 `LocationRoot` 仍把结果当普通 location 使用。

## Generated Baseline 与 Runtime Save State

`GeneratedSettlementStore` 管 baseline：

```text
exterior
interiors
building contracts
objects
anchors
schedule targets
initial NPC definitions
initial schedules
initial spawn rows
```

`SaveManager` 和各玩法系统管 runtime state：

```text
GameState
TimeManager
QuestSystem
PartySystem
RelationSystem
CropSystem
BusinessSystem
NpcScheduleSystem offscreen state
```

`SaveManager` 额外记录 generated settlement index：

```json
{
  "generated_settlements": {
    "generated_settlement": {
      "snapshot_path": "user://saves/slot_1/generated/settlements/generated_settlement.json",
      "schema_version": 1,
      "generator_version": "v67"
    }
  }
}
```

## 测试覆盖

新增测试：

```text
scripts/tests/v67_persistent_generated_settlement_population_smoke.gd
```

## v67.2 Persistence Integrity Update

v67.2 tightens the generated settlement baseline so it is bound to the active save context instead of a guessed slot path.

Current generated baseline paths are:

```text
user://saves/<slot_id>/worlds/<world_id>/generated/settlements/<settlement_instance_id>.json
user://saves/<slot_id>/worlds/<world_id>/generated/characters/<npc_id>.json
```

`SaveManager` now owns the active generated-content context:

```text
active_save_path
active_save_slot_id
active_world_id
generated_settlements
```

`GeneratedSettlementStore` reads snapshot paths from `SaveManager.generated_settlements` first. New snapshot writes use the current `SaveManager.get_generated_root_path()` and register the resulting snapshot path back into the save index.

`load_game()` restores generated settlement context before loading the saved scene:

```text
read save JSON
validate version
configure active save path / slot / world
restore generated_settlements index
clear generated runtime caches
restore system save states
load saved scene
restore controlled character
```

New game and slot/world changes clear generated runtime caches through `DefinitionLoader.clear_generated_runtime_cache()` and `GeneratedSettlementStore.clear_runtime_cache()`. Snapshots stay on disk; in-memory resolved locations and `user://` generated JSON cache entries are flushed when context changes.

v67.2 separates ID meanings in the snapshot:

```text
settlement_template_id: source/template identity
settlement_instance_id: persistent generated settlement instance
snapshot_id: stable baseline snapshot id
exterior_location_id: generated exterior location id
```

Formal generated IDs are namespaced before snapshot write. This includes building ids, source building ids, parent building ids, interior location ids, generated shop ids, generated object ids, schedule target ids, NPC ids, schedule entry ids, and role assignment ids. Interior anchor ids remain local to their location; schedule resolution still uses `location_id + anchor_id`.

`DefinitionLoader` now explicitly supports generated `user://` JSON definitions and reports generated-resource errors separately from ordinary `res://` definition errors.

Additional smoke coverage:

```text
scripts/tests/v67_2_generated_settlement_persistence_integrity_smoke.gd
```

The v67.2 smoke covers two-slot generation isolation, generated character source isolation, cache switching between slots, `load_game()` context/index restoration before scene load, generated `user://` character reads, and formal generated ID namespace integrity.

覆盖内容：

- 第一次 materialize persistent generated settlement 时写入 snapshot。
- snapshot 包含 exterior、generated interiors、building contracts、schedule targets。
- snapshot 包含 NPC definitions、role assignments、spawn rows。
- 每个 schedule target 都能解析到真实 location anchor。
- 每个 NPC schedule entry 都使用可解析的 `location_id + anchor_id`。
- generated NPC definition 文件可以通过 `DefinitionLoader.load_json_resource()` 读取。
- 至少一个 NPC 有 home target，至少一个 NPC 有 work/service target。
- spawn rows 已注入 exterior 或 interior location。
- generated interior 能通过 `DefinitionLoader.resolve_location_by_id()` 解析。
- 再次 materialize 同一 `settlement_id` 时读取同一 snapshot，settlement、policy、seed、NPC ids 保持稳定。
- `SaveManager` 记录 generated settlement index。
