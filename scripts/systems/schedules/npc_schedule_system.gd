extends Node

signal schedule_applied(character_id: String, location_id: String, entry_id: String)
signal offscreen_settled(location_id: String, from_absolute_minutes: int, to_absolute_minutes: int)

var active_location_root: Node
var active_location_data_path: String = ""
var active_location_registered_minutes: int = 0
var offscreen_states: Dictionary = {}


func _ready() -> void:
	TimeManager.time_changed.connect(_on_time_changed)


func register_location_root(location_root: Node) -> void:
	if location_root == null or not is_instance_valid(location_root):
		return

	active_location_root = location_root
	active_location_data_path = str(location_root.get("location_data_path"))
	active_location_registered_minutes = TimeManager.get_absolute_minutes()
	_apply_current_location_schedule()


func unregister_location_root(location_root: Node) -> void:
	if active_location_root == null:
		return

	if not is_instance_valid(active_location_root) or active_location_root == location_root:
		if not active_location_data_path.is_empty():
			settle_offscreen_location(active_location_data_path, active_location_registered_minutes, TimeManager.get_absolute_minutes())
		active_location_root = null
		active_location_data_path = ""
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


func settle_offscreen_location(location_data_path: String, from_absolute_minutes: int, to_absolute_minutes: int) -> Dictionary:
	var location_data: Dictionary = _read_json_resource(location_data_path)
	if location_data.is_empty():
		return {}

	var location_id: String = str(location_data.get("id", ""))
	var character_states: Array[Dictionary] = []
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

		character_states.append({
			"character_id": str(spawn_data.get("id", character_definition.get("id", ""))),
			"location_id": str(active_entry.get("location_id", location_id)),
			"grid_position": active_entry.get("grid_position", {}),
			"facing": str(active_entry.get("facing", character_definition.get("facing", "down"))),
			"activity": str(active_entry.get("activity", "idle")),
			"entry_id": str(active_entry.get("id", "")),
		})

	var summary: Dictionary = {
		"location_id": location_id,
		"from_absolute_minutes": from_absolute_minutes,
		"to_absolute_minutes": to_absolute_minutes,
		"characters": character_states,
	}
	offscreen_states[location_id] = summary
	offscreen_settled.emit(location_id, from_absolute_minutes, to_absolute_minutes)
	return summary


func get_offscreen_summary(location_id: String = "") -> Dictionary:
	if location_id.is_empty():
		return offscreen_states.duplicate(true)

	return offscreen_states.get(location_id, {}) as Dictionary


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
