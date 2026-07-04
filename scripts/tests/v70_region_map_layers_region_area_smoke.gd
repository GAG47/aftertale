extends SceneTree

const WorldGenerationProfileScript := preload("res://scripts/systems/world/world_generation_profile.gd")
const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const RegionMapViewScene := preload("res://scenes/ui/screens/region_map_screen.tscn")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 7001
const REQUIRED_FACT_MAPS := [
	"elevation_map",
	"moisture_map",
	"water_map",
	"forest_map",
	"rock_map",
	"slope_map",
	"water_distance_map",
]
const REQUIRED_DERIVED_MAPS := [
	"hydro_context_map",
	"landform_class_map",
	"vegetation_class_map",
	"surface_class_map",
	"local_feature_map",
]
const ALLOWED_AREA_TYPES := [
	"plain",
	"forest",
	"hills",
	"highland",
	"mountain",
	"river_valley",
	"wetland",
	"lake_region",
	"coastland",
	"rocky_wilds",
	"settlement_area",
]
const SMALL_SCALE_TERMS := [
	"foothill",
	"riverbank",
	"coast_edge",
	"beach",
	"creek_side",
	"clearing",
	"entrance",
	"path",
	"slope",
	"rocky_slope",
	"forest_edge",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world_data := _generated_world_data()
	if world_data.is_empty():
		return
	if not _assert_region_map_layers(world_data):
		return
	if not _assert_region_areas_use_large_scale_types(world_data):
		return
	if not _assert_location_nodes_use_area_context(world_data):
		return
	if not _assert_edges_use_area_relation(world_data):
		return
	if not _assert_map_view_reads_layered_region_map(world_data):
		return
	if not _assert_unsupported_area_type_fails():
		return

	print("v70 region map layers region area smoke test passed")
	quit(0)


func _assert_region_map_layers(world_data: Dictionary) -> bool:
	var region_map: Dictionary = world_data.get("region_map", {}) as Dictionary
	if region_map.is_empty():
		_fail("v70 RegionMap is missing")
		return false
	if region_map.has("biome_map"):
		_fail("v70 RegionMap still exposes removed world biome_map")
		return false
	var width := int(region_map.get("width", 0))
	var height := int(region_map.get("height", 0))
	for map_key in REQUIRED_FACT_MAPS + REQUIRED_DERIVED_MAPS:
		if not _map_has_size(region_map.get(map_key, []) as Array, width, height):
			_fail("v70 RegionMap missing required layered map: %s" % map_key)
			return false
	if not _assert_layer_has_variation(region_map.get("elevation_map", []) as Array):
		_fail("v70 elevation_map has no variation")
		return false
	if not _assert_layer_has_variation(region_map.get("hydro_context_map", []) as Array):
		_fail("v70 hydro_context_map has no variation")
		return false
	return true


func _assert_region_areas_use_large_scale_types(world_data: Dictionary) -> bool:
	var areas: Array = world_data.get("region_areas", []) as Array
	if areas.is_empty():
		_fail("v70 world has no RegionArea rows")
		return false
	for area_value in areas:
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		var area_type := str(area.get("area_type", ""))
		if area.has("dominant_biome"):
			_fail("v70 RegionArea still has removed dominant_biome: %s" % region_id)
			return false
		if not ALLOWED_AREA_TYPES.has(area_type):
			_fail("v70 RegionArea has unsupported area_type: %s/%s" % [region_id, area_type])
			return false
		if SMALL_SCALE_TERMS.has(area_type):
			_fail("v70 RegionArea uses small-scale area_type: %s/%s" % [region_id, area_type])
			return false
		var display_name := str(area.get("display_name", ""))
		for small_term in ["山脚区域", "河岸区域", "入口区域", "小路区域", "空地区域", "岩坡区域", "溪流边区域"]:
			if display_name.contains(small_term):
				_fail("v70 RegionArea display name uses local-scale term: %s" % display_name)
				return false
	return true


func _assert_location_nodes_use_area_context(world_data: Dictionary) -> bool:
	var config: Dictionary = WorldGenerationProfileScript.resolve_generation_config({
		"world_id": str(world_data.get("world_id", "")),
		"world_seed": int(world_data.get("world_seed", 0)),
		"region_profile_id": PROFILE_ID,
	})
	var role_profile_map: Dictionary = config.get("area_role_profile_map", {}) as Dictionary
	var area_by_id := _region_area_by_id(world_data)
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if location.has("region_biome"):
			_fail("v70 location still has removed region_biome: %s" % location_id)
			return false
		var area_type := str(location.get("area_type", ""))
		var local_role := str(location.get("local_role", ""))
		var parent_region_id := str(location.get("parent_region_id", ""))
		var area: Dictionary = area_by_id.get(parent_region_id, {}) as Dictionary
		if area.is_empty() or str(area.get("area_type", "")) != area_type:
			_fail("v70 location area_type does not match parent RegionArea: %s" % location_id)
			return false
		if local_role.is_empty():
			_fail("v70 location missing local_role: %s" % location_id)
			return false
		var role_map: Dictionary = role_profile_map.get(area_type, {}) as Dictionary
		var profiles: Array = role_map.get(local_role, []) as Array
		if not profiles.has(str(location.get("generator_profile_id", ""))):
			_fail("v70 profile is not derived from area_type + local_role: %s" % location_id)
			return false
		if (location.get("region_cell", {}) as Dictionary).is_empty():
			_fail("v70 location missing region_cell: %s" % location_id)
			return false
		if (location.get("region_patch", {}) as Dictionary).is_empty():
			_fail("v70 location missing region_patch: %s" % location_id)
			return false
		if (location.get("region_context", {}) as Dictionary).is_empty():
			_fail("v70 location missing region_context: %s" % location_id)
			return false
	return true


func _assert_edges_use_area_relation(world_data: Dictionary) -> bool:
	for edge_value in (world_data.get("exits", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		var exit_id := str(edge.get("exit_id", ""))
		if edge.has("from_biome") or edge.has("to_biome") or edge.has("biome_relation"):
			_fail("v70 edge still has removed biome fields: %s" % exit_id)
			return false
		var relation := "%s_to_%s" % [str(edge.get("from_area_type", "")), str(edge.get("target_area_type", ""))]
		if str(edge.get("area_relation", "")) != relation:
			_fail("v70 edge area_relation mismatch: %s" % exit_id)
			return false
	return true


func _assert_map_view_reads_layered_region_map(world_data: Dictionary) -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v70 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v70 world load failed: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v70 world start failed: %s" % str(start_result.get("error", "")))
		return false
	var panel: RegionMapView = RegionMapViewScene.instantiate() as RegionMapView
	root.add_child(panel)
	panel.bind_world_service(world_service)
	panel.open_panel()
	var summary: Dictionary = panel.get_view_summary()
	if int(summary.get("region_width", 0)) <= 0 or int(summary.get("region_height", 0)) <= 0:
		_fail("v70 RegionMapView did not read RegionMap size")
		panel.queue_free()
		return false
	if bool(summary.get("grid_visible", true)):
		_fail("v70 RegionMapView reports debug grid visible")
		panel.queue_free()
		return false
	panel.queue_free()
	world_service.reset_world()
	return true


func _assert_unsupported_area_type_fails() -> bool:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v70_bad_area_type_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"area_role_profile_map": {
			"plain": {
				"field_entry": ["plain"],
			},
			"not_supported_area": {
				"field_entry": ["plain"],
			},
		},
	})
	if bool(result.get("success", false)):
		_fail("v70 unsupported area_type unexpectedly succeeded")
		return false
	if not str(result.get("errors", [])).contains("unsupported area_type"):
		_fail("v70 unsupported area_type did not expose explicit failure: %s" % str(result.get("errors", [])))
		return false
	return true


func _generated_world_data() -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v70_layered_region_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
	})
	if not bool(result.get("success", false)):
		_fail("v70 world generation failed: %s" % str(result.get("errors", [])))
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
