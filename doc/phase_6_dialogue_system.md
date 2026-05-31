# Phase 6 Non-AI Dialogue System

本文档记录阶段 6 已建立的传统 RPG 对话系统。当前阶段不接 AI，对话资源完全来自本地 JSON。

## 已建立内容

```text
对话资源：data/dialogues/*.json
DialogueRunner：scripts/systems/dialogues/dialogue_runner.gd
DialoguePanel：scenes/ui/components/dialogue_panel.tscn
TalkAction：scripts/systems/actions/talk_action.gd
NPC dialogue_source：data/characters/*.json
```

## 对话启动链路

```text
InputManager.primary_action_requested
LocationRoot 检查受控角色面前一格是否有可交互角色
LocationRoot 创建 TalkAction
ActionSystem.submit
TalkAction.check 验证说话人、距离、对话资源
TalkAction.execute 调用 DialogueRunner.start_dialogue
DialogueRunner 设置 GameState 为 DIALOGUE
DialoguePanel 显示当前节点和选项
```

UI 只显示文本和选项，不直接修改世界事实。

## 当前条件与结果

当前条件支持：

```text
has_flag
not_flag
has_item
character_kind
faction_id
```

当前结果支持：

```text
set_flag
```

结果由 `DialogueRunner` 转成规则结果和 `ActionResult.world_changes`，不由 UI 直接执行。

## 当前测试内容

```text
debug_villager -> data/dialogues/debug_villager_dialogue.json
debug_guard -> data/dialogues/debug_guard_dialogue.json
```

面对 NPC 按 `E` 会进入对话模式。点击选项推进节点，选择结束选项或按 `Esc` 返回探索模式。

## 边界

当前阶段不实现任务发放、关系变化、商店交易、战斗触发或 AI 生成对白。这些后续必须继续通过行动系统、任务系统、关系系统或事件系统接入。
