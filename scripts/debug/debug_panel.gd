class_name DebugPanel
extends PanelContainer

@onready var status_label: Label = $MarginContainer/StatusLabel

var _game_state: Node
var _scene_loader: Node
var _time_manager: Node
var _input_manager: Node
var _action_system: Node
var _dialogue_runner: Node
var _quest_system: Node
var _relation_system: Node


func _ready() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func bind_managers(game_state: Node, scene_loader: Node, time_manager: Node, input_manager: Node, action_system: Node, dialogue_runner: Node, quest_system: Node, relation_system: Node) -> void:
	_game_state = game_state
	_scene_loader = scene_loader
	_time_manager = time_manager
	_input_manager = input_manager
	_action_system = action_system
	_dialogue_runner = dialogue_runner
	_quest_system = quest_system
	_relation_system = relation_system
	_refresh()


func _refresh() -> void:
	if _game_state == null:
		return

	var active_scene := "无"
	if _scene_loader.current_scene_path != "":
		active_scene = _scene_loader.current_scene_path

	var location_summary: Dictionary = {}
	if _scene_loader.current_scene != null and is_instance_valid(_scene_loader.current_scene) and _scene_loader.current_scene.has_method("get_location_summary"):
		location_summary = _scene_loader.current_scene.get_location_summary() as Dictionary

	var location_line := "地点：无"
	var grid_line := "格子：无"
	var object_line := "对象：0"
	var character_line := "角色：0"
	var controlled_line := "操控角色：无"
	var controlled_flags_line := "标记：无"
	var inventory_line := "背包：空"
	var currency_line := "金币：0"
	var action_line := "最近行动：无"
	var action_feedback_line := "行动反馈：无"
	var dialogue_line := "对话：未进行"
	var quest_line := "任务：无"
	var npc_schedule_line := "NPC日程：无"
	var relation_line := "关系：无"
	var battle_line := "战斗：未进行"
	var generation_line := "生成：无"
	if not location_summary.is_empty():
		location_line = "地点：%s" % location_summary.get("display_name", "未知")
		grid_line = "格子：%dx%d @ %dpx" % [
			location_summary.get("width", 0),
			location_summary.get("height", 0),
			location_summary.get("tile_size", 0),
		]
		object_line = "对象：%d，出口：%d" % [
			location_summary.get("object_count", 0),
			location_summary.get("exit_count", 0),
		]
		character_line = "角色：%d" % [
			location_summary.get("character_count", 0),
		]
		var generation_summary: Dictionary = location_summary.get("generation_summary", {}) as Dictionary
		if not generation_summary.is_empty():
			generation_line = "生成：%s seed=%s 通行=%.3f 水=%.3f 湿地=%.3f 林=%.3f 石=%.3f 低=%.3f 高=%.3f 坡=%.3f 脊=%.3f" % [
				str(generation_summary.get("profile", "unknown")),
				str(generation_summary.get("seed", "")),
				float(generation_summary.get("passable_ratio", 0.0)),
				float(generation_summary.get("water_ratio", 0.0)),
				float(generation_summary.get("wetland_ratio", 0.0)),
				float(generation_summary.get("forest_ratio", 0.0)),
				float(generation_summary.get("rock_ratio", 0.0)),
				float(generation_summary.get("lowland_ratio", 0.0)),
				float(generation_summary.get("highland_ratio", 0.0)),
				float(generation_summary.get("slope_ratio", 0.0)),
				float(generation_summary.get("ridge_ratio", 0.0)),
			]

		var controlled_character: Dictionary = location_summary.get("controlled_character", {}) as Dictionary
		if not controlled_character.is_empty():
			controlled_line = "操控角色：%s %s 面向%s" % [
				controlled_character.get("id", "unknown"),
				controlled_character.get("grid_position", Vector2i.ZERO),
				_translate_facing(str(controlled_character.get("facing", "unknown"))),
			]
			controlled_flags_line = "标记：可交互=%s 可战斗=%s 阵营=%s" % [
				controlled_character.get("is_interactable", false),
				controlled_character.get("is_combatable", false),
				controlled_character.get("faction_id", "none"),
			]

		var inventory_summary: Array = location_summary.get("controlled_inventory", []) as Array
		if not inventory_summary.is_empty():
			var parts := PackedStringArray()
			for stack_value in inventory_summary:
				var stack: Dictionary = stack_value as Dictionary
				parts.append("%s x%s" % [
					str(stack.get("display_name", stack.get("item_id", "unknown"))),
					str(stack.get("quantity", 0)),
				])
			inventory_line = "背包：%s" % ", ".join(parts)

		if not controlled_character.is_empty():
			currency_line = "金币：%d" % BusinessSystem.get_currency(str(controlled_character.get("id", "")))

		var character_summaries: Array = location_summary.get("characters", []) as Array
		if not character_summaries.is_empty():
			var schedule_parts := PackedStringArray()
			for character_value in character_summaries:
				var character: Dictionary = character_value as Dictionary
				if bool(character.get("is_player_controlled", false)):
					continue
				schedule_parts.append("%s %s @ %s" % [
				str(character.get("id", "未知")),
				str(character.get("activity", "待机")),
					str(character.get("grid_position", Vector2i.ZERO)),
				])
			if not schedule_parts.is_empty():
				npc_schedule_line = "NPC日程：%s" % ", ".join(schedule_parts)

			if _relation_system != null and not controlled_character.is_empty():
				var relation_summary: Array = _relation_system.get_summary_for_actor(
					str(controlled_character.get("id", "")),
					character_summaries
				) as Array
				if not relation_summary.is_empty():
					var relation_parts := PackedStringArray()
					for relation_value in relation_summary:
						var relation: Dictionary = relation_value as Dictionary
						relation_parts.append("%s %s A%d T%d H%d" % [
							str(relation.get("source_id", "未知")),
							str(relation.get("stance", "neutral")),
							int(relation.get("affinity", 0)),
							int(relation.get("trust", 0)),
							int(relation.get("hostility", 0)),
						])
					relation_line = "关系：%s" % ", ".join(relation_parts)

	if _action_system != null:
		var action_summary: Dictionary = _action_system.get_last_summary() as Dictionary
		if not action_summary.is_empty():
			action_line = "最近行动：%s 成功=%s 变化=%d" % [
				action_summary.get("action_type", "未知"),
				action_summary.get("success", false),
				(action_summary.get("world_changes", []) as Array).size(),
			]

			var feedback: Array = action_summary.get("feedback", []) as Array
			if not feedback.is_empty():
				action_feedback_line = "行动反馈：%s" % str(feedback[feedback.size() - 1])

	if _dialogue_runner != null and bool(_dialogue_runner.active):
		var dialogue_state: Dictionary = _dialogue_runner.get_current_state() as Dictionary
		dialogue_line = "对话：%s/%s" % [
			dialogue_state.get("dialogue_id", "未知"),
			dialogue_state.get("node_id", "未知"),
		]

	if _quest_system != null:
		var quest_summary: Array = _quest_system.get_summary() as Array
		if not quest_summary.is_empty():
			var quest_parts := PackedStringArray()
			for quest_value in quest_summary:
				var quest: Dictionary = quest_value as Dictionary
				quest_parts.append("%s %s %d/%d" % [
					str(quest.get("quest_id", "未知")),
					str(quest.get("status", "unknown")),
					int(quest.get("completed_count", 0)),
					int(quest.get("total_count", 0)),
				])
			quest_line = "任务：%s" % ", ".join(quest_parts)

	if BattleSystem.is_active():
		var battle_summary: Dictionary = BattleSystem.get_summary()
		var current_unit: Dictionary = battle_summary.get("current_unit", {}) as Dictionary
		var unit_parts := PackedStringArray()
		var battle_units: Array = battle_summary.get("units", []) as Array
		for unit_value in battle_units:
			var unit: Dictionary = unit_value as Dictionary
			unit_parts.append("%s %s 生命%d/%d 行动点%d 速度%d" % [
				str(unit.get("character_id", "未知")),
				_translate_team(str(unit.get("team", "?"))),
				int(unit.get("hp", 0)),
				int(unit.get("max_hp", 0)),
				int(unit.get("action_points", 0)),
				int(unit.get("speed", 0)),
			])
		battle_line = "战斗：第%d回合 当前=%s 行动点%d | %s" % [
			int(battle_summary.get("round", 0)),
			str(current_unit.get("character_id", "无")),
			int(current_unit.get("action_points", 0)),
			", ".join(unit_parts),
		]

	status_label.text = "\n".join([
		"调试面板",
		"会话：%s" % _game_state.session_id,
		"模式：%s" % _game_state.get_mode_label(),
		"场景上下文：%s" % _game_state.current_scene_id,
		"地点上下文：%s" % _game_state.current_location_id,
		"已加载场景：%s" % active_scene,
		location_line,
		grid_line,
		object_line,
		character_line,
		generation_line,
		controlled_line,
		controlled_flags_line,
		inventory_line,
		currency_line,
		action_line,
		action_feedback_line,
		dialogue_line,
		quest_line,
		npc_schedule_line,
		relation_line,
		battle_line,
		"时间：%s（%s）" % [_time_manager.get_time_label(), _time_manager.get_day_period_label()],
		"时间暂停：%s" % _time_manager.is_paused,
		"输入锁定：%s" % _input_manager.input_locked,
		"开关：F3",
	])


func _translate_facing(facing: String) -> String:
	match facing:
		"up":
			return "上方"
		"down":
			return "下方"
		"left":
			return "左侧"
		"right":
			return "右侧"
		_:
			return facing


func _translate_team(team: String) -> String:
	match team:
		"player":
			return "我方"
		"enemy":
			return "敌方"
		_:
			return team
