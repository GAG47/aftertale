extends SceneTree

const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const RegionMapViewScene := preload("res://scenes/ui/screens/region_map_screen.tscn")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6801
const DEFAULT_WORLD_SEED := 6501
const REMOVED_ENTRY_KEY := "default" + "_entrance"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_region_map_view_data():
		return
	if not _assert_default_world_start_exits_compile_without_overlap():
		return

	print("v68 region map view smoke test passed")
	quit(0)


func _assert_region_map_view_data() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v68 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()

	var world_data := _generated_world_data()
	if world_data.is_empty():
		return false
	if not _assert_generated_location_display_names(world_data):
		return false
	if JSON.stringify(world_data).contains(REMOVED_ENTRY_KEY):
		_fail("v68 generated world data contains removed entry key")
		return false

	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v68 generated world failed to load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v68 generated world failed to start: %s" % str(start_result.get("error", "")))
		return false

	var start_location_id := str(world_data.get("start_location_id", ""))
	var view_data: Dictionary = world_service.get_region_map_view_data()
	if not _assert_view_data_matches_world(view_data, world_data, start_location_id):
		return false

	var panel: RegionMapView = RegionMapViewScene.instantiate() as RegionMapView
	root.add_child(panel)
	panel.bind_world_service(world_service)
	panel.open_panel()
	var summary: Dictionary = panel.get_view_summary()
	if int(summary.get("region_width", 0)) <= 0 or int(summary.get("region_height", 0)) <= 0:
		_fail("v68 RegionMapView did not read region map size")
		panel.queue_free()
		return false
	if int(summary.get("location_count", 0)) != (world_data.get("locations", []) as Array).size():
		_fail("v68 RegionMapView location count mismatch")
		panel.queue_free()
		return false
	if str(summary.get("display_current_location_id", "")) != start_location_id:
		_fail("v68 RegionMapView did not select the current location")
		panel.queue_free()
		return false
	if not bool(summary.get("node_labels_enabled", false)):
		_fail("v68 RegionMapView did not report node label drawing")
		panel.queue_free()
		return false
	if not bool(summary.get("road_lines_enabled", false)):
		_fail("v68 RegionMapView did not report road-style connection drawing")
		panel.queue_free()
		return false
	if not bool(summary.get("adventure_style_enabled", false)):
		_fail("v68 RegionMapView did not report adventure map styling")
		panel.queue_free()
		return false
	if bool(summary.get("grid_visible", true)):
		_fail("v68 RegionMapView still reports visible debug grid")
		panel.queue_free()
		return false
	if str(summary.get("current_marker_style", "")) != "pin":
		_fail("v68 RegionMapView did not report pin-style current marker")
		panel.queue_free()
		return false

	var next_edge := _first_edge_from(world_service, start_location_id)
	if next_edge.is_empty():
		_fail("v68 generated world has no edge from start location")
		panel.queue_free()
		return false
	var target_location_id := str(next_edge.get("target_location_id", ""))
	var transition_result: Dictionary = world_service.transition_by_exit_id(str(next_edge.get("exit_id", "")), false)
	if not bool(transition_result.get("success", false)):
		_fail("v68 world transition failed: %s" % str(transition_result.get("error", "")))
		panel.queue_free()
		return false

	var moved_view_data: Dictionary = world_service.get_region_map_view_data()
	if str(moved_view_data.get("current_location_id", "")) != target_location_id:
		_fail("v68 map view data did not update current location after transition")
		panel.queue_free()
		return false
	if str(moved_view_data.get("display_current_location_id", "")) != target_location_id:
		_fail("v68 map view data did not update displayed current location after transition")
		panel.queue_free()
		return false
	if JSON.stringify(moved_view_data).contains(REMOVED_ENTRY_KEY):
		_fail("v68 map view data contains removed entry key")
		panel.queue_free()
		return false

	panel.refresh()
	var moved_summary: Dictionary = panel.get_view_summary()
	if str(moved_summary.get("display_current_location_id", "")) != target_location_id:
		_fail("v68 RegionMapView did not refresh current location after transition")
		panel.queue_free()
		return false
	panel.close_panel()
	panel.queue_free()
	world_service.reset_world()
	return true


func _generated_world_data() -> Dictionary:
	return _generated_world_data_for("v68_region_map_view_world", WORLD_SEED)


func _generated_world_data_for(world_id: String, seed: int) -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": world_id,
		"world_seed": seed,
		"region_profile_id": PROFILE_ID,
	})
	if not bool(result.get("success", false)):
		_fail("v68 world generation failed: %s" % str(result.get("errors", [])))
		return {}
	return result.get("world_data", {}) as Dictionary


