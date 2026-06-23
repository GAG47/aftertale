extends Node

const DEFAULT_WORLD_PATH := "res://data/worlds/test_world.json"

@onready var world_root: Node = $WorldRoot
@onready var ui_root: UIRoot = $UILayer/UIRoot


func _ready() -> void:
	SceneLoader.configure(world_root)

	InputManager.debug_toggle_requested.connect(_on_debug_toggle_requested)
	InputManager.cancel_requested.connect(_on_cancel_requested)
	InputManager.save_requested.connect(_on_save_requested)
	InputManager.load_requested.connect(_on_load_requested)

	ui_root.bind_managers(GameState, SceneLoader, TimeManager, InputManager, ActionSystem, DialogueRunner, QuestSystem, RelationSystem)
	ui_root.return_title_requested.connect(_on_return_title_requested)
	ui_root.new_game_requested.connect(_on_new_game_requested)
	ui_root.quit_game_requested.connect(_on_quit_game_requested)

	_start_new_game()


func _start_new_game() -> void:
	GameState.start_new_session()
	NpcScheduleSystem.reset_schedule_state()
	PartySystem.reset_party("debug_player")
	GameState.set_scene_context("boot", "none")

	TimeManager.reset()
	TimeManager.set_paused(false)

	var world_service: Variant = _world_transition_service()
	var world_result: Dictionary = world_service.load_world(DEFAULT_WORLD_PATH) if world_service != null else {
		"success": false,
		"error": "WorldTransitionService autoload is unavailable.",
	}
	if bool(world_result.get("success", false)):
		var start_result: Dictionary = world_service.start_world(true)
		if bool(start_result.get("success", false)):
			return
		push_warning("World start failed, falling back to direct test village load: %s" % str(start_result.get("error", "")))
	else:
		push_warning("World load failed, falling back to direct test village load: %s" % str(world_result.get("error", "")))
	SceneLoader.load_location("res://scenes/locations/test_village.tscn", "plaza")


func _world_transition_service() -> Variant:
	return get_node_or_null("/root/WorldTransitionService")


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
