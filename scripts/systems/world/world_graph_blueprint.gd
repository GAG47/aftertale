class_name WorldGraphBlueprint
extends RefCounted

var world_data: Dictionary = {}


func configure(data: Dictionary) -> void:
	world_data = data.duplicate(true)


func to_dictionary() -> Dictionary:
	return world_data.duplicate(true)


func get_debug_summary() -> Dictionary:
	return (world_data.get("debug_summary", {}) as Dictionary).duplicate(true)


func validate() -> Array[String]:
	var errors: Array[String] = []
	var locations: Array = world_data.get("locations", []) as Array
	var spawns: Array = world_data.get("spawns", []) as Array
	var exits: Array = world_data.get("exits", []) as Array
	var location_ids: Dictionary = {}
	var spawn_keys: Dictionary = {}
	var exit_ids: Dictionary = {}

	if str(world_data.get("world_id", "")).is_empty():
		errors.append("world_id is missing")
	if str(world_data.get("start_location_id", "")).is_empty():
		errors.append("start_location_id is missing")

	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if location_id.is_empty():
			errors.append("location node missing location_id")
			continue
		if location_ids.has(location_id):
			errors.append("duplicate location node id: %s" % location_id)
			continue
		location_ids[location_id] = true
		if str(location.get("location_kind", "")) == "generated_wild":
			if str(location.get("generator_profile_id", "")).is_empty():
				errors.append("generated_wild node missing generator_profile_id: %s" % location_id)
			if not location.has("seed"):
				errors.append("generated_wild node missing seed: %s" % location_id)
			if (location.get("size", {}) as Dictionary).is_empty():
				errors.append("generated_wild node missing size: %s" % location_id)

	for spawn_value in spawns:
		var spawn: Dictionary = spawn_value as Dictionary
		var location_id := str(spawn.get("location_id", ""))
		var spawn_id := str(spawn.get("spawn_id", ""))
		var key := "%s::%s" % [location_id, spawn_id]
		if location_id.is_empty() or spawn_id.is_empty():
			errors.append("spawn point missing location_id or spawn_id")
			continue
		if not location_ids.has(location_id):
			errors.append("spawn point references unknown location: %s/%s" % [location_id, spawn_id])
		if spawn_keys.has(key):
			errors.append("duplicate spawn point id: %s" % key)
		spawn_keys[key] = true

	for exit_value in exits:
		var edge: Dictionary = exit_value as Dictionary
		var exit_id := str(edge.get("exit_id", ""))
		var from_location_id := str(edge.get("from_location_id", ""))
		var target_location_id := str(edge.get("target_location_id", ""))
		var target_spawn_id := str(edge.get("target_spawn_id", ""))
		if exit_id.is_empty():
			errors.append("transition edge missing exit_id")
			continue
		if exit_ids.has(exit_id):
			errors.append("duplicate transition edge id: %s" % exit_id)
		exit_ids[exit_id] = true
		if not location_ids.has(from_location_id):
			errors.append("transition edge references unknown source location: %s/%s" % [from_location_id, exit_id])
		if not location_ids.has(target_location_id):
			errors.append("transition edge references unknown target location: %s/%s" % [exit_id, target_location_id])
		if not spawn_keys.has("%s::%s" % [target_location_id, target_spawn_id]):
			errors.append("transition edge references unknown target spawn: %s/%s" % [target_location_id, target_spawn_id])

	if not location_ids.has(str(world_data.get("start_location_id", ""))):
		errors.append("start_location_id references unknown location")
	if not _is_connected(locations, exits):
		errors.append("world graph is not connected")
	return errors


func _is_connected(locations: Array, exits: Array) -> bool:
	if locations.is_empty():
		return true
	var adjacency: Dictionary = {}
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		adjacency[str(location.get("location_id", ""))] = []
	for exit_value in exits:
		var edge: Dictionary = exit_value as Dictionary
		var from_location_id := str(edge.get("from_location_id", ""))
		var target_location_id := str(edge.get("target_location_id", ""))
		if not adjacency.has(from_location_id) or not adjacency.has(target_location_id):
			continue
		(adjacency[from_location_id] as Array).append(target_location_id)
		(adjacency[target_location_id] as Array).append(from_location_id)

	var start_location_id := str((locations[0] as Dictionary).get("location_id", ""))
	var open: Array[String] = [start_location_id]
	var seen: Dictionary = {}
	while not open.is_empty():
		var current: String = str(open.pop_front())
		if seen.has(current):
			continue
		seen[current] = true
		for next_value in (adjacency.get(current, []) as Array):
			var next_id := str(next_value)
			if not seen.has(next_id):
				open.append(next_id)
	return seen.size() == adjacency.size()
