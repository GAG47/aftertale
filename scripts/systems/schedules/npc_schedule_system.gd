extends Node

signal schedule_applied(character_id: String, location_id: String, entry_id: String)
signal offscreen_settled(location_id: String, from_absolute_minutes: int, to_absolute_minutes: int)

var active_location_root: Node
var active_location_data_path: String = ""
var active_location_id: String = ""
var active_location_registered_minutes: int = 0
var offscreen_states: Dictionary = {}
var last_settled_minutes_by_location: Dictionary = {}
var _skip_next_unregister_settle: bool = false


func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)


func register_location_root(location_root: Node) -> void:
	if location_root == null or not is_instance_valid(location_root):
		return

	var location_id := _location_id_from_root(location_root)
	_settle_location_before_entry(location_id, str(location_root.get("location_data_path")))
	active_location_root = location_root
	active_location_data_path = str(location_root.get("location_data_path"))
	active_location_id = location_id
	active_location_registered_minutes = TimeManager.get_absolute_minutes()
	_apply_current_location_schedule()


func unregister_location_root(location_root: Node) -> void:
	if active_location_root == null:
		return

	if not is_instance_valid(active_location_root) or active_location_root == location_root:
		if _skip_next_unregister_settle:
			_skip_next_unregister_settle = false
		elif not active_location_data_path.is_empty() or not active_location_id.is_empty():
			settle_offscreen_location(active_location_data_path, active_location_registered_minutes, TimeManager.get_absolute_minutes(), active_location_id)
		active_location_root = null
		active_location_data_path = ""
		active_location_id = ""
		active_location_registered_minutes = 0


func get_active_entry(schedule: Array, absolute_minutes: int) -> Dictionary:
	if schedule.is_empty():
		return {}

	var minute_of_day: int = absolute_minutes % TimeManager.MINUTES_PER_DAY
	for entry_value in schedule:
		var entry: Dictionary = entry_value as Dictionary
		var start_minute: int = TimeManager.parse_time_to_minute(str(entry.get("start", "")))
		var end_minute: int = TimeManager.parse_time_to_minute(str(entry.get("end", "")))
		if start_minute < 0 or end_minute < 0:
			continue

		var active: bool = false
		if start_minute <= end_minute:
			active = minute_of_day >= start_minute and minute_of_day <= end_minute
		else:
			active = minute_of_day >= start_minute or minute_of_day <= end_minute

		if active:
			return entry.duplicate(true)

	return {}


func settle_offscreen_location(location_data_path: String, from_absolute_minutes: int, to_absolute_minutes: int, resolved_location_id: String = "") -> Dictionary:
	var location_data: Dictionary = _location_data_for_schedule(resolved_location_id, location_data_path)
	if location_data.is_empty():
		return {}

	var location_id: String = str(location_data.get("id", ""))
	var character_states: Array[Dictionary] = []
	var states_by_location: Dictionary = {}
	var character_rows: Array = location_data.get("characters", []) as Array
	for character_spawn_value in character_rows:
		var spawn_data: Dictionary = character_spawn_value as Dictionary
		if bool(spawn_data.get("is_player_controlled", false)):
			continue

		var character_definition: Dictionary = _read_json_resource(str(spawn_data.get("source", "")))
		if character_definition.is_empty() or bool(character_definition.get("is_player_controlled", false)):
			continue

		var schedule: Array = _get_schedule(character_definition, spawn_data)
		var active_entry: Dictionary = get_active_entry(schedule, to_absolute_minutes)
		if active_entry.is_empty():
			continue

		var scheduled_location_id: String = str(active_entry.get("location_id", location_id))
		var scheduled_location_data: Dictionary = location_data
		if scheduled_location_id != location_id:
			scheduled_location_data = _read_location_data_by_id(scheduled_location_id)
		var target: Dictionary = _resolve_schedule_target(active_entry, scheduled_location_data)
		var target_position: Dictionary = target.get("grid_position", active_entry.get("grid_position", {})) as Dictionary
		if target_position.is_empty():
			push_warning("Skipping offscreen schedule state without grid_position: %s -> %s/%s" % [
				str(spawn_data.get("id", character_definition.get("id", ""))),
				scheduled_location_id,
				str(active_entry.get("anchor_id", "")),
			])
			continue
		var character_state := {
			"character_id": str(spawn_data.get("id", character_definition.get("id", ""))),
			"location_id": scheduled_location_id,
			"anchor_id": str(active_entry.get("anchor_id", "")),
			"grid_position": target_position,
			"facing": str(target.get("facing", active_entry.get("facing", character_definition.get("facing", "down")))),
			"activity_type": str(active_entry.get("activity_type", "idle")),
			"activity": str(active_entry.get("activity", "idle")),
			"entry_id": str(active_entry.get("id", "")),
			"movement": str(active_entry.get("movement", "walk")),
		}
		character_states.append(character_state)
		if not states_by_location.has(scheduled_location_id):
			states_by_location[scheduled_location_id] = []
		(states_by_location[scheduled_location_id] as Array).append(character_state)

	var summary: Dictionary = {
		"location_id": location_id,
		"from_absolute_minutes": from_absolute_minutes,
		"to_absolute_minutes": to_absolute_minutes,
		"characters": character_states,
	}
	offscreen_states[location_id] = summary
	last_settled_minutes_by_location[location_id] = to_absolute_minutes
	for target_location_id_value in states_by_location.keys():
		var target_location_id := str(target_location_id_value)
		offscreen_states[target_location_id] = {
			"location_id": target_location_id,
			"from_absolute_minutes": from_absolute_minutes,
			"to_absolute_minutes": to_absolute_minutes,
			"characters": (states_by_location[target_location_id] as Array).duplicate(true),
		}
		last_settled_minutes_by_location[target_location_id] = to_absolute_minutes
	offscreen_settled.emit(location_id, from_absolute_minutes, to_absolute_minutes)
	return summary


