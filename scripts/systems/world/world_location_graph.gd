class_name WorldLocationGraph
extends RefCounted

const WorldLocationSpecScript := preload("res://scripts/systems/world/world_location_spec.gd")

var world_id: String = ""
var world_seed: int = 0
var start_location_id: String = ""
var start_spawn_id: String = ""
var source_data: Dictionary = {}
var locations_by_id: Dictionary = {}
var spawns_by_location: Dictionary = {}
var exits_by_location_and_id: Dictionary = {}
var exits_by_id: Dictionary = {}
var child_locations_by_parent_id: Dictionary = {}
var exits_from_location_id: Dictionary = {}
var exits_to_location_id: Dictionary = {}


func configure(data: Dictionary) -> Array[String]:
	source_data = data.duplicate(true)
	world_id = str(data.get("world_id", data.get("id", "")))
	world_seed = int(data.get("world_seed", data.get("seed", 0)))
	start_location_id = str(data.get("start_location_id", ""))
	start_spawn_id = str(data.get("start_spawn_id", ""))
	locations_by_id.clear()
	spawns_by_location.clear()
	exits_by_location_and_id.clear()
	exits_by_id.clear()
	child_locations_by_parent_id.clear()
	exits_from_location_id.clear()
	exits_to_location_id.clear()

	var errors: Array[String] = []
	if world_id.is_empty():
		errors.append("world_id is missing")

	for location_value in (data.get("locations", []) as Array):
		var location_spec := WorldLocationSpecScript.normalize_location(location_value as Dictionary)
		var location_id := str(location_spec.get("location_id", ""))
		if location_id.is_empty():
			errors.append("location spec missing location_id")
			continue
		locations_by_id[location_id] = location_spec
		var parent_location_id := str(location_spec.get("parent_location_id", ""))
		if not parent_location_id.is_empty():
			var children: Array = child_locations_by_parent_id.get(parent_location_id, []) as Array
			children.append(location_id)
			child_locations_by_parent_id[parent_location_id] = children

	for spawn_value in (data.get("spawns", []) as Array):
		var spawn_spec := WorldLocationSpecScript.normalize_spawn(spawn_value as Dictionary)
		var location_id := str(spawn_spec.get("location_id", ""))
		var spawn_id := str(spawn_spec.get("spawn_id", ""))
		if location_id.is_empty() or spawn_id.is_empty():
			errors.append("spawn spec missing location_id or spawn_id")
			continue
		if str(spawn_spec.get("entrance_id", "")).is_empty():
			errors.append("spawn spec missing explicit entrance_id: %s/%s" % [location_id, spawn_id])
			continue
		if not locations_by_id.has(location_id):
			errors.append("spawn references unknown location: %s/%s" % [location_id, spawn_id])
			continue
		var spawns: Dictionary = spawns_by_location.get(location_id, {}) as Dictionary
		spawns[spawn_id] = spawn_spec
		spawns_by_location[location_id] = spawns

	for exit_value in (data.get("exits", data.get("connections", [])) as Array):
		var exit_spec := WorldLocationSpecScript.normalize_exit(exit_value as Dictionary)
		var exit_id := str(exit_spec.get("exit_id", ""))
		var from_location_id := str(exit_spec.get("from_location_id", ""))
		var target_location_id := str(exit_spec.get("target_location_id", ""))
		var target_spawn_id := str(exit_spec.get("target_spawn_id", ""))
		if exit_id.is_empty() or from_location_id.is_empty():
			errors.append("exit spec missing exit_id or from_location_id")
			continue
		if not locations_by_id.has(from_location_id):
			errors.append("exit references unknown source location: %s/%s" % [from_location_id, exit_id])
			continue
		if not locations_by_id.has(target_location_id):
			errors.append("exit references unknown target location: %s/%s" % [exit_id, target_location_id])
			continue
		if get_spawn_spec(target_location_id, target_spawn_id).is_empty():
			errors.append("exit references unknown target spawn: %s/%s" % [target_location_id, target_spawn_id])
			continue
		var key := _exit_key(from_location_id, exit_id)
		exits_by_location_and_id[key] = exit_spec
		_add_exit_index(exits_from_location_id, from_location_id, exit_spec)
		_add_exit_index(exits_to_location_id, target_location_id, exit_spec)
		if not exits_by_id.has(exit_id):
			exits_by_id[exit_id] = []
		(exits_by_id[exit_id] as Array).append(exit_spec)

	if start_location_id.is_empty():
		errors.append("start_location_id is missing")
	elif not locations_by_id.has(start_location_id):
		errors.append("start_location_id references unknown location: %s" % start_location_id)
	if start_spawn_id.is_empty():
		errors.append("start_spawn_id is missing")
	elif get_spawn_spec(start_location_id, start_spawn_id).is_empty():
		errors.append("start_spawn_id references unknown spawn: %s/%s" % [start_location_id, start_spawn_id])

	return errors


func get_location_spec(location_id: String) -> Dictionary:
	return (locations_by_id.get(location_id, {}) as Dictionary).duplicate(true)


