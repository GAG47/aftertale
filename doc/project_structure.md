# Project Structure

本文档定义阶段 0 的 Godot 项目骨架。当前阶段只建立稳定位置，不实现可玩闭环，也不接入 AI、后端或 RAG。

## 根目录职责

```text
assets/      原始美术、音频、字体等可导入素材。
data/        游戏事实和配置数据，如世界、角色、物品、任务、阵营。
resources/   Godot Resource 资源，如 .tres 定义、主题、材质、Tileset。
scenes/      Godot 场景文件，如启动、世界、地点、角色、物体、战斗场景。
scripts/     GDScript 代码，包含核心框架、规则系统、UI 脚本和调试脚本。
tools/       编辑器工具、导入工具、校验工具和后续构建辅助脚本。
doc/         设计文档、架构记录和工程说明。
```

## 目录树

```text
assets/
  art/
    characters/
    tilesets/
    objects/
    ui/
  audio/
    music/
    sfx/
  fonts/

data/
  world/
  locations/
  characters/
  items/
  dialogues/
  quests/
  factions/
  economy/
  generation/

resources/
  definitions/
  tilesets/
  themes/
  materials/

scenes/
  boot/
  world/
  locations/
  characters/
  objects/
  combat/
  ui/
    screens/
    components/

scripts/
  core/
  systems/
    actions/
    characters/
    scenes/
    items/
    dialogues/
    quests/
    time/
    combat/
  ui/
  debug/

tools/
  editor/
  import/
  validation/
```

## 放置原则

表现层内容放在 `scenes/`、`assets/` 和 `resources/`；规则层代码放在 `scripts/systems/`；项目基础框架放在 `scripts/core/`。

UI 场景统一放在 `scenes/ui/`，UI 脚本放在 `scripts/ui/`，UI 主题资源放在 `resources/themes/`，UI 原始素材放在 `assets/art/ui/`。根目录不单独保留 `ui/`，避免和 Godot 场景、脚本、资源目录重复。

会改变世界事实的逻辑应进入规则系统，不能直接写在 UI、场景节点或素材资源中。阶段 1 之后，启动场景、全局状态、场景加载、输入、时间和调试入口应优先落在现有目录中。

AI 相关内容当前不创建目录、不写接口；等进入 AI / 后端增强阶段时，再基于已经稳定的规则层和世界状态单独设计接入位置。
