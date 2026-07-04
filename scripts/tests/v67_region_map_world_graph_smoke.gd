extends SceneTree

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6701
const REQUIRED_REGION_MAPS := [
	"elevation_map",
	"moisture_map",
	"water_map",
	"forest_map",
	"rock_map",
	"slope_map",
	"water_distance_map",
	"hydro_context_map",
	"landform_class_map",
	"vegetation_class_map",
	"surface_class_map",
	"local_feature_map",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_map_seed_behavior():
		return
	if not _assert_world_graph_uses_region_map_layers():
		return
	if not _assert_generated_wild_receives_region_patch():
		return
	if not _assert_unsupported_area_profile_fails():
		return

	print("v67 region map world graph smoke test passed")
	quit(0)


func _assert_region_map_seed_behavior() -> bool:
	var first_data := _generated_world_data(WORLD_SEED, "v67_seed_world")
	if first_data.is_empty():
		return false
	var same_data := _generated_world_data(WORLD_SEED, "v67_seed_world")
	if same_data.is_empty():
		return false
	var different_data := _generated_world_data(WORLD_SEED + 11, "v67_seed_world")
	if different_data.is_empty():
		return false
	var first_map: Dictionary = first_data.get("region_map", {}) as Dictionary
	var same_map: Dictionary = same_data.get("region_map", {}) as Dictionary
	var different_map: Dictionary = different_data.get("region_map", {}) as Dictionary
	if _map_signature(first_map) != _map_signature(same_map):
		_fail("v67 same seed did not reproduce the same RegionMap")
		return false
	if _map_signature(first_map) == _map_signature(different_map):
		_fail("v67 different seed produced the same RegionMap")
		return false
	return true


func _assert_world_graph_uses_region_map_layers() -> bool:
	var world_data := _generated_world_data(WORLD_SEED, "v67_layered_world")
	if world_data.is_empty():
		return false
	var region_map: Dictionary = world_data.get("region_map", {}) as Dictionary
	if region_map.has("biome_map"):
		_fail("v67 RegionMap still exposes removed world biome_map")
		return false
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	for map_key in REQUIRED_REGION_MAPS:
		if not _map_has_size(region_map.get(map_key, []) as Array, width, height):
			_fail("v67 RegionMap missing or invalid layered map: %s" % map_key)
			return false
	if not _assert_layer_has_variation(region_map.get("elevation_map", []) as Array):
		_fail("v67 elevation_map has no usable variation")
		return false
	if not _assert_layer_has_variation(region_map.get("moisture_map", []) as Array):
		_fail("v67 moisture_map has no usable variation")
		return false
	var config: Dictionary = WorldGenerationProfileScript.resolve_generation_config({
		"world_id": str(world_data.get("world_id", "")),
		"world_seed": int(world_data.get("world_seed", 0)),
		"region_profile_id": PROFILE_ID,
	})
	var role_profile_map: Dictionary = config.get("area_role_profile_map", {}) as Dictionary
	var area_by_id := _region_area_by_id(world_data)
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if location.has("region_biome"):
			_fail("v67 location still has removed region_biome")
			return false
		var location_id := str(location.get("location_id", ""))
		var parent_region_id := str(location.get("parent_region_id", ""))
		var area: Dictionary = area_by_id.get(parent_region_id, {}) as Dictionary
		var area_type := str(location.get("area_type", ""))
		var local_role := str(location.get("local_role", ""))
		if area.is_empty() or str(area.get("area_type", "")) != area_type:
			_fail("v67 location area_type does not come from parent RegionArea: %s" % location_id)
			return false
		if (location.get("region_patch", {}) as Dictionary).is_empty():
			_fail("v67 location has no RegionPatch: %s" % location_id)
			return false
		var role_map: Dictionary = role_profile_map.get(area_type, {}) as Dictionary
		var profiles: Array = role_map.get(local_role, []) as Array
		if not profiles.has(str(location.get("generator_profile_id", ""))):
			_fail("v67 generator_profile_id is not derived from area_type + local_role: %s" % location_id)
			return false
	for edge_value in (world_data.get("exits", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		if edge.has("from_biome") or edge.has("to_biome") or edge.has("biome_relation"):
			_fail("v67 edge still has removed biome relation fields")
			return false
		if str(edge.get("area_relation", "")) != "%s_to_%s" % [str(edge.get("from_area_type", "")), str(edge.get("target_area_type", ""))]:
			_fail("v67 edge area relation is not derived from area types")
			return false
	return true


func _assert_generated_wild_receives_region_patch() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v67 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()
	var world_data := _generated_world_data(WORLD_SEED, "v67_runtime_patch_world")
	if world_data.is_empty():
		return false
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v67 world load failed: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v67 world start failed: %s" % str(start_result.get("error", "")))
		return false
	var start_location_id := str(world_data.get("start_location_id", ""))
	var location_data: Dictionary = world_service.get_registered_location_data(start_location_id)
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	if not bool(summary.get("region_patch_applied", false)):
		_fail("v67 generated wild location did not apply RegionPatch")
		return false
	var metadata: Dictionary = world_service.get_location_metadata(start_location_id)
	if str(metadata.get("area_type", "")).is_empty():
		_fail("v67 runtime metadata missing area_type")
		return false
	if (metadata.get("region_context", {}) as Dictionary).is_empty():
		_fail("v67 runtime metadata missing region_context")
		return false
	world_service.reset_world()
	return true


func _assert_unsupported_area_profile_fails() -> bool:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v67_bad_area_profile_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"area_role_profile_map": {
			"plain": {
				"field_entry": ["not_a_real_profile"],
			},
		},
	})
	if bool(result.get("success", false)):
		_fail("v67 unsupported area role profile unexpectedly succeeded")
		return false
	var errors_text := str(result.get("errors", []))
	if not errors_text.contains("unsupported wild terrain profile") and not errors_text.contains("not listed in available_wild_profiles"):
		_fail("v67 unsupported profile did not expose an explicit error: %s" % errors_text)
		return false
	return true


func _generated_world_data(seed: int, world_id: String) -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": world_id,
		"world_seed": seed,
		"region_profile_id": PROFILE_ID,
	})
	if not bool(result.get("success", false)):
		_fail("v67 world generation failed: %s" % str(result.get("errors", [])))
		return {}
	return result.get("world_data", {}) as Dictionary


func _region_area_by_id(world_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for area_value in (world_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty():
			result[region_id] = area
	return result


func _map_signature(region_map: Dictionary) -> String:
	var parts: Array[String] = []
	for map_key in REQUIRED_REGION_MAPS:
		parts.append(JSON.stringify(region_map.get(map_key, [])))
	return "|".join(parts)


func _map_has_size(map_data: Array, width: int, height: int) -> bool:
	if map_data.size() != height:
		return false
	for row_value in map_data:
		var row: Array = row_value as Array
		if row.size() != width:
			return false
	return true


func _assert_layer_has_variation(map_data: Array) -> bool:
	var seen := {}
	for row_value in map_data:
		var row: Array = row_value as Array
		for value in row:
			seen[str(value)] = true
			if seen.size() >= 2:
				return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