func _assert_default_world_start_exits_compile_without_overlap() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v68 WorldTransitionService autoload is missing for default-world exit check")
		return false
	world_service.reset_world()
	var world_data := _generated_world_data_for("generated_default_world", DEFAULT_WORLD_SEED)
	if world_data.is_empty():
		return false
	if not _assert_generated_location_display_names(world_data):
		return false
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v68 default world failed to load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v68 default world failed to start: %s" % str(start_result.get("error", "")))
		return false
	var start_location_id := str(world_data.get("start_location_id", ""))
	var graph_edges: Array = world_service.get_edges_from(start_location_id)
	var location_data: Dictionary = world_service.get_registered_location_data(start_location_id)
	if location_data.is_empty():
		_fail("v68 default world start location was not materialized")
		return false
	var compiled_exits: Array = location_data.get("exits", []) as Array
	if compiled_exits.size() < graph_edges.size():
		_fail("v68 default world start location has fewer runtime exits than world edges")
		return false
	var compiled_exit_ids := {}
	var compiled_exit_cells := {}
	for exit_value in compiled_exits:
		var exit_data: Dictionary = exit_value as Dictionary
		var world_exit_id := str(exit_data.get("world_exit_id", ""))
		if not world_exit_id.is_empty():
			compiled_exit_ids[world_exit_id] = true
		var cell: Dictionary = exit_data.get("grid_position", {}) as Dictionary
		var cell_key := "%d,%d" % [int(cell.get("x", -1)), int(cell.get("y", -1))]
		if compiled_exit_cells.has(cell_key):
			_fail("v68 default world start location has overlapping runtime exits at %s" % cell_key)
			return false
		compiled_exit_cells[cell_key] = true
	for edge_value in graph_edges:
		var edge: Dictionary = edge_value as Dictionary
		var exit_id := str(edge.get("exit_id", ""))
		if not compiled_exit_ids.has(exit_id):
			_fail("v68 default world edge has no compiled runtime exit: %s" % exit_id)
			return false
	var grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if grid.exits_by_cell.size() != compiled_exits.size():
		_fail("v68 default world LocationGrid collapsed overlapping exits")
		return false
	world_service.reset_world()
	return true


func _assert_generated_location_display_names(world_data: Dictionary) -> bool:
	var profile_labels := {
		"plain": "平原野地",
		"forest_edge": "林缘野地",
		"riverbank": "河岸野地",
		"foothill": "山脚野地",
	}
	for location_value in (world_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("location_kind", "")) != "generated_wild":
			continue
		var location_id := str(location.get("location_id", ""))
		var profile_id := str(location.get("generator_profile_id", ""))
		var display_name := str(location.get("display_name", ""))
		if location_id.is_empty():
			_fail("v68 generated location has no location_id")
			return false
		if display_name.is_empty() or display_name == location_id:
			_fail("v68 generated location has no separate display name: %s" % location_id)
			return false
		if display_name.contains("Wild"):
			_fail("v68 generated location display name still uses English Wild label: %s" % display_name)
			return false
		if not profile_labels.has(profile_id):
			_fail("v68 generated location profile has no Chinese display label in test: %s" % profile_id)
			return false
		if not display_name.begins_with(str(profile_labels.get(profile_id, ""))):
			_fail("v68 generated location display name does not match its profile: %s -> %s" % [profile_id, display_name])
			return false
	return true


func _assert_view_data_matches_world(view_data: Dictionary, world_data: Dictionary, expected_current_location_id: String) -> bool:
	if view_data.is_empty():
		_fail("v68 map view data is empty")
		return false
	if (view_data.get("region_map", {}) as Dictionary).is_empty():
		_fail("v68 map view data has no RegionMap")
		return false
	if (view_data.get("locations", []) as Array).size() != (world_data.get("locations", []) as Array).size():
		_fail("v68 map view data location count mismatch")
		return false
	if (view_data.get("edges", []) as Array).size() != (world_data.get("exits", []) as Array).size():
		_fail("v68 map view data edge count mismatch")
		return false
	if str(view_data.get("current_location_id", "")) != expected_current_location_id:
		_fail("v68 map view data current location mismatch")
		return false
	if str(view_data.get("display_current_location_id", "")) != expected_current_location_id:
		_fail("v68 map view data display current location mismatch")
		return false
	var region_map: Dictionary = view_data.get("region_map", {}) as Dictionary
	if int(region_map.get("width", 0)) <= 0 or int(region_map.get("height", 0)) <= 0:
		_fail("v68 RegionMap has invalid size")
		return false
	var biome_map: Array = region_map.get("biome_map", []) as Array
	if biome_map.is_empty():
		_fail("v68 RegionMap has no biome map")
		return false
	return true


func _first_edge_from(world_service: Variant, location_id: String) -> Dictionary:
	for edge_value in world_service.get_edges_from(location_id):
		var edge: Dictionary = edge_value as Dictionary
		if bool(edge.get("enabled", true)):
			return edge
	return {}


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
