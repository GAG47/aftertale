# Phase 1 Runtime Framework

本文档记录阶段 1 已建立的 Godot 内部基础运行框架。当前阶段只提供后续系统的统一挂载点和信号入口，不实现具体玩法闭环，不接入 AI、后端或 RAG。

## 已建立内容

```text
主启动场景：scenes/boot/main.tscn
全局游戏状态：scripts/core/game_state.gd
场景加载管理：scripts/core/scene_loader.gd
时间管理基础：scripts/systems/time/time_manager.gd
输入管理：scripts/core/input_manager.gd
UI 根节点：scenes/ui/screens/ui_root.tscn
调试面板入口：scenes/ui/components/debug_panel.tscn
```

## Autoload

以下管理器已在 `project.godot` 中注册为 Autoload：

```text
GameState
SceneLoader
TimeManager
InputManager
```

这些全局入口只负责基础状态、信号和调度。后续系统应依赖这些入口协作，而不是在 UI 或场景节点里直接改世界事实。

## 启动流程

```text
Main 场景启动
SceneLoader 绑定 WorldRoot 作为场景容器
UIRoot 绑定 GameState / SceneLoader / TimeManager / InputManager
GameState 创建新会话
GameState 设置当前上下文为 boot
TimeManager 重置到 Day 1 06:00 并开始推进
```

## 输入入口

`InputManager` 在运行时注册基础输入动作：

```text
W / Up：向上
S / Down：向下
A / Left：向左
D / Right：向右
E / Enter：主要交互
Escape：取消
F3：显示或隐藏调试面板
```

当前阶段只发出输入信号，不直接移动角色、不触发对话、不改变世界事实。

## 调试面板

按 `F3` 可显示调试面板。面板用于观察当前会话、模式、场景上下文、加载场景、时间和输入锁定状态。

调试面板是观察入口，不是规则入口。它不负责修改世界事实。

## 后续接入原则

阶段 2 的场景系统应接入 `SceneLoader` 和 `GameState`，并把场景事实写入规则层或世界状态结构。角色、物品、任务、战斗等系统应继续放在 `scripts/systems/`，通过信号和明确接口接入当前运行框架。
