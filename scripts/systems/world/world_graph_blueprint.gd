class_name WorldGraphBlueprint
extends RefCounted

const RegionMapGeneratorScript := preload("res://scripts/systems/world/region_map_generator.gd")
const RegionAreaBuilderScript := preload("res://scripts/systems/world/region_area_builder.gd")

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
	var region_areas: Array = world_data.get("region_areas", []) as Array
	var location_ids: Dictionary = {}
	var location_rows_by_id: Dictionary = {}
	var region_area_ids: Dictionary = {}
	var spawn_keys: Dictionary = {}
	var exit_ids: Dictionary = {}

	if str(world_data.get("world_id", "")).is_empty():
		errors.append("world_id is missing")
	if str(world_data.get("start_location_id", "")).is_empty():
		errors.append("start_location_id is missing")
	var region_map: Dictionary = world_data.get("region_map", {}) as Dictionary
	if region_map.is_empty():
		errors.append("region_map is missing")
	else:
		var region_generator: RefCounted = RegionMapGeneratorScript.new()
		errors.append_array(region_generator.validate_region_map(region_map))
		if region_areas.is_empty():
			errors.append("region_areas is missing")
		else:
			var area_builder: RefCounted = RegionAreaBuilderScript.new()
			errors.append_array(area_builder.validate_region_areas(region_map, region_areas))

	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if region_id.is_empty():
			continue
		if region_area_ids.has(region_id):
			continue
		region_area_ids[region_id] = true

	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if location_id.is_empty():
			errors.append("location node missing location_id")
			continue
		if location_ids.has(location_id):
			errors.append("duplicate location node id: %s" % location_id)
			continue
		if region_area_ids.has(location_id):
			errors.append("RegionArea cannot be used as a WorldLocationNode: %s" % location_id)
			continue
		location_ids[location_id] = true
		location_rows_by_id[location_id] = location.duplicate(true)
		if str(location.get("location_kind", "")) == "generated_wild":
			var parent_region_id := str(location.get("parent_region_id", ""))
			if parent_region_id.is_empty():
				errors.append("generated_wild node missing parent_region_id: %s" % location_id)
			elif not region_area_ids.has(parent_region_id):
				errors.append("generated_wild node references unknown RegionArea: %s/%s" % [location_id, parent_region_id])
			if str(location.get("local_role", "")).is_empty():
				errors.append("generated_wild node missing local_role: %s" % location_id)
			if str(location.get("generator_profile_id", "")).is_empty():
				errors.append("generated_wild node missing generator_profile_id: %s" % location_id)
			if not location.has("seed"):
				errors.append("generated_wild node missing seed: %s" % location_id)
			if (location.get("size", {}) as Dictionary).is_empty():
				errors.append("generated_wild node missing size: %s" % location_id)
			if (location.get("region_position", {}) as Dictionary).is_empty():
				errors.append("generated_wild node missing region_position: %s" % location_id)
			if str(location.get("area_type", "")).is_empty():
				errors.append("generated_wild node missing area_type: %s" % location_id)
			if location.has("region_biome"):
				errors.append("generated_wild node contains removed region_biome path: %s" % location_id)
			if (location.get("region_patch", {}) as Dictionary).is_empty():
				errors.append("generated_wild node missing region_patch: %s" % location_id)
			if (location.get("region_context", {}) as Dictionary).is_empty():
				errors.append("generated_wild node missing region_context: %s" % location_id)

	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		for generated_id_value in (area.get("generated_location_node_ids", []) as Array):
			var generated_id := str(generated_id_value)
			if generated_id.is_empty():
				continue
			if not location_ids.has(generated_id):
				errors.append("RegionArea references unknown generated location node: %s/%s" % [region_id, generated_id])
			else:
				var generated_location: Dictionary = location_rows_by_id.get(generated_id, {}) as Dictionary
				if str(generated_location.get("parent_region_id", "")) != region_id:
					errors.append("RegionArea generated node parent mismatch: %s/%s" % [region_id, generated_id])

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
		if region_area_ids.has(from_location_id):
			errors.append("transition edge source cannot be RegionArea: %s/%s" % [from_location_id, exit_id])
		if region_area_ids.has(target_location_id):
			errors.append("transition edge target cannot be RegionArea: %s/%s" % [exit_id, target_location_id])
		if not spawn_keys.has("%s::%s" % [target_location_id, target_spawn_id]):
			errors.append("transition edge references unknown target spawn: %s/%s" % [target_location_id, target_spawn_id])
		if (edge.get("from_region_position", {}) as Dictionary).is_empty():
			errors.append("transition edge missing from_region_position: %s" % exit_id)
		if (edge.get("to_region_position", {}) as Dictionary).is_empty():
			errors.append("transition edge missing to_region_position: %s" % exit_id)
		if edge.has("from_biome"):
			errors.append("transition edge contains removed from_biome path: %s" % exit_id)
		if edge.has("to_biome"):
			errors.append("transition edge contains removed to_biome path: %s" % exit_id)
		if str(edge.get("from_area_type", "")).is_empty():
			errors.append("transition edge missing from_area_type: %s" % exit_id)
		if str(edge.get("target_area_type", "")).is_empty():
			errors.append("transition edge missing target_area_type: %s" % exit_id)
		if str(edge.get("transition_kind", "")).is_empty():
			errors.append("transition edge missing transition_kind: %s" % exit_id)
		var from_region_id := str(edge.get("from_region_id", ""))
		var target_region_id := str(edge.get("target_region_id", ""))
		if from_region_id.is_empty():
			errors.append("transition edge missing from_region_id: %s" % exit_id)
		elif not region_area_ids.has(from_region_id):
			errors.append("transition edge references unknown from_region_id: %s/%s" % [exit_id, from_region_id])
		if target_region_id.is_empty():
			errors.append("transition edge missing target_region_id: %s" % exit_id)
		elif not region_area_ids.has(target_region_id):
			errors.append("transition edge references unknown target_region_id: %s/%s" % [exit_id, target_region_id])
		var edge_scope := str(edge.get("edge_scope", ""))
		if not ["internal_region", "between_regions"].has(edge_scope):
			errors.append("transition edge has invalid edge_scope: %s/%s" % [exit_id, edge_scope])
		elif edge_scope == "internal_region" and from_region_id != target_region_id:
			errors.append("internal_region edge crosses RegionArea: %s" % exit_id)
		elif edge_scope == "between_regions" and from_region_id == target_region_id:
			errors.append("between_regions edge does not cross RegionArea: %s" % exit_id)
		if edge.has("biome_relation"):
			errors.append("transition edge contains removed biome_relation path: %s" % exit_id)
		if str(edge.get("area_relation", "")).is_empty():
			errors.append("transition edge missing area_relation: %s" % exit_id)

	if not location_ids.has(str(world_data.get("start_location_id", ""))):
		errors.append("start_location_id references unknown location")
	if region_area_ids.has(str(world_data.get("start_location_id", ""))):
		errors.append("start_location_id cannot be RegionArea")
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
