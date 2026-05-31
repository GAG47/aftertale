# Phase 3 Character Entity System

本文档记录阶段 3 已建立的通用角色实体系统。当前阶段只建立角色作为世界实体的基础，不实现 NPC AI、对话、攻击、队伍、动画或完整行动系统。

## 已建立内容

```text
Character 基础实体：scripts/systems/characters/character_entity.gd
格子位置：CharacterEntity.grid_position
朝向：CharacterEntity.facing
移动：LocationRoot 接收输入，LocationGrid 判定，CharacterEntity 更新位置
属性容器：CharacterEntity.attributes
身份信息：CharacterEntity.identity
阵营 / 关系占位：faction_id / relation_slots
可交互标记：is_interactable
可战斗标记：is_combatable
角色占用规则：LocationGrid.register_character / move_character
```

## 数据

角色定义放在：

```text
data/characters/debug_player.json
data/characters/debug_villager.json
data/characters/debug_guard.json
```

地点中的角色生成配置放在 `data/locations/*.json` 的 `characters` 字段中。地点只说明角色在哪里出现，角色自身属性、身份、阵营和标记来自 `data/characters/*.json`。

## 单一实体原则

玩家、NPC、敌人和队友当前都使用同一个 `CharacterEntity`。区别由以下字段表达：

```text
character_kind
is_player_controlled
is_interactable
is_combatable
faction_id
relation_slots
```

不在阶段 3 拆分 `PlayerCharacter`、`NpcCharacter`、`EnemyCharacter` 或 `CompanionCharacter`。原因是角色身份会随世界状态变化，而不是固定类层级。后续如果出现稳定的差异，应优先考虑控制器或组件，而不是过早拆子类。

## 当前移动链路

```text
InputManager.move_requested
LocationRoot 找到 is_player_controlled 的 CharacterEntity
CharacterEntity 更新朝向
LocationGrid.move_character 判定目标格可进入并更新占用
CharacterEntity.set_grid_position 更新角色格子和显示位置
LocationRoot 检查出口并调用 SceneLoader.load_location
```

这条链路仍是阶段 3 的临时规则链路。阶段 4 行动系统建立后，应改成：

```text
InputManager -> MoveAction -> ActionSystem -> LocationGrid -> CharacterEntity
```

## 调试表现

当前角色使用调试图形：

```text
player：白色
npc：蓝色
enemy：红色
companion：绿色
黄色小点：可交互
红色小点：可战斗
黑色线：朝向
```

这些只是表现层占位。正式 16x16 像素角色资源进入后，应替换绘制方式，不改角色规则结构。
