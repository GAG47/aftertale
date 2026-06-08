extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui_scene: PackedScene = load("res://scenes/ui/screens/ui_root.tscn")
	var ui_root: Control = ui_scene.instantiate() as Control
	var battle_hud: BattleHudPanel = ui_root.get_node("BattleHudPanel") as BattleHudPanel
	ui_root.remove_child(battle_hud)
	ui_root.free()
	add_child(battle_hud)
	var player: Dictionary = _unit("debug_player", "测试玩家", "player", true, {})
	player["status_effects"] = {
		"wet": {
			"id": "wet",
			"status_id": "wet",
			"display_name": "湿润",
		},
	}
	var enemy: Dictionary = _unit("debug_training_dummy", "训练假人", "enemy", false, {})
	var summary: Dictionary = {
		"battle_id": "v55_ui_smoke",
		"active": true,
		"round": 11,
		"current_unit": player,
		"turn_order": [player, enemy],
		"selectable_player_units": [player],
		"presentation_pending": false,
		"recent_ai_decisions": [{
			"character_id": "训练假人",
			"profile_id": "defensive",
			"candidate_count": 18,
			"chosen": {
				"description": "移动到 (7, 4) 后使用雷霆射线",
				"total_score": 49.0,
				"score_breakdown": [
					{"label": "元素反应", "raw": 15.0, "weight": 1.6, "weighted": 24.0},
					{"label": "伤害收益", "raw": 8.0, "weight": 0.9, "weighted": 7.2},
					{"label": "资源消耗", "raw": -5.0, "weight": 1.0, "weighted": -5.0},
				],
			},
			"top_candidates": [
				{"description": "移动后使用雷霆射线", "total_score": 49.0},
				{"description": "原地使用普通攻击", "total_score": 12.0},
				{"description": "等待", "total_score": -2.0},
			],
		}],
	}
	battle_hud.show_battle_summary(
		summary,
		true,
		[
			_skill("basic_attack", "普通攻击", 0),
			_skill("power_strike", "重击", 1),
			_skill("quick_shot", "速射", 1),
			_skill("first_aid", "急救", 1),
		],
		"basic_attack",
		"move"
	)
	await get_tree().process_frame

	var character_dock: Control = battle_hud.get_node("CharacterDock") as Control
	var skill_dock: Control = battle_hud.get_node("SkillDock") as Control
	var viewport_rect: Rect2 = battle_hud.get_viewport_rect()
	if character_dock.get_global_rect().intersects(skill_dock.get_global_rect()):
		push_error("v55 character and skill docks overlap")
		get_tree().quit(1)
		return
	if not viewport_rect.encloses(skill_dock.get_global_rect()):
		push_error("v55 skill dock must remain inside the viewport")
		get_tree().quit(1)
		return
	if battle_hud.has_node("ContextPreview"):
		push_error("v55 must not create a center context preview")
		get_tree().quit(1)
		return
	var status_icons: HBoxContainer = character_dock.find_child("StatusIcons", true, false) as HBoxContainer
	if status_icons == null or status_icons.get_child_count() != 1:
		push_error("v55 character dock must render active status icons")
		get_tree().quit(1)
		return
	var turn_list: VBoxContainer = battle_hud.get_node(
		"TurnOrderPanel/Margin/Box/Scroll/List"
	) as VBoxContainer
	if turn_list.get_child_count() != 2:
		push_error("v55 turn order must show exactly one round")
		get_tree().quit(1)
		return

	battle_hud.toggle_ai_debug()
	await get_tree().process_frame
	var ai_panel: Control = battle_hud.get_node("AiDebugPanel") as Control
	if not ai_panel.visible:
		push_error("v55 AI debug panel did not open")
		get_tree().quit(1)
		return
	print("v55 UI smoke test passed")
	get_tree().quit(0)


func _unit(
	character_id: String,
	display_name: String,
	team: String,
	is_current: bool,
	appearance: Dictionary
) -> Dictionary:
	return {
		"character_id": character_id,
		"display_name": display_name,
		"team": team,
		"is_current": is_current,
		"speed": 5 if team == "player" else 4,
		"hp": 20 if team == "player" else 12,
		"max_hp": 20 if team == "player" else 16,
		"mp": 8 if team == "player" else 3,
		"max_mp": 15 if team == "player" else 6,
		"action_points": 2,
		"max_action_points": 2,
		"status_text": "湿润" if team == "enemy" else "",
		"status_effects": {},
		"appearance": appearance,
		"level": 1,
		"attack": 6,
		"defense": 5,
	}


func _skill(skill_id: String, display_name: String, mp_cost: int) -> Dictionary:
	return {
		"id": skill_id,
		"display_name": display_name,
		"description": "%s 测试。" % display_name,
		"range": 1,
		"ap_cost": 1,
		"mp_cost": mp_cost,
		"can_use": true,
		"failure_reason": "",
	}
