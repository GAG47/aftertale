# Project Structure

本文档是 Aftertale 项目目录和文档索引入口。详细架构说明请优先阅读 v66 新增的当前架构文档。

## 主要文档入口

- `doc/project_current_architecture.md`：从整个项目角度总结当前架构、9 层结构、Autoload、数据目录、运行流程和系统关系。
- `doc/system_catalog.md`：按目录整理当前系统职责、主要文件、相关系统、当前状态和后续可能扩展方向。
- `doc/architecture_observations.md`：总结当前架构观察、协作路径、结构性问题、后续注意事项和 AI 接入边界。
- `doc/phase_67_persistent_generated_settlement_population.md`：v67 生成聚落持久化、居民生成和 NPC 日程接入记录。
- `doc/project_direction_notes.md`：项目方向说明。
- `doc/development_todo_progress.md`：开发进度和待办记录。
- `doc/phase_*.md`：各阶段功能实现记录。

## 根目录职责

```text
assets/              原始美术、音频、字体等可导入素材。
data/                JSON 游戏定义和生成输入，例如角色、地点、物品、技能、任务、商店、作物、聚落 policy。
doc/                 设计文档、阶段记录、架构说明和项目索引。
resources/           Godot Resource 资源，例如主题、材质、tileset 或其他 .tres 定义。
scenes/              Godot 场景文件，包括启动场景、location、UI 和工具场景。
scripts/             GDScript 代码，包括核心运行层、玩法系统、UI、调试、测试和工具脚本。
tools/               编辑器工具、导入工具、校验工具和构建辅助脚本。
```

## 关键代码目录

```text
scripts/core/        启动、全局状态、场景加载、定义加载、输入管理。
scripts/systems/     RPG 规则和玩法系统。
scripts/ui/          UI 面板和 UI 逻辑脚本。
scripts/debug/       调试面板和调试辅助脚本。
scripts/tests/       阶段 smoke tests 和工具场景测试。
scripts/tools/       资源处理和工具场景脚本。
```

`scripts/systems/` 下当前已经形成多个子系统，例如 actions、battle、business、characters、crafting、crops、dialogues、items、party、quests、relations、save、scenes、schedules、settlements、skills、time。实际战斗实现目前集中在 `scripts/systems/battle/`，`scripts/systems/combat/` 当前只是占位目录。

## 数据目录

`data/` 当前是项目定义数据的主要入口，包含 appearance、battle、characters、crops、dialogues、factions、items、locations、quests、recipes、relations、settlement_policies、shops、skills 等目录。`economy`、`generation`、`world` 当前主要是预留或早期占位目录。

理解数据目录时，建议同时阅读：

- `doc/project_current_architecture.md`
- `doc/system_catalog.md`

## 场景目录

`scenes/` 当前包含：

- `scenes/boot/`：启动主场景。
- `scenes/locations/`：可加载 location 场景，包括手写和生成聚落相关场景。
- `scenes/ui/`：UI screens 和 components。
- `scenes/tools/`：工具和调试场景。

## 放置原则

表现层内容优先放在 `scenes/`、`assets/` 和 `resources/`。规则层代码优先放在 `scripts/systems/`。项目基础运行框架放在 `scripts/core/`。数据定义放在 `data/`。文档和阶段记录放在 `doc/`。

会改变世界事实或玩法状态的逻辑，应优先进入已有规则系统或新增系统入口，而不是直接写在 UI、场景节点或素材资源中。当前架构和目录详情以 `doc/project_current_architecture.md` 与 `doc/system_catalog.md` 为主要入口。
