extends Node

@onready var world_root: Node = $WorldRoot
@onready var ui_root: UIRoot = $UILayer/UIRoot


func _ready() -> void:
	SceneLoader.configure(world_root)
	if _try_run_smoke_test_from_flag():
		return

	InputManager.debug_toggle_requested.connect(_on_debug_toggle_requested)
	InputManager.cancel_requested.connect(_on_cancel_requested)
	InputManager.save_requested.connect(_on_save_requested)
	InputManager.load_requested.connect(_on_load_requested)

	ui_root.bind_managers(GameState, SceneLoader, TimeManager, InputManager, ActionSystem, DialogueRunner, QuestSystem, RelationSystem)
	ui_root.return_title_requested.connect(_on_return_title_requested)
	ui_root.new_game_requested.connect(_on_new_game_requested)
	ui_root.quit_game_requested.connect(_on_quit_game_requested)

	_start_new_game()


func _try_run_smoke_test_from_flag() -> bool:
	var smoke_path := ""
	if FileAccess.file_exists("res://data/run_v67_3_smoke.json"):
		smoke_path = "res://scripts/tests/v67_3_generated_npc_schedule_appearance_integrity_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v67_2_smoke.json"):
		smoke_path = "res://scripts/tests/v67_2_generated_settlement_persistence_integrity_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v67_smoke.json"):
		smoke_path = "res://scripts/tests/v67_persistent_generated_settlement_population_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v65_smoke.json"):
		smoke_path = "res://scripts/tests/v65_unified_interaction_resolver_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v64_contract_smoke.json"):
		smoke_path = "res://scripts/tests/v64_generated_interiors_contract_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v64_smoke.json"):
		smoke_path = "res://scripts/tests/v64_policy_playable_settlement_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v63_smoke.json"):
		smoke_path = "res://scripts/tests/v63_settlement_scene_compiler_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v62_smoke.json"):
		smoke_path = "res://scripts/tests/v62_general_settlement_generation_smoke.gd"
	elif FileAccess.file_exists("res://data/run_v61_smoke.json"):
		smoke_path = "res://scripts/tests/v61_settlement_planning_smoke.gd"
	else:
		return false

	var smoke_script := load(smoke_path) as Script
	if smoke_script == null:
		push_error("Could not load settlement smoke test script: %s" % smoke_path)
		get_tree().quit(1)
		return true

	var smoke_test = smoke_script.new()
	var ok: bool = smoke_test.run(self)
	get_tree().quit(0 if ok else 1)
	return true


func _start_new_game() -> void:
	GameState.start_new_session()
	NpcScheduleSystem.reset_schedule_state()
	SaveManager.reset_active_save_context()
	PartySystem.reset_party("debug_player")
	GameState.set_scene_context("boot", "none")

	TimeManager.reset()
	TimeManager.set_paused(false)

	SceneLoader.load_location("res://scenes/locations/generated_settlement.tscn", "main_entrance")


func _on_debug_toggle_requested() -> void:
	ui_root.toggle_debug_panel()
	if SceneLoader.current_scene != null and is_instance_valid(SceneLoader.current_scene):
		if SceneLoader.current_scene.has_method("set_debug_presentation_visible"):
			SceneLoader.current_scene.set_debug_presentation_visible(ui_root.is_debug_panel_visible())


func _on_save_requested() -> void:
	SaveManager.save_game()


func _on_load_requested() -> void:
	SaveManager.load_game()


func _on_cancel_requested() -> void:
	if ui_root.is_title_screen_visible():
		return

	if ui_root.is_facility_visible():
		ui_root.close_facility()
		return

	if ui_root.is_character_visible():
		ui_root.close_character_panel()
		return

	if ui_root.is_quest_visible():
		ui_root.close_quest_panel()
		return

	if ui_root.is_inventory_visible():
		ui_root.close_inventory()
		return

	if ui_root.is_game_menu_visible():
		ui_root.close_game_menu()
		return

	if DialogueRunner.active:
		DialogueRunner.cancel_dialogue()
		return

	if BattleSystem.is_active() and SceneLoader.current_scene != null and is_instance_valid(SceneLoader.current_scene) and SceneLoader.current_scene.has_method("try_flee_battle"):
		if bool(SceneLoader.current_scene.try_flee_battle()):
			return

	if ui_root.is_debug_panel_visible():
		ui_root.set_debug_panel_visible(false)
		return

	ui_root.open_game_menu()


func _on_return_title_requested() -> void:
	SceneLoader.unload_current_scene()
	GameState.set_scene_context("title", "none")
	TimeManager.set_paused(true)
	ui_root.open_title_screen()


func _on_new_game_requested() -> void:
	ui_root.clear_transient_ui()
	_start_new_game()


func _on_quit_game_requested() -> void:
	get_tree().quit()
