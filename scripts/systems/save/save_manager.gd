extends Node

signal game_saved(save_path: String)
signal game_loaded(save_path: String)
signal save_failed(save_path: String, reason: String)
signal load_failed(save_path: String, reason: String)

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://saves/slot_1.json"
const SAVE_DIR := "user://saves"
const DEFAULT_WORLD_ID := "default_world"
const GeneratedSettlementStoreScript := preload("res://scripts/systems/settlements/generated_settlement_store.gd")

var active_save_path: String = DEFAULT_SAVE_PATH
var active_save_slot_id: String = "slot_1"
var active_world_id: String = DEFAULT_WORLD_ID
var last_save_path: String = DEFAULT_SAVE_PATH
var last_message: String = ""
var generated_settlements: Dictionary = {}


func save_game(save_path: String = "") -> ActionResult:
	save_path = _normalized_save_path(save_path)
	if not _can_save_in_current_mode():
		return _fail_save(save_path, "只能在对话和战斗之外保存。")

	var active_scene: Node = _get_active_scene()
	if active_scene == null:
		return _fail_save(save_path, "没有可保存的当前场景。")

	configure_active_save_context(save_path, active_world_id, false)
	_persist_current_controlled_character()

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"active_save_path": active_save_path,
		"active_save_slot_id": active_save_slot_id,
		"active_world_id": active_world_id,
		"scene": _build_scene_state(active_scene),
		"game_state": GameState.get_save_state(),
		"time": TimeManager.get_save_state(),
		"quests": QuestSystem.get_save_state(),
		"party": PartySystem.get_save_state(),
		"relations": RelationSystem.get_save_state(),
		"crops": CropSystem.get_save_state(),
		"business": BusinessSystem.get_save_state(),
		"npc_schedules": NpcScheduleSystem.get_save_state(),
		"generated_settlements": generated_settlements.duplicate(true),
	}

	var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path).get_base_dir())
	if dir_error != OK:
		return _fail_save(save_path, "无法创建存档目录。")

	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _fail_save(save_path, "无法打开存档文件进行写入。")

	file.store_string(JSON.stringify(save_data, "\t"))
	configure_active_save_context(save_path, active_world_id, false)
	last_message = "游戏已保存。"
	game_saved.emit(save_path)

	var result: ActionResult = ActionResult.succeeded("SaveGame", GameState.player_id, {
		"save_path": save_path,
	})
	result.add_world_change({
		"type": "game_saved",
		"save_path": save_path,
		"version": SAVE_VERSION,
	})
	result.add_feedback("游戏已保存。")
	ActionSystem.publish_result(result)
	return result


func load_game(save_path: String = "") -> ActionResult:
	save_path = _normalized_save_path(save_path)
	if not FileAccess.file_exists(save_path):
		return _fail_load(save_path, "存档文件不存在。")

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _fail_load(save_path, "无法打开存档文件。")

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail_load(save_path, "存档文件不是有效的 JSON。")

	var save_data: Dictionary = parsed as Dictionary
	var version: int = int(save_data.get("version", 0))
	if version != SAVE_VERSION:
		return _fail_load(save_path, "不支持的存档版本：%d。" % version)

	configure_active_save_context(save_path, _world_id_from_save_data(save_data), false)
	apply_generated_settlement_index(save_data.get("generated_settlements", {}) as Dictionary, false)
	clear_generated_runtime_caches()

	DialogueRunner.clear_dialogue_state()
	BattleSystem.clear_battle_state()
	GameState.apply_save_state(save_data.get("game_state", {}) as Dictionary)
	TimeManager.apply_save_state(save_data.get("time", {}) as Dictionary)
	QuestSystem.apply_save_state(save_data.get("quests", {}) as Dictionary)
	PartySystem.apply_save_state(save_data.get("party", {}) as Dictionary)
	RelationSystem.apply_save_state(save_data.get("relations", {}) as Dictionary)
	CropSystem.apply_save_state(save_data.get("crops", {}) as Dictionary)
	BusinessSystem.apply_save_state(save_data.get("business", {}) as Dictionary)
	NpcScheduleSystem.apply_save_state(save_data.get("npc_schedules", {}) as Dictionary)

	var scene_state: Dictionary = save_data.get("scene", {}) as Dictionary
	var scene_path: String = str(scene_state.get("scene_path", ""))
	if scene_path.is_empty():
		return _fail_load(save_path, "存档缺少场景路径。")

	var entrance_id: String = str(scene_state.get("entrance_id", ""))
	SceneLoader.set_save_runtime_on_next_unload(false)
	var load_error: Error = SceneLoader.load_location(scene_path, entrance_id)
	if load_error != OK:
		SceneLoader.set_save_runtime_on_next_unload(true)
		return _fail_load(save_path, "无法加载存档场景。")

	_restore_controlled_character(scene_state)
	GameState.set_mode(GameState.GameMode.EXPLORATION)
	configure_active_save_context(save_path, active_world_id, false)
	last_message = "游戏已读取。"
	game_loaded.emit(save_path)

	var result: ActionResult = ActionResult.succeeded("LoadGame", GameState.player_id, {
		"save_path": save_path,
	})
	result.add_world_change({
		"type": "game_loaded",
		"save_path": save_path,
		"version": version,
	})
	result.add_feedback("游戏已读取。")
	ActionSystem.publish_result(result)
	return result