func get_location(location_id: String) -> Dictionary:
	return get_location_spec(location_id)


func get_all_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var location_ids: Array = locations_by_id.keys()
	location_ids.sort()
	for location_id_value in location_ids:
		var location_id := str(location_id_value)
		var spec: Dictionary = locations_by_id.get(location_id, {}) as Dictionary
		if not spec.is_empty():
			result.append(spec.duplicate(true))
	return result


func get_all_edges() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var edge_keys: Array = exits_by_location_and_id.keys()
	edge_keys.sort()
	for key_value in edge_keys:
		var edge: Dictionary = exits_by_location_and_id.get(str(key_value), {}) as Dictionary
		if not edge.is_empty():
			result.append(edge.duplicate(true))
	return result


func get_region_map() -> Dictionary:
	return (source_data.get("region_map", {}) as Dictionary).duplicate(true)


func get_spawn_spec(location_id: String, spawn_id: String) -> Dictionary:
	var spawns: Dictionary = spawns_by_location.get(location_id, {}) as Dictionary
	return (spawns.get(spawn_id, {}) as Dictionary).duplicate(true)


func get_exit_spec(from_location_id: String, exit_id: String) -> Dictionary:
	var direct: Dictionary = exits_by_location_and_id.get(_exit_key(from_location_id, exit_id), {}) as Dictionary
	if not direct.is_empty():
		return direct.duplicate(true)
	var exits: Array = exits_by_id.get(exit_id, []) as Array
	for exit_value in exits:
		var exit_spec: Dictionary = exit_value as Dictionary
		if from_location_id.is_empty() or str(exit_spec.get("from_location_id", "")) == from_location_id:
			return exit_spec.duplicate(true)
	return {}


func upsert_location_spec(value: Dictionary) -> Array[String]:
	var spec := WorldLocationSpecScript.normalize_location(value)
	var location_id := str(spec.get("location_id", ""))
	if location_id.is_empty():
		return ["location spec missing location_id"]

	var old_spec: Dictionary = locations_by_id.get(location_id, {}) as Dictionary
	if not old_spec.is_empty():
		_remove_child_index(location_id, str(old_spec.get("parent_location_id", "")))
	locations_by_id[location_id] = spec
	_add_child_index(location_id, str(spec.get("parent_location_id", "")))
	_upsert_source_row("locations", "location_id", spec)
	return []


func upsert_spawn_spec(value: Dictionary) -> Array[String]:
	var spec := WorldLocationSpecScript.normalize_spawn(value)
	var location_id := str(spec.get("location_id", ""))
	var spawn_id := str(spec.get("spawn_id", ""))
	if location_id.is_empty() or spawn_id.is_empty():
		return ["spawn spec missing location_id or spawn_id"]
	if not locations_by_id.has(location_id):
		return ["spawn references unknown location: %s/%s" % [location_id, spawn_id]]

	var spawns: Dictionary = spawns_by_location.get(location_id, {}) as Dictionary
	spawns[spawn_id] = spec
	spawns_by_location[location_id] = spawns
	_upsert_source_row("spawns", "spawn_id", spec, "location_id")
	return []


func upsert_exit_spec(value: Dictionary) -> Array[String]:
	var spec := WorldLocationSpecScript.normalize_exit(value)
	var exit_id := str(spec.get("exit_id", ""))
	var from_location_id := str(spec.get("from_location_id", ""))
	var target_location_id := str(spec.get("target_location_id", ""))
	var target_spawn_id := str(spec.get("target_spawn_id", ""))
	if exit_id.is_empty() or from_location_id.is_empty():
		return ["exit spec missing exit_id or from_location_id"]
	if not locations_by_id.has(from_location_id):
		return ["exit references unknown source location: %s/%s" % [from_location_id, exit_id]]
	if not locations_by_id.has(target_location_id):
		return ["exit references unknown target location: %s/%s" % [exit_id, target_location_id]]
	if get_spawn_spec(target_location_id, target_spawn_id).is_empty():
		return ["exit references unknown target spawn: %s/%s" % [target_location_id, target_spawn_id]]

	var key := _exit_key(from_location_id, exit_id)
	var old_spec: Dictionary = exits_by_location_and_id.get(key, {}) as Dictionary
	if not old_spec.is_empty():
		_remove_exit_indexes(old_spec)

	exits_by_location_and_id[key] = spec
	_add_exit_index(exits_from_location_id, from_location_id, spec)
	_add_exit_index(exits_to_location_id, target_location_id, spec)
	if not exits_by_id.has(exit_id):
		exits_by_id[exit_id] = []
	(exits_by_id[exit_id] as Array).append(spec)
	_upsert_source_row("exits", "exit_id", spec, "from_location_id")
	return []


func find_spawn_id_for_entrance(location_id: String, entrance_id: String) -> String:
	if entrance_id.is_empty():
		return ""
	var spawns: Dictionary = spawns_by_location.get(location_id, {}) as Dictionary
	for spawn_id_value in spawns.keys():
		var spawn_id := str(spawn_id_value)
		var spawn_spec: Dictionary = spawns.get(spawn_id, {}) as Dictionary
		if str(spawn_spec.get("entrance_id", "")) == entrance_id:
			return spawn_id
	return ""


