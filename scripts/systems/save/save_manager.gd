extends Node

signal game_saved(save_path: String)
signal game_loaded(save_path: String)
signal save_failed(save_path: String, reason: String)
signal load_failed(save_path: String, reason: String)

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://saves/slot_1.json"
const SAVE_DIR := "user://saves"

var last_save_path: String = DEFAULT_SAVE_PATH
var last_message: String = ""


func save_game(save_path: String = DEFAULT_SAVE_PATH) -> ActionResult:
	if not _can_save_in_current_mode():
		return _fail_save(save_path, "Save is only available outside dialogue and combat.")

	var active_scene: Node = _get_active_scene()
	if active_scene == null:
		return _fail_save(save_path, "No active scene to save.")

	_persist_current_controlled_character()

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"scene": _build_scene_state(active_scene),
		"game_state": GameState.get_save_state(),
		"time": TimeManager.get_save_state(),
		"quests": QuestSystem.get_save_state(),
		"relations": RelationSystem.get_save_state(),
		"crops": CropSystem.get_save_state(),
		"business": BusinessSystem.get_save_state(),
	}

	var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	if dir_error != OK:
		return _fail_save(save_path, "Could not create save directory.")

	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _fail_save(save_path, "Could not open save file for writing.")

	file.store_string(JSON.stringify(save_data, "\t"))
	last_save_path = save_path
	last_message = "Saved game."
	game_saved.emit(save_path)

	var result: ActionResult = ActionResult.succeeded("SaveGame", GameState.player_id, {
		"save_path": save_path,
	})
	result.add_world_change({
		"type": "game_saved",
		"save_path": save_path,
		"version": SAVE_VERSION,
	})
	result.add_feedback("Game saved.")
	ActionSystem.publish_result(result)
	return result


func load_game(save_path: String = DEFAULT_SAVE_PATH) -> ActionResult:
	if not FileAccess.file_exists(save_path):
		return _fail_load(save_path, "Save file does not exist.")

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _fail_load(save_path, "Could not open save file.")

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail_load(save_path, "Save file is not valid JSON.")

	var save_data: Dictionary = parsed as Dictionary
	var version: int = int(save_data.get("version", 0))
	if version != SAVE_VERSION:
		return _fail_load(save_path, "Unsupported save version: %d." % version)

	DialogueRunner.clear_dialogue_state()
	BattleSystem.clear_battle_state()
	GameState.apply_save_state(save_data.get("game_state", {}) as Dictionary)
	TimeManager.apply_save_state(save_data.get("time", {}) as Dictionary)
	QuestSystem.apply_save_state(save_data.get("quests", {}) as Dictionary)
	RelationSystem.apply_save_state(save_data.get("relations", {}) as Dictionary)
	CropSystem.apply_save_state(save_data.get("crops", {}) as Dictionary)
	BusinessSystem.apply_save_state(save_data.get("business", {}) as Dictionary)

	var scene_state: Dictionary = save_data.get("scene", {}) as Dictionary
	var scene_path: String = str(scene_state.get("scene_path", ""))
	if scene_path.is_empty():
		return _fail_load(save_path, "Save file has no scene path.")

	var entrance_id: String = str(scene_state.get("entrance_id", ""))
	SceneLoader.set_save_runtime_on_next_unload(false)
	var load_error: Error = SceneLoader.load_location(scene_path, entrance_id)
	if load_error != OK:
		SceneLoader.set_save_runtime_on_next_unload(true)
		return _fail_load(save_path, "Could not load saved scene.")

	_restore_controlled_character(scene_state)
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	last_save_path = save_path
	last_message = "Loaded game."
	game_loaded.emit(save_path)

	var result: ActionResult = ActionResult.succeeded("LoadGame", GameState.player_id, {
		"save_path": save_path,
	})
	result.add_world_change({
		"type": "game_loaded",
		"save_path": save_path,
		"version": version,
	})
	result.add_feedback("Game loaded.")
	ActionSystem.publish_result(result)
	return result


func has_save(save_path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(save_path)


func _can_save_in_current_mode() -> bool:
	return GameState.current_mode != GameState.GameMode.DIALOGUE and GameState.current_mode != GameState.GameMode.COMBAT


func _build_scene_state(active_scene: Node) -> Dictionary:
	var controlled_state: Dictionary = {}
	if active_scene.has_method("get_controlled_character_state"):
		controlled_state = active_scene.get_controlled_character_state() as Dictionary

	return {
		"scene_path": SceneLoader.current_scene_path,
		"scene_id": GameState.current_scene_id,
		"location_id": GameState.current_location_id,
		"entrance_id": str(active_scene.get("entrance_id")) if active_scene.get("entrance_id") != null else "",
		"controlled_character": controlled_state,
	}


func _persist_current_controlled_character() -> void:
	var active_scene: Node = _get_active_scene()
	if active_scene == null or not active_scene.has_method("get_controlled_character"):
		return

	var controlled_character: Node = active_scene.get_controlled_character() as Node
	GameState.save_character_runtime(controlled_character)


func _restore_controlled_character(scene_state: Dictionary) -> void:
	var active_scene: Node = _get_active_scene()
	if active_scene == null or not active_scene.has_method("restore_controlled_character"):
		return

	var controlled_state: Dictionary = scene_state.get("controlled_character", {}) as Dictionary
	active_scene.restore_controlled_character(controlled_state)


func _get_active_scene() -> Node:
	if SceneLoader.current_scene == null or not is_instance_valid(SceneLoader.current_scene):
		return null

	return SceneLoader.current_scene


func _fail_save(save_path: String, reason: String) -> ActionResult:
	last_message = reason
	save_failed.emit(save_path, reason)
	var result: ActionResult = ActionResult.failed("SaveGame", GameState.player_id, reason, {
		"save_path": save_path,
	})
	ActionSystem.publish_result(result)
	return result


func _fail_load(save_path: String, reason: String) -> ActionResult:
	last_message = reason
	load_failed.emit(save_path, reason)
	var result: ActionResult = ActionResult.failed("LoadGame", GameState.player_id, reason, {
		"save_path": save_path,
	})
	ActionSystem.publish_result(result)
	return result
