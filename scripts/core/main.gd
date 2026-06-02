extends Node

@onready var world_root: Node = $WorldRoot
@onready var ui_root: UIRoot = $UILayer/UIRoot


func _ready() -> void:
	SceneLoader.configure(world_root)

	InputManager.debug_toggle_requested.connect(_on_debug_toggle_requested)
	InputManager.cancel_requested.connect(_on_cancel_requested)
	InputManager.save_requested.connect(_on_save_requested)
	InputManager.load_requested.connect(_on_load_requested)

	ui_root.bind_managers(GameState, SceneLoader, TimeManager, InputManager, ActionSystem, DialogueRunner, QuestSystem, RelationSystem)

	GameState.start_new_session()
	PartySystem.reset_party("debug_player")
	GameState.set_scene_context("boot", "none")

	TimeManager.reset()
	TimeManager.set_paused(false)

	SceneLoader.load_location("res://scenes/locations/test_field.tscn", "start")


func _on_debug_toggle_requested() -> void:
	ui_root.toggle_debug_panel()


func _on_save_requested() -> void:
	SaveManager.save_game()


func _on_load_requested() -> void:
	SaveManager.load_game()


func _on_cancel_requested() -> void:
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