func get_offscreen_character_state(location_id: String, character_id: String) -> Dictionary:
	if location_id.is_empty() or character_id.is_empty():
		return {}

	var summary: Dictionary = get_offscreen_summary(location_id)
	var character_rows: Array = summary.get("characters", []) as Array
	for character_value in character_rows:
		var character_state: Dictionary = character_value as Dictionary
		if str(character_state.get("character_id", "")) == character_id:
			return character_state.duplicate(true)

	return {}


func get_offscreen_summary(location_id: String = "") -> Dictionary:
	if location_id.is_empty():
		return offscreen_states.duplicate(true)

	return offscreen_states.get(location_id, {}) as Dictionary


func get_save_state() -> Dictionary:
	return {
		"offscreen_states": offscreen_states.duplicate(true),
		"last_settled_minutes_by_location": last_settled_minutes_by_location.duplicate(true),
	}


func apply_save_state(state: Dictionary) -> void:
	offscreen_states = (state.get("offscreen_states", {}) as Dictionary).duplicate(true)
	last_settled_minutes_by_location = (state.get("last_settled_minutes_by_location", {}) as Dictionary).duplicate(true)
	_skip_next_unregister_settle = true


func reset_schedule_state() -> void:
	active_location_root = null
	active_location_data_path = ""
	active_location_id = ""
	active_location_registered_minutes = 0
	offscreen_states.clear()
	last_settled_minutes_by_location.clear()
	_skip_next_unregister_settle = false


func _on_time_changed(_day: int, _hour: int, _minute: int) -> void:
	_apply_current_location_schedule()


func _apply_current_location_schedule() -> void:
	if GameState.current_mode == GameState.GameMode.COMBAT:
		return

	if active_location_root == null:
		return

	if not is_instance_valid(active_location_root):
		active_location_root = null
		active_location_data_path = ""
		active_location_registered_minutes = 0
		return

	if not active_location_root.has_method("apply_current_schedule"):
		return

	active_location_root.apply_current_schedule(TimeManager.get_absolute_minutes())


func _get_schedule(character_definition: Dictionary, spawn_data: Dictionary) -> Array:
	if spawn_data.has("schedule"):
		return spawn_data.get("schedule", []) as Array

	return character_definition.get("schedule", []) as Array


func _read_json_resource(resource_path: String) -> Dictionary:
	return DefinitionLoader.load_json_resource(resource_path)


func _settle_location_before_entry(location_id: String, location_data_path: String) -> void:
	if location_id.is_empty() and location_data_path.is_empty():
		return

	var location_data: Dictionary = _location_data_for_schedule(location_id, location_data_path)
	if location_data.is_empty():
		return

	location_id = str(location_data.get("id", location_id))
	if location_id.is_empty():
		return

	var current_minutes: int = TimeManager.get_absolute_minutes()
	var last_settled_minutes: int = int(last_settled_minutes_by_location.get(location_id, -1))
	if last_settled_minutes < 0 or last_settled_minutes >= current_minutes:
		return

	settle_offscreen_location(location_data_path, last_settled_minutes, current_minutes, location_id)


func _location_data_for_schedule(location_id: String, location_data_path: String) -> Dictionary:
	var world_service: Variant = _world_transition_service()
	if world_service != null and world_service.is_world_active() and not location_id.is_empty():
		var runtime_data: Dictionary = world_service.get_registered_location_data(location_id)
		if not runtime_data.is_empty():
			return runtime_data
		if not world_service.get_location_spec(location_id).is_empty():
			return {}
	var location_data: Dictionary = DefinitionLoader.resolve_location_by_id(location_id) if not location_id.is_empty() else {}
	if location_data.is_empty():
		location_data = DefinitionLoader.load_resolved_location(location_data_path)
	return location_data


func _world_transition_service() -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("WorldTransitionService")


func _location_id_from_root(location_root: Node) -> String:
	if location_root == null or not is_instance_valid(location_root):
		return ""
	if not location_root.has_method("get_location_summary"):
		return ""
	var summary: Dictionary = location_root.get_location_summary()
	return str(summary.get("id", ""))


func _read_location_data_by_id(location_id: String) -> Dictionary:
	if location_id.is_empty():
		return {}

	return DefinitionLoader.resolve_location_by_id(location_id)


func _resolve_schedule_target(entry: Dictionary, location_data: Dictionary) -> Dictionary:
	var target: Dictionary = {}
	var anchor_id: String = str(entry.get("anchor_id", ""))
	if not anchor_id.is_empty() and not location_data.is_empty():
		var anchor: Dictionary = _get_anchor(location_data, anchor_id)
		if not anchor.is_empty():
			var anchor_position: Dictionary = anchor.get("grid_position", {}) as Dictionary
			if not anchor_position.is_empty():
				target["grid_position"] = anchor_position.duplicate(true)
			if anchor.has("facing"):
				target["facing"] = str(anchor.get("facing", "down"))

	if not target.has("grid_position") and entry.has("grid_position"):
		target["grid_position"] = (entry.get("grid_position", {}) as Dictionary).duplicate(true)
	if entry.has("facing"):
		target["facing"] = str(entry.get("facing", "down"))

	return target


func _get_anchor(location_data: Dictionary, anchor_id: String) -> Dictionary:
	var anchor_rows: Array = location_data.get("anchors", []) as Array
	for anchor_value in anchor_rows:
		var anchor: Dictionary = anchor_value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			return anchor

	return {}