func get_child_locations(parent_location_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child_id_value in (child_locations_by_parent_id.get(parent_location_id, []) as Array):
		var child_spec := get_location_spec(str(child_id_value))
		if not child_spec.is_empty():
			result.append(child_spec)
	return result


func get_edges_from(location_id: String) -> Array[Dictionary]:
	return _duplicate_exit_rows(exits_from_location_id.get(location_id, []) as Array)


func get_edges_to(location_id: String) -> Array[Dictionary]:
	return _duplicate_exit_rows(exits_to_location_id.get(location_id, []) as Array)


func get_parent_location_id(location_id: String) -> String:
	var location_spec := get_location_spec(location_id)
	return str(location_spec.get("parent_location_id", ""))


func is_child_location(location_id: String) -> bool:
	return not get_parent_location_id(location_id).is_empty()


func location_count() -> int:
	return locations_by_id.size()


func get_debug_summary() -> Dictionary:
	var child_counts: Dictionary = {}
	for parent_id in child_locations_by_parent_id.keys():
		child_counts[str(parent_id)] = (child_locations_by_parent_id[parent_id] as Array).size()
	return {
		"world_id": world_id,
		"location_count": locations_by_id.size(),
		"child_counts": child_counts,
		"edge_count": exits_by_location_and_id.size(),
	}


func to_dictionary() -> Dictionary:
	return source_data.duplicate(true)


func _exit_key(from_location_id: String, exit_id: String) -> String:
	return "%s::%s" % [from_location_id, exit_id]


func _add_child_index(location_id: String, parent_location_id: String) -> void:
	if parent_location_id.is_empty():
		return
	var children: Array = child_locations_by_parent_id.get(parent_location_id, []) as Array
	if not children.has(location_id):
		children.append(location_id)
	child_locations_by_parent_id[parent_location_id] = children


func _remove_child_index(location_id: String, parent_location_id: String) -> void:
	if parent_location_id.is_empty() or not child_locations_by_parent_id.has(parent_location_id):
		return
	var children: Array = child_locations_by_parent_id.get(parent_location_id, []) as Array
	children.erase(location_id)
	if children.is_empty():
		child_locations_by_parent_id.erase(parent_location_id)
	else:
		child_locations_by_parent_id[parent_location_id] = children


func _add_exit_index(index: Dictionary, location_id: String, exit_spec: Dictionary) -> void:
	if location_id.is_empty():
		return
	if not index.has(location_id):
		index[location_id] = []
	(index[location_id] as Array).append(exit_spec.duplicate(true))


func _remove_exit_indexes(exit_spec: Dictionary) -> void:
	var exit_id := str(exit_spec.get("exit_id", ""))
	var from_location_id := str(exit_spec.get("from_location_id", ""))
	var target_location_id := str(exit_spec.get("target_location_id", ""))
	_remove_exit_from_index(exits_from_location_id, from_location_id, exit_id, from_location_id)
	_remove_exit_from_index(exits_to_location_id, target_location_id, exit_id, from_location_id)
	if exits_by_id.has(exit_id):
		var rows: Array = exits_by_id.get(exit_id, []) as Array
		for index in range(rows.size() - 1, -1, -1):
			var row: Dictionary = rows[index] as Dictionary
			if str(row.get("from_location_id", "")) == from_location_id:
				rows.remove_at(index)
		if rows.is_empty():
			exits_by_id.erase(exit_id)
		else:
			exits_by_id[exit_id] = rows


func _remove_exit_from_index(index: Dictionary, location_id: String, exit_id: String, from_location_id: String) -> void:
	if location_id.is_empty() or not index.has(location_id):
		return
	var rows: Array = index.get(location_id, []) as Array
	for row_index in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[row_index] as Dictionary
		if str(row.get("exit_id", "")) == exit_id and str(row.get("from_location_id", "")) == from_location_id:
			rows.remove_at(row_index)
	if rows.is_empty():
		index.erase(location_id)
	else:
		index[location_id] = rows


func _duplicate_exit_rows(rows: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_value in rows:
		result.append((row_value as Dictionary).duplicate(true))
	return result


func _upsert_source_row(array_name: String, id_key: String, row: Dictionary, scope_key: String = "") -> void:
	var rows: Array = source_data.get(array_name, []) as Array
	var row_id := str(row.get(id_key, ""))
	var row_scope := str(row.get(scope_key, "")) if not scope_key.is_empty() else ""
	var replaced := false
	for index in range(rows.size()):
		var existing: Dictionary = rows[index] as Dictionary
		if str(existing.get(id_key, "")) != row_id:
			continue
		if not scope_key.is_empty() and str(existing.get(scope_key, "")) != row_scope:
			continue
		rows[index] = row.duplicate(true)
		replaced = true
		break
	if not replaced:
		rows.append(row.duplicate(true))
	source_data[array_name] = rows
