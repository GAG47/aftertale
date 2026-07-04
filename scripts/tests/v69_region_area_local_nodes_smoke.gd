extends SceneTree

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const WorldGraphBlueprintScript := preload("res://scripts/systems/world/world_graph_blueprint.gd")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6901
const REMOVED_WORLD_KEYS := [
	"biome_map",
	"dominant_biome",
	"region_biome",
	"from_biome",
	"to_biome",
	"biome_relation",
	"biome_profile_map",
	"local_roles_by_biome",
	"local_role_profile_map",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first_result: Dictionary = _generated_world_result(WORLD_SEED, "v69_region_area_world")
	if not bool(first_result.get("success", false)):
		_fail("v69 world generation failed: %s" % str(first_result.get("errors", [])))
		return
	var first_data: Dictionary = first_result.get("world_data", {}) as Dictionary
	if not _assert_region_area_layer(first_data):
		return
	if not _assert_location_nodes_are_region_children(first_data):
		return
	if not _assert_edges_only_connect_location_nodes(first_data):
		return
	if not _assert_world_service_exposes_region_areas(first_data):
		return
	if not _assert_seed_behavior(first_data):
		return
	if not _assert_invalid_role_profile_fails():
		return

	print("v69 region area local nodes smoke test passed")
	quit(0)


func _assert_region_area_layer(world_data: Dictionary) -> bool:
	if JSON.stringify(world_data).contains("biome_map"):
		_fail("v69 generated world still contains removed world biome_map")
		return false
	if (world_data.get("region_map", {}) as Dictionary).is_empty():
		_fail("v69 generated world has no RegionMap")
		return false
	var region_areas: Array = world_data.get("region_areas", []) as Array
	if region_areas.is_empty():
		_fail("v69 generated world has no RegionArea rows")
		return false
	var location_nodes: Array = world_data.get("location_nodes", []) as Array
	var transition_edges: Array = world_data.get("transition_edges", []) as Array
	if location_nodes.size() != (world_data.get("locations", []) as Array).size():
		_fail("v69 location_nodes is not synchronized with locations")
		return false
	if transition_edges.size() != (world_data.get("exits", []) as Array).size():
		_fail("v69 transition_edges is not synchronized with exits")
		return false
	var blueprint: RefCounted = WorldGraphBlueprintScript.new()
	blueprint.configure(world_data)
	var errors: Array[String] = blueprint.validate()
	if not errors.is_empty():
		_fail("v69 blueprint validation failed: %s" % str(errors))
		return false
	var region_area_ids: Dictionary = _region_area_ids(world_data)
	for area_value in region_areas:
		var area: Dictionary = area_value as Dictionary
		var area_type := str(area.get("area_type", ""))
		if area_type.is_empty():
			_fail("v69 RegionArea missing area_type")
			return false
		if area.has("dominant_biome"):
			_fail("v69 RegionArea still has removed dominant_biome: %s" % str(area.get("region_id", "")))
			return false
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if region_area_ids.has(location_id):
			_fail("v69 RegionArea leaked into location nodes: %s" % location_id)
			return false
	return true


func _assert_location_nodes_are_region_children(world_data: Dictionary) -> bool:
	var config: Dictionary = WorldGenerationProfileScript.resolve_generation_config({
		"world_id": str(world_data.get("world_id", "")),
		"world_seed": int(world_data.get("world_seed", 0)),
		"region_profile_id": PROFILE_ID,
	})
	var role_profile_map: Dictionary = config.get("area_role_profile_map", {}) as Dictionary
	var region_area_ids: Dictionary = _region_area_ids(world_data)
	var area_by_id: Dictionary = _region_area_by_id(world_data)
	var generated_ids_by_area: Dictionary = {}
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		var parent_region_id := str(location.get("parent_region_id", ""))
		var local_role := str(location.get("local_role", ""))
		var area_type := str(location.get("area_type", ""))
		if parent_region_id.is_empty() or not region_area_ids.has(parent_region_id):
			_fail("v69 location node missing valid parent_region_id: %s/%s" % [location_id, parent_region_id])
			return false
		if local_role.is_empty():
			_fail("v69 location node missing local_role: %s" % location_id)
			return false
		if location.has("region_biome"):
			_fail("v69 location node still has removed region_biome: %s" % location_id)
			return false
		var area: Dictionary = area_by_id.get(parent_region_id, {}) as Dictionary
		if str(area.get("area_type", "")) != area_type:
			_fail("v69 location area_type does not match parent RegionArea: %s" % location_id)
			return false
		if not _area_contains_position(area, location.get("region_position", {}) as Dictionary):
			_fail("v69 location region_position is outside parent RegionArea: %s" % location_id)
			return false
		var role_map: Dictionary = role_profile_map.get(area_type, {}) as Dictionary
		var profiles: Array = role_map.get(local_role, []) as Array
		if not profiles.has(str(location.get("generator_profile_id", ""))):
			_fail("v69 generator profile is not derived from area_type + local_role: %s" % location_id)
			return false
		if (location.get("region_context", {}) as Dictionary).is_empty():
			_fail("v69 location has no region_context: %s" % location_id)
			return false
		if str(location.get("display_name", "")).is_empty() or str(location.get("display_name", "")).contains("Wild"):
			_fail("v69 location display name is not localized by local role: %s" % location_id)
			return false
		var ids: Array = generated_ids_by_area.get(parent_region_id, []) as Array
		ids.append(location_id)
		generated_ids_by_area[parent_region_id] = ids
	for area_value in (world_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		var area_generated_ids: Array = area.get("generated_location_node_ids", []) as Array
		var expected_ids: Array = generated_ids_by_area.get(region_id, []) as Array
		if area_generated_ids.size() != expected_ids.size():
			_fail("v69 RegionArea generated node list mismatch: %s" % region_id)
			return false
	return true


func _assert_edges_only_connect_location_nodes(world_data: Dictionary) -> bool:
	var location_by_id: Dictionary = _location_by_id(world_data)
	var region_area_ids: Dictionary = _region_area_ids(world_data)
	for edge_value in (world_data.get("exits", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		var exit_id := str(edge.get("exit_id", ""))
		var from_location_id := str(edge.get("from_location_id", ""))
		var target_location_id := str(edge.get("target_location_id", ""))
		if region_area_ids.has(from_location_id) or region_area_ids.has(target_location_id):
			_fail("v69 edge connects RegionArea instead of real locations: %s" % exit_id)
			return false
		var from_node: Dictionary = location_by_id.get(from_location_id, {}) as Dictionary
		var target_node: Dictionary = location_by_id.get(target_location_id, {}) as Dictionary
		if from_node.is_empty() or target_node.is_empty():
			_fail("v69 edge references missing location node: %s" % exit_id)
			return false
		var from_region_id := str(edge.get("from_region_id", ""))
		var target_region_id := str(edge.get("target_region_id", ""))
		if from_region_id != str(from_node.get("parent_region_id", "")):
			_fail("v69 edge from_region_id does not match source node: %s" % exit_id)
			return false
		if target_region_id != str(target_node.get("parent_region_id", "")):
			_fail("v69 edge target_region_id does not match target node: %s" % exit_id)
			return false
		var expected_scope := "internal_region" if from_region_id == target_region_id else "between_regions"
		if str(edge.get("edge_scope", "")) != expected_scope:
			_fail("v69 edge_scope mismatch: %s" % exit_id)
			return false
		if str(edge.get("area_relation", "")) != "%s_to_%s" % [str(edge.get("from_area_type", "")), str(edge.get("target_area_type", ""))]:
			_fail("v69 edge area_relation is not area_type-derived: %s" % exit_id)
			return false
		for removed_key in REMOVED_WORLD_KEYS:
			if edge.has(removed_key):
				_fail("v69 edge still has removed key %s: %s" % [removed_key, exit_id])
				return false
	return true


func _assert_world_service_exposes_region_areas(world_data: Dictionary) -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v69 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v69 generated world did not load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v69 generated world did not start: %s" % str(start_result.get("error", "")))
		return false
	var view_data: Dictionary = world_service.get_region_map_view_data()
	if (view_data.get("region_areas", []) as Array).is_empty():
		_fail("v69 map view data has no RegionArea rows")
		return false
	if str(view_data.get("current_region_id", "")).is_empty():
		_fail("v69 map view data has no current_region_id")
		return false
	var first_area_id := str(((world_data.get("region_areas", []) as Array)[0] as Dictionary).get("region_id", ""))
	if not world_service.prepare_scene_load_for_location(first_area_id).is_empty():
		_fail("v69 RegionArea was accepted as a materializable location")
		return false
	var invalid_data := world_data.duplicate(true)
	var exits: Array = (invalid_data.get("exits", []) as Array).duplicate(true)
	var first_edge: Dictionary = (exits[0] as Dictionary).duplicate(true)
	first_edge["target_location_id"] = first_area_id
	exits[0] = first_edge
	invalid_data["exits"] = exits
	world_service.reset_world()
	var invalid_load_result: Dictionary = world_service.load_world_from_data(invalid_data)
	if bool(invalid_load_result.get("success", false)):
		_fail("v69 world graph accepted an edge targeting RegionArea")
		return false
	world_service.reset_world()
	return true


func _assert_seed_behavior(first_data: Dictionary) -> bool:
	var same_result: Dictionary = _generated_world_result(WORLD_SEED, "v69_region_area_world")
	if not bool(same_result.get("success", false)):
		_fail("v69 same-seed generation failed: %s" % str(same_result.get("errors", [])))
		return false
	var same_data: Dictionary = same_result.get("world_data", {}) as Dictionary
	if _world_signature(first_data) != _world_signature(same_data):
		_fail("v69 same seed did not reproduce the same region area local node graph")
		return false
	var different_result: Dictionary = _generated_world_result(WORLD_SEED + 17, "v69_region_area_world")
	if not bool(different_result.get("success", false)):
		_fail("v69 different-seed generation failed: %s" % str(different_result.get("errors", [])))
		return false
	var different_data: Dictionary = different_result.get("world_data", {}) as Dictionary
	if _world_signature(first_data) == _world_signature(different_data):
		_fail("v69 different seed produced the same region area local node graph")
		return false
	return true


func _assert_invalid_role_profile_fails() -> bool:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v69_bad_role_profile_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"area_role_profile_map": {
			"plain": {
				"field_entry": ["missing_profile"],
			},
		},
	})
	if bool(result.get("success", false)):
		_fail("v69 unsupported area role profile unexpectedly succeeded")
		return false
	var errors_text := str(result.get("errors", []))
	if not errors_text.contains("unsupported wild terrain profile") and not errors_text.contains("not listed in available_wild_profiles"):
		_fail("v69 unsupported area role profile did not expose failure: %s" % errors_text)
		return false
	return true


func _generated_world_result(seed: int, world_id: String) -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	return generator.generate_world_data_result({
		"world_id": world_id,
		"world_seed": seed,
		"region_profile_id": PROFILE_ID,
	})


func _region_area_ids(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for area_value in (world_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty():
			result[region_id] = true
	return result


func _region_area_by_id(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for area_value in (world_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty():
			result[region_id] = area
	return result


func _location_by_id(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if not location_id.is_empty():
			result[location_id] = location
	return result


func _area_contains_position(area: Dictionary, position_data: Dictionary) -> bool:
	var target := "%d,%d" % [int(position_data.get("x", -1)), int(position_data.get("y", -1))]
	for cell_value in (area.get("cells", []) as Array):
		var cell: Dictionary = cell_value as Dictionary
		var key := "%d,%d" % [int(cell.get("x", -1)), int(cell.get("y", -1))]
		if key == target:
			return true
	return false


func _world_signature(world_data: Dictionary) -> String:
	var area_rows: Array[String] = []
	for area_value in (world_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		area_rows.append("%s:%s:%s:%s" % [
			str(area.get("region_id", "")),
			str(area.get("area_type", "")),
			str(area.get("center_position", {})),
			str(area.get("generated_location_node_ids", [])),
		])
	area_rows.sort()
	var location_rows: Array[String] = []
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		location_rows.append("%s:%s:%s:%s:%s:%s" % [
			str(location.get("location_id", "")),
			str(location.get("parent_region_id", "")),
			str(location.get("area_type", "")),
			str(location.get("local_role", "")),
			str(location.get("region_position", {})),
			str(location.get("generator_profile_id", "")),
		])
	location_rows.sort()
	var edge_rows: Array[String] = []
	for edge_value in (world_data.get("exits", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		edge_rows.append("%s:%s:%s:%s:%s:%s" % [
			str(edge.get("exit_id", "")),
			str(edge.get("from_location_id", "")),
			str(edge.get("target_location_id", "")),
			str(edge.get("from_region_id", "")),
			str(edge.get("target_region_id", "")),
			str(edge.get("area_relation", "")),
		])
	edge_rows.sort()
	return "%s|%s|%s" % [str(area_rows), str(location_rows), str(edge_rows)]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
