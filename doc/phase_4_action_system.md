# Phase 4 Action System

本文档记录阶段 4 已建立的行动系统。行动系统是规则层核心入口，所有会改变世界的行为都应通过统一 Action 结构，而不是由 UI、NPC、AI 或场景节点直接改状态。

## 已建立内容

```text
ActionSystem：scripts/systems/actions/action_system.gd
ActionResult：scripts/systems/actions/action_result.gd
GameAction 基类：scripts/systems/actions/game_action.gd
MoveAction：scripts/systems/actions/move_action.gd
TalkAction：scripts/systems/actions/talk_action.gd
InspectAction：scripts/systems/actions/inspect_action.gd
PickUpAction：scripts/systems/actions/pick_up_action.gd
UseItemAction：scripts/systems/actions/use_item_action.gd
AttackAction：scripts/systems/actions/attack_action.gd
TradeAction：scripts/systems/actions/trade_action.gd
RestAction：scripts/systems/actions/rest_action.gd
CraftAction：scripts/systems/actions/craft_action.gd
AcceptQuestAction：scripts/systems/actions/accept_quest_action.gd
```

`ActionSystem` 已在 `project.godot` 注册为 Autoload。

## Action 结构

每个 Action 都包含：

```text
发起者：actor / actor_id
目标：target
上下文：context
条件检查：check
执行结果：execute -> ActionResult
世界状态变化：ActionResult.world_changes
表现反馈：ActionResult.feedback
```

`ActionSystem.submit` 会先调用 `check`，通过后再调用 `execute`。执行结果会进入最近行动记录和行动历史，调试面板可观察最近一次行动。

## 当前真实执行的行动

`MoveAction` 已完整接入当前场景系统：

```text
InputManager.move_requested
LocationRoot 创建 MoveAction
ActionSystem.submit
MoveAction.check 检查角色、方向、场景网格和目标格
MoveAction.execute 更新角色朝向、网格占用、角色格子位置
MoveAction 发现出口时请求场景切换
```

因此当前移动已经不再由 `LocationRoot` 直接修改角色位置。`LocationRoot` 只提供当前场景上下文，并在行动成功后同步自身观察用坐标。

## 尚未执行的行动

以下行动类已经存在，并遵循同一个 Action 结构：

```text
TalkAction
InspectAction
PickUpAction
UseItemAction
AttackAction
TradeAction
RestAction
CraftAction
AcceptQuestAction
```

由于对话、物品、战斗、交易、休息、制作和任务系统尚未实现，它们当前会返回明确的规则失败，不修改世界事实。这不是临时绕行，而是阶段边界：动作入口已经存在，缺失的是后续系统的具体规则。

## 后续接入原则

后续系统不得绕过 `ActionSystem` 直接改世界事实。比如：

```text
对话选项导致关系变化 -> TalkAction 或后续对话结果 Action
拾取物品 -> PickUpAction
攻击角色 -> AttackAction
接受任务 -> AcceptQuestAction
使用物品 -> UseItemAction
```

UI、NPC、AI 或场景节点只能请求行动，不能直接写入世界状态。
