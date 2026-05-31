# Phase 7 Quest System

本文档记录阶段 7 已建立的任务系统。任务系统在角色、行动、物品和对话之后接入，任务推进必须来自行动结果、世界状态或事件触发。

## 已建立内容

```text
Quest 定义：data/quests/*.json
Quest State：scripts/systems/quests/quest_state.gd
QuestSystem：scripts/systems/quests/quest_system.gd
Quest Source：任务定义中的 source 字段
任务接受：AcceptQuestAction
任务推进：QuestSystem 监听 ActionSystem.action_executed
任务完成：QuestSystem 检查 objectives 并发放 rewards
任务失败：QuestSystem.fail_quest
```

`QuestSystem` 已注册为 Autoload。

## 当前测试任务

```text
data/quests/debug_apple_request.json
```

流程：

```text
面对 Debug Villager 按 E
选择“有什么我能帮忙的吗？”
AcceptQuestAction 接受 debug_apple_request
拾取 Debug Apple
QuestSystem 通过 has_item 目标推进
再次与 Debug Villager 对话
选择“我捡到一个苹果。”
QuestSystem 通过 dialogue_option_selected 目标完成任务
任务奖励发放 Debug Key，并设置 debug_apple_request_completed flag
```

## 目标类型

当前支持：

```text
has_item
item_picked_up
dialogue_option_selected
flag_set
```

## 奖励类型

当前支持：

```text
item
flag
```

奖励由 `QuestSystem` 作为规则系统执行，不由 UI 或对话面板直接发放。

## 对话接入

对话选项可以使用：

```text
result type=request_action
action_type=AcceptQuestAction
quest_id=...
```

`DialogueRunner` 会请求 `ActionSystem.submit`，而不是直接修改任务状态。对话选项本身也会发布为 `DialogueOption` 结果，供 `QuestSystem` 监听推进。

## 边界

当前不实现任务 UI、地图任务追踪、时间限制失败、复杂分支任务或关系奖励。这些后续必须继续通过 ActionSystem、QuestSystem 或事件系统接入。
