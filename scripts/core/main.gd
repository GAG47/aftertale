extends Node

const RegionLocationGraphCompilerScript := preload("res://scripts/systems/regions/region_location_graph_compiler.gd")
const LocationGraphRuntimeAdapterScript := preload("res://scripts/systems/regions/location_graph_runtime_adapter.gd")
const SNAPSHOT_RUNTIME_LOCATION_SCENE := preload("res://scenes/locations/snapshot_runtime_location.tscn")

const DEFAULT_REGION_INPUT_PATHS := [
	"res://data/regions/frontier_town_region.json",
	"res://data/regions/frontier_forest_region.json",
]
const DEFAULT_EDGE_PROFILE_PATH := "res://data/location_graph/edge_contract_profiles/default.json"
const DEFAULT_GRAPH_ID := "graph.frontier.overworld.lg_0001"

@onready var world_root: Node = $WorldRoot
@onready var ui_root: UIRoot = $UILayer/UIRoot

var _runtime_adapter: RefCounted
var _runtime_location_scene: Control


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
	_clear_snapshot_runtime()
	var world_service: Variant = _world_transition_service()
	if world_service != null:
		world_service.reset_world()

	var compile_result: Dictionary = _compile_default_region_location_graph()
	if not bool(compile_result.get("success", false)):
		var edge_contract_result: Dictionary = compile_result.get("edge_contract_result", {}) as Dictionary
		if not edge_contract_result.is_empty():
			ui_root.set_raw_debug_data(edge_contract_result)
		else:
			var location_node_results: Array = compile_result.get("location_node_results", []) as Array
			if not location_node_results.is_empty() and location_node_results[0] is Dictionary:
				ui_root.set_raw_debug_data(location_node_results[0] as Dictionary)
			else:
				var location_node_result: Dictionary = compile_result.get("location_node_result", {}) as Dictionary
				if not location_node_result.is_empty():
					ui_root.set_raw_debug_data(location_node_result)
		push_error("Region Location Graph compile failed: %s" % str(compile_result.get("errors", [])))
		return
	var location_graph_snapshot: Dictionary = compile_result.get("location_graph_snapshot", {}) as Dictionary
	if location_graph_snapshot.is_empty():
		push_error("Region Location Graph compiler returned success without a LocationGraphSnapshot.")
		return
	ui_root.set_raw_debug_data(location_graph_snapshot)

	GameState.start_new_session()
	NpcScheduleSystem.reset_schedule_state()
	PartySystem.reset_party("debug_player")
	GameState.set_scene_context("boot", "none")

	TimeManager.reset()
	TimeManager.set_paused(false)

	_runtime_location_scene = SNAPSHOT_RUNTIME_LOCATION_SCENE.instantiate() as Control
	if _runtime_location_scene == null:
		push_error("Snapshot Runtime Location scene could not be instantiated.")
		return
	ui_root.add_child(_runtime_location_scene)
	ui_root.set_snapshot_runtime_active(true)
	_runtime_adapter = LocationGraphRuntimeAdapterScript.new()
	var runtime_result: Dictionary = _runtime_adapter.load_snapshot(location_graph_snapshot)
	if not bool(runtime_result.get("success", false)):
		var error_text := "; ".join(runtime_result.get("errors", []) as Array[String])
		_runtime_location_scene.show_load_error(
			str(location_graph_snapshot.get("graph_id", "")),
			str(location_graph_snapshot.get("snapshot_id", "")),
			error_text
		)
		push_error("Snapshot Runtime Adapter load failed: %s" % error_text)
		return
	var bind_result: Dictionary = _runtime_location_scene.bind_adapter(_runtime_adapter)
	if not bool(bind_result.get("success", false)):
		push_error("Snapshot Runtime Location scene bind failed: %s" % str(bind_result.get("errors", [])))
		return
	GameState.set_scene_context("snapshot_runtime_location", str(runtime_result.get("current_location_id", "")))


func _compile_default_region_location_graph() -> Dictionary:
	var region_inputs: Array[Dictionary] = []
	for resource_path in DEFAULT_REGION_INPUT_PATHS:
		var region_input: Dictionary = DefinitionLoader.load_json_resource(resource_path, "region input")
		if region_input.is_empty():
			return {
				"success": false,
				"errors": ["Default RegionInput is missing or invalid JSON: %s" % resource_path],
				"warnings": [],
			}
		region_inputs.append(region_input)
	var compiler: RefCounted = RegionLocationGraphCompilerScript.new()
	return compiler.compile_to_location_graph_result(region_inputs, DEFAULT_EDGE_PROFILE_PATH, DEFAULT_GRAPH_ID)


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
	_clear_snapshot_runtime()
	SceneLoader.unload_current_scene()
	GameState.set_scene_context("title", "none")
	TimeManager.set_paused(true)
	ui_root.open_title_screen()


func _on_new_game_requested() -> void:
	ui_root.clear_transient_ui()
	_start_new_game()


func _on_quit_game_requested() -> void:
	get_tree().quit()


func is_snapshot_runtime_active() -> bool:
	return (
		_runtime_adapter != null
		and _runtime_adapter.is_loaded()
		and _runtime_location_scene != null
		and is_instance_valid(_runtime_location_scene)
	)


func get_snapshot_runtime_current_location_id() -> String:
	if _runtime_adapter == null or not _runtime_adapter.is_loaded():
		return ""
	return str(_runtime_adapter.current_location_id)


func _clear_snapshot_runtime() -> void:
	if ui_root != null:
		ui_root.set_snapshot_runtime_active(false)
	if _runtime_location_scene != null and is_instance_valid(_runtime_location_scene):
		if _runtime_location_scene.get_parent() != null:
			_runtime_location_scene.get_parent().remove_child(_runtime_location_scene)
		_runtime_location_scene.queue_free()
	_runtime_location_scene = null
	if _runtime_adapter != null:
		_runtime_adapter.reset()
	_runtime_adapter = null
