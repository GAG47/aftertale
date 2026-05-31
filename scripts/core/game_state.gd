extends Node

signal session_started(session_id: String)
signal mode_changed(previous_mode: int, new_mode: int)
signal scene_context_changed(scene_id: String, location_id: String)
signal world_fact_changed(key: String, value: Variant)

enum GameMode {
	BOOT,
	EXPLORATION,
	DIALOGUE,
	COMBAT,
	TRADE,
	CRAFT,
	MANAGEMENT,
	MENU,
	PAUSED,
}

var session_id: String = ""
var current_mode: GameMode = GameMode.BOOT
var current_scene_id: String = ""
var current_location_id: String = ""
var player_id: String = ""
var flags: Dictionary = {}
var world_facts: Dictionary = {}
var character_runtime_states: Dictionary = {}
var removed_location_objects: Dictionary = {}
var removed_location_characters: Dictionary = {}


func start_new_session(new_session_id: String = "") -> void:
	session_id = new_session_id
	if session_id.is_empty():
		session_id = Time.get_datetime_string_from_system(false, true)

	flags.clear()
	world_facts.clear()
	character_runtime_states.clear()
	removed_location_objects.clear()
	removed_location_characters.clear()
	set_mode(GameMode.EXPLORATION)
	session_started.emit(session_id)


func set_mode(new_mode: GameMode) -> void:
	if current_mode == new_mode:
		return

	var previous_mode := current_mode
	current_mode = new_mode
	mode_changed.emit(previous_mode, current_mode)


func get_mode_label(mode: int = -1) -> String:
	if mode == -1:
		mode = current_mode

	match mode:
		GameMode.BOOT:
			return "启动"
		GameMode.EXPLORATION:
			return "探索"
		GameMode.DIALOGUE:
			return "对话"
		GameMode.COMBAT:
			return "战斗"
		GameMode.TRADE:
			return "交易"
		GameMode.CRAFT:
			return "制作"
		GameMode.MANAGEMENT:
			return "经营"
		GameMode.MENU:
			return "菜单"
		GameMode.PAUSED:
			return "暂停"
		_:
			return "未知"


func set_scene_context(scene_id: String, location_id: String = "") -> void:
	current_scene_id = scene_id
	current_location_id = location_id
	scene_context_changed.emit(current_scene_id, current_location_id)


func set_flag(key: String, value: bool = true) -> void:
	flags[key] = value


func has_flag(key: String) -> bool:
	return flags.get(key, false)


func set_world_fact(key: String, value: Variant) -> void:
	world_facts[key] = value
	world_fact_changed.emit(key, value)


func get_world_fact(key: String, default_value: Variant = null) -> Variant:
	return world_facts.get(key, default_value)


func is_session_active() -> bool:
	return not session_id.is_empty()


func get_save_state() -> Dictionary:
	return {
		"session_id": session_id,
		"current_scene_id": current_scene_id,
		"current_location_id": current_location_id,
		"player_id": player_id,
		"flags": flags.duplicate(true),
		"world_facts": world_facts.duplicate(true),
		"character_runtime_states": character_runtime_states.duplicate(true),
		"removed_location_objects": removed_location_objects.duplicate(true),
		"removed_location_characters": removed_location_characters.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	session_id = str(state.get("session_id", session_id))
	current_scene_id = str(state.get("current_scene_id", ""))
	current_location_id = str(state.get("current_location_id", ""))
	player_id = str(state.get("player_id", ""))
	flags = (state.get("flags", {}) as Dictionary).duplicate(true)
	world_facts = (state.get("world_facts", {}) as Dictionary).duplicate(true)
	character_runtime_states = (state.get("character_runtime_states", {}) as Dictionary).duplicate(true)
	removed_location_objects = (state.get("removed_location_objects", {}) as Dictionary).duplicate(true)
	removed_location_characters = (state.get("removed_location_characters", {}) as Dictionary).duplicate(true)


func save_character_runtime(character: Node) -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.has_method("get_runtime_state"):
		return

	var character_id: String = str(character.get("character_id"))
	if character_id.is_empty():
		return

	character_runtime_states[character_id] = character.get_runtime_state()


func get_character_runtime(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}

	return (character_runtime_states.get(character_id, {}) as Dictionary).duplicate(true)


func mark_location_object_removed(location_id: String, object_id: String) -> void:
	_mark_removed_id(removed_location_objects, location_id, object_id)


func is_location_object_removed(location_id: String, object_id: String) -> bool:
	return _is_removed_id(removed_location_objects, location_id, object_id)


func mark_location_character_removed(location_id: String, character_id: String) -> void:
	_mark_removed_id(removed_location_characters, location_id, character_id)


func is_location_character_removed(location_id: String, character_id: String) -> bool:
	return _is_removed_id(removed_location_characters, location_id, character_id)


func _mark_removed_id(store: Dictionary, location_id: String, entry_id: String) -> void:
	if location_id.is_empty() or entry_id.is_empty():
		return

	var removed_ids: Dictionary = store.get(location_id, {}) as Dictionary
	removed_ids[entry_id] = true
	store[location_id] = removed_ids


func _is_removed_id(store: Dictionary, location_id: String, entry_id: String) -> bool:
	if location_id.is_empty() or entry_id.is_empty():
		return false

	var removed_ids: Dictionary = store.get(location_id, {}) as Dictionary
	return bool(removed_ids.get(entry_id, false))
