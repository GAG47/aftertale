# Phase 5 Items And Interactions

本文档记录阶段 5 已建立的物品和交互对象系统。当前阶段让探索开始拥有可交互内容，并保证调查、拾取、使用都通过 `ActionSystem` 生效。

## 已建立内容

```text
Item 定义：data/items/*.json
Inventory：scripts/systems/items/inventory.gd
ItemStack：scripts/systems/items/item_stack.gd
装备槽：scripts/systems/items/equipment_slots.gd
场景掉落物：LocationObject kind=drop
可调查对象：LocationObject.is_inspectable
可拾取对象：LocationObject.is_pickable
可使用对象：LocationObject.is_usable
InspectAction：scripts/systems/actions/inspect_action.gd
PickUpAction：scripts/systems/actions/pick_up_action.gd
UseItemAction：scripts/systems/actions/use_item_action.gd
```

## 交互链路

```text
InputManager.primary_action_requested
LocationRoot 查找受控角色面前一格
LocationRoot 选择 InspectAction / PickUpAction / UseItemAction
ActionSystem.submit
Action.check
Action.execute
ActionResult 记录世界变化和表现反馈
```

`LocationRoot` 只负责把玩家的交互意图转换成 Action 请求，不直接修改背包、对象或世界事实。

## 当前测试内容

`test_field` 包含：

```text
Field Sign：可调查
Field Apple：可拾取，进入玩家 Inventory
Loose Crate：可调查、可使用
```

`test_clearing` 包含：

```text
Clearing Marker：可调查
Fallen Stick：可拾取，进入玩家 Inventory
Old Switch：可调查、可使用
```

## 当前边界

背包和装备槽是规则结构，当前没有 UI 界面。调试面板会显示受控角色背包摘要。

`UseItemAction` 已支持使用场景对象和背包物品的规则入口。当前背包物品使用只记录反馈和世界变化，不接属性变化；属性成长和消耗品效果应在后续角色成长 / 物品效果系统中接入。

装备槽已建立结构，但装备动作和装备 UI 暂不实现。后续应通过专门的 Action 接入，不允许 UI 直接改装备槽。