func has_save(save_path: String = "") -> bool:
	save_path = _normalized_save_path(save_path)
	return FileAccess.file_exists(save_path)


func configure_active_save_context(save_path: String = DEFAULT_SAVE_PATH, world_id: String = DEFAULT_WORLD_ID, clear_runtime_cache: bool = true) -> void:
	var normalized_path := _normalized_save_path(save_path, false)
	var next_slot_id := _safe_id(_slot_id_from_save_path(normalized_path))
	if next_slot_id.is_empty():
		next_slot_id = "slot_1"
	var next_world_id := _safe_id(world_id)
	if next_world_id.is_empty():
		next_world_id = DEFAULT_WORLD_ID

	var changed := normalized_path != active_save_path or next_slot_id != active_save_slot_id or next_world_id != active_world_id
	active_save_path = normalized_path
	active_save_slot_id = next_slot_id
	active_world_id = next_world_id
	last_save_path = active_save_path
	if changed and clear_runtime_cache:
		clear_generated_runtime_caches()


func reset_active_save_context(save_path: String = DEFAULT_SAVE_PATH, world_id: String = DEFAULT_WORLD_ID) -> void:
	configure_active_save_context(save_path, world_id, false)
	clear_generated_settlement_index(false)
	clear_generated_runtime_caches()


func get_active_save_path() -> String:
	return active_save_path


func get_active_save_slot_id() -> String:
	return active_save_slot_id


func get_active_world_id() -> String:
	return active_world_id


func get_current_slot_id() -> String:
	return active_save_slot_id


func get_generated_root_path() -> String:
	return "%s/%s/worlds/%s/generated" % [SAVE_DIR, active_save_slot_id, active_world_id]


func register_generated_settlement(settlement_id: String, snapshot_path: String, metadata: Variant = {}, generator_version: String = "") -> void:
	if settlement_id.is_empty() or snapshot_path.is_empty():
		return

	var record: Dictionary = {}
	if metadata is Dictionary:
		record = (metadata as Dictionary).duplicate(true)
	else:
		record = {
			"schema_version": int(metadata),
			"generator_version": generator_version,
		}

	generated_settlements[settlement_id] = {
		"settlement_id": settlement_id,
		"snapshot_path": snapshot_path,
		"schema_version": int(record.get("schema_version", 0)),
		"generator_version": str(record.get("generator_version", "")),
		"policy_id": str(record.get("policy_id", "")),
		"seed": int(record.get("seed", 0)),
		"exterior_location_id": str(record.get("exterior_location_id", "")),
		"snapshot_id": str(record.get("snapshot_id", "")),
		"active_save_slot_id": active_save_slot_id,
		"active_world_id": active_world_id,
	}


func get_generated_settlement_record(settlement_id: String) -> Dictionary:
	return (generated_settlements.get(settlement_id, {}) as Dictionary).duplicate(true)


func get_generated_settlement_index() -> Dictionary:
	return generated_settlements.duplicate(true)


func unregister_generated_settlement(settlement_id: String, clear_runtime_cache: bool = true) -> void:
	if settlement_id.is_empty():
		return
	generated_settlements.erase(settlement_id)
	if clear_runtime_cache:
		clear_generated_runtime_caches()


func apply_generated_settlement_index(index: Dictionary, clear_runtime_cache: bool = true) -> void:
	generated_settlements = index.duplicate(true)
	if clear_runtime_cache:
		clear_generated_runtime_caches()


func clear_generated_settlement_index(clear_runtime_cache: bool = true) -> void:
	generated_settlements.clear()
	if clear_runtime_cache:
		clear_generated_runtime_caches()


func clear_generated_runtime_caches() -> void:
	if DefinitionLoader != null and DefinitionLoader.has_method("clear_generated_runtime_cache"):
		DefinitionLoader.clear_generated_runtime_cache()
	if GeneratedSettlementStoreScript != null:
		GeneratedSettlementStoreScript.clear_runtime_cache()


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


func _normalized_save_path(save_path: String, prefer_active: bool = true) -> String:
	if not save_path.is_empty():
		return save_path
	if prefer_active and not active_save_path.is_empty():
		return active_save_path
	return DEFAULT_SAVE_PATH


func _world_id_from_save_data(save_data: Dictionary) -> String:
	var world_id := str(save_data.get("active_world_id", save_data.get("world_id", "")))
	if world_id.is_empty():
		return DEFAULT_WORLD_ID
	return world_id


func _slot_id_from_save_path(save_path: String) -> String:
	var file_name := save_path.get_file()
	if file_name.is_empty():
		return "slot_1"
	var dot_index := file_name.rfind(".")
	if dot_index > 0:
		file_name = file_name.substr(0, dot_index)
	if file_name.is_empty():
		return "slot_1"
	return file_name


func _safe_id(value: String) -> String:
	var result := value.strip_edges().to_lower()
	for character in [" ", "/", "\\", ":", ".", "-", "\t", "\n"]:
		result = result.replace(character, "_")
	while result.find("__") >= 0:
		result = result.replace("__", "_")
	return result


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
