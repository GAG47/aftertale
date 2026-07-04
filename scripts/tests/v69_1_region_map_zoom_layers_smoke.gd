extends SceneTree

const WorldGraphGeneratorScript := preload("res://scripts/systems/world/world_graph_generator.gd")
const RegionMapViewScene := preload("res://scenes/ui/screens/region_map_screen.tscn")

const PROFILE_ID := "temperate_frontier"
const WORLD_SEED := 6911


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _assert_zoom_layer_view():
		return

	print("v69.1 region map zoom layers smoke test passed")
	quit(0)


func _assert_zoom_layer_view() -> bool:
	var world_service: Variant = root.get_node_or_null("WorldTransitionService")
	if world_service == null:
		_fail("v69.1 WorldTransitionService autoload is missing")
		return false
	world_service.reset_world()

	var world_data: Dictionary = _generated_world_data()
	if world_data.is_empty():
		return false
	var load_result: Dictionary = world_service.load_world_from_data(world_data)
	if not bool(load_result.get("success", false)):
		_fail("v69.1 generated world failed to load: %s" % str(load_result.get("error", "")))
		return false
	var start_result: Dictionary = world_service.start_world(false)
	if not bool(start_result.get("success", false)):
		_fail("v69.1 generated world failed to start: %s" % str(start_result.get("error", "")))
		return false

	var original_location_id := str(world_service.get_current_location_id())
	var view_data: Dictionary = world_service.get_region_map_view_data()
	if not _assert_world_view_data(view_data):
		world_service.reset_world()
		return false

	var panel: RegionMapView = RegionMapViewScene.instantiate() as RegionMapView
	root.add_child(panel)
	panel.size = Vector2(1280.0, 720.0)
	panel.bind_world_service(world_service)
	panel.open_panel()

	if not _assert_far_layer(panel):
		return _cleanup(false, panel, world_service)
	if not _assert_alpha_transition(panel):
		return _cleanup(false, panel, world_service)
	if not _assert_near_layer(panel, view_data):
		return _cleanup(false, panel, world_service)
	if not _assert_focus_priority(panel, view_data):
		return _cleanup(false, panel, world_service)
	if not _assert_selection_does_not_transition(panel, world_service, view_data, original_location_id):
		return _cleanup(false, panel, world_service)
	if not _assert_close_shortcuts(panel):
		return _cleanup(false, panel, world_service)

	return _cleanup(true, panel, world_service)


func _assert_world_view_data(view_data: Dictionary) -> bool:
	if (view_data.get("region_map", {}) as Dictionary).is_empty():
		_fail("v69.1 view data has no RegionMap")
		return false
	if (view_data.get("region_areas", []) as Array).is_empty():
		_fail("v69.1 view data has no RegionArea rows")
		return false
	if (view_data.get("locations", []) as Array).is_empty():
		_fail("v69.1 view data has no WorldLocationNode rows")
		return false
	if str(view_data.get("current_region_id", "")).is_empty():
		_fail("v69.1 view data has no current_region_id")
		return false
	return true


func _assert_far_layer(panel: RegionMapView) -> bool:
	panel.set_zoom_level(0.86)
	var summary: Dictionary = panel.get_view_summary()
	if not summary.has("zoom_level"):
		_fail("v69.1 summary does not expose zoom_level")
		return false
	if float(summary.get("region_layer_alpha", 0.0)) < 0.95:
		_fail("v69.1 far zoom should keep region layer visible")
		return false
	if float(summary.get("location_layer_alpha", 1.0)) > 0.05:
		_fail("v69.1 far zoom should hide location layer")
		return false
	if (summary.get("visible_region_area_ids", []) as Array).is_empty():
		_fail("v69.1 far zoom did not expose RegionArea ids")
		return false
	if not (summary.get("visible_location_ids", []) as Array).is_empty():
		_fail("v69.1 far zoom exposed WorldLocationNode ids")
		return false
	if str(summary.get("selection_type", "")) != "region_area":
		_fail("v69.1 far zoom should keep region selection type")
		return false
	return true


func _assert_alpha_transition(panel: RegionMapView) -> bool:
	panel.set_zoom_level(0.86)
	var far_summary: Dictionary = panel.get_view_summary()
	panel.set_zoom_level(1.32)
	var middle_summary: Dictionary = panel.get_view_summary()
	panel.set_zoom_level(1.90)
	var near_summary: Dictionary = panel.get_view_summary()

	var far_region_alpha := float(far_summary.get("region_layer_alpha", 0.0))
	var far_location_alpha := float(far_summary.get("location_layer_alpha", 0.0))
	var middle_region_alpha := float(middle_summary.get("region_layer_alpha", 0.0))
	var middle_location_alpha := float(middle_summary.get("location_layer_alpha", 0.0))
	var near_region_alpha := float(near_summary.get("region_layer_alpha", 0.0))
	var near_location_alpha := float(near_summary.get("location_layer_alpha", 0.0))

	if middle_region_alpha <= 0.05 or middle_region_alpha >= 0.95:
		_fail("v69.1 transition region alpha should be between hidden and visible")
		return false
	if middle_location_alpha <= 0.05 or middle_location_alpha >= 0.95:
		_fail("v69.1 transition location alpha should be between hidden and visible")
		return false
	if not (far_region_alpha > middle_region_alpha and middle_region_alpha > near_region_alpha):
		_fail("v69.1 region alpha did not fade continuously")
		return false
	if not (far_location_alpha < middle_location_alpha and middle_location_alpha < near_location_alpha):
		_fail("v69.1 location alpha did not fade continuously")
		return false
	return true


func _assert_near_layer(panel: RegionMapView, view_data: Dictionary) -> bool:
	panel.clear_pointer_region()
	panel.set_zoom_level(1.90)
	var summary: Dictionary = panel.get_view_summary()
	var focused_region_id := str(summary.get("focused_region_id", ""))
	if focused_region_id.is_empty():
		_fail("v69.1 near zoom has no focused_region_id")
		return false
	if float(summary.get("region_layer_alpha", 1.0)) > 0.05:
		_fail("v69.1 near zoom should hide region layer")
		return false
	if float(summary.get("location_layer_alpha", 0.0)) < 0.95:
		_fail("v69.1 near zoom should show location layer")
		return false
	if not (summary.get("visible_region_area_ids", []) as Array).is_empty():
		_fail("v69.1 near zoom still exposes RegionArea ids")
		return false
	var visible_location_ids: Array = summary.get("visible_location_ids", []) as Array
	if visible_location_ids.is_empty():
		_fail("v69.1 near zoom did not expose focused-region locations")
		return false
	var location_by_id: Dictionary = _location_by_id(view_data)
	for location_id_value in visible_location_ids:
		var location_id := str(location_id_value)
		var location: Dictionary = location_by_id.get(location_id, {}) as Dictionary
		if str(location.get("parent_region_id", "")) != focused_region_id:
			_fail("v69.1 near zoom exposed a location outside the focused region: %s" % location_id)
			return false
	var edge_by_id: Dictionary = _edge_by_id(view_data)
	for edge_id_value in (summary.get("visible_location_edge_ids", []) as Array):
		var edge_id := str(edge_id_value)
		var edge: Dictionary = edge_by_id.get(edge_id, {}) as Dictionary
		if str(edge.get("edge_scope", "")) != "internal_region":
			_fail("v69.1 near zoom exposed a non-internal edge: %s" % edge_id)
			return false
		if str(edge.get("from_region_id", "")) != focused_region_id or str(edge.get("target_region_id", "")) != focused_region_id:
			_fail("v69.1 near zoom exposed an edge outside the focused region: %s" % edge_id)
			return false
	return true


func _assert_focus_priority(panel: RegionMapView, view_data: Dictionary) -> bool:
	var current_region_id := str(view_data.get("current_region_id", ""))
	var other_region_id := _different_region_id(view_data, current_region_id)
	if other_region_id.is_empty():
		_fail("v69.1 generated world has no second RegionArea to test hover focus")
		return false
	panel.clear_pointer_region()
	panel.set_zoom_level(1.90)
	var current_summary: Dictionary = panel.get_view_summary()
	if str(current_summary.get("focused_region_id", "")) != current_region_id:
		_fail("v69.1 focus without hover should use current player RegionArea")
		return false
	if not panel.set_pointer_region_id(other_region_id):
		_fail("v69.1 could not set pointer RegionArea")
		return false
	var hover_summary: Dictionary = panel.get_view_summary()
	if str(hover_summary.get("focused_region_id", "")) != other_region_id:
		_fail("v69.1 hovered RegionArea did not become focused_region_id")
		return false
	panel.clear_pointer_region()
	return true


func _assert_selection_does_not_transition(panel: RegionMapView, world_service: Variant, view_data: Dictionary, original_location_id: String) -> bool:
	var first_area: Dictionary = ((view_data.get("region_areas", []) as Array)[0] as Dictionary)
	var region_id := str(first_area.get("region_id", ""))
	if region_id.is_empty():
		_fail("v69.1 cannot select first RegionArea")
		return false
	if not panel.select_region(region_id):
		_fail("v69.1 RegionArea selection failed")
		return false
	if str(world_service.get_current_location_id()) != original_location_id:
		_fail("v69.1 RegionArea selection changed current location")
		return false
	var region_summary: Dictionary = panel.get_view_summary()
	if str(region_summary.get("selection_type", "")) != "region_area":
		_fail("v69.1 RegionArea selection did not mark selection_type")
		return false

	var location_id := _first_location_id_for_region(view_data, str(region_summary.get("focused_region_id", "")))
	if location_id.is_empty():
		location_id = _first_location_id(view_data)
	if location_id.is_empty():
		_fail("v69.1 cannot select any WorldLocationNode")
		return false
	if not panel.select_location(location_id):
		_fail("v69.1 WorldLocationNode selection failed")
		return false
	if str(world_service.get_current_location_id()) != original_location_id:
		_fail("v69.1 WorldLocationNode selection changed current location")
		return false
	var location_summary: Dictionary = panel.get_view_summary()
	if str(location_summary.get("selection_type", "")) != "location_node":
		_fail("v69.1 WorldLocationNode selection did not mark selection_type")
		return false
	return true


func _assert_close_shortcuts(panel: RegionMapView) -> bool:
	var closed := { "value": false }
	panel.close_requested.connect(func() -> void:
		closed["value"] = true
	)
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	panel._gui_input(event)
	if not bool(closed.get("value", false)):
		_fail("v69.1 M key did not request map close")
		return false
	closed["value"] = false
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	panel._gui_input(event)
	if not bool(closed.get("value", false)):
		_fail("v69.1 Esc key did not request map close")
		return false
	return true


func _generated_world_data() -> Dictionary:
	var generator: RefCounted = WorldGraphGeneratorScript.new()
	var result: Dictionary = generator.generate_world_data_result({
		"world_id": "v69_1_region_map_zoom_layers_world",
		"world_seed": WORLD_SEED,
		"region_profile_id": PROFILE_ID,
		"node_count_range": [8, 10],
		"connection_density": 1.45,
	})
	if not bool(result.get("success", false)):
		_fail("v69.1 world generation failed: %s" % str(result.get("errors", [])))
		return {}
	return result.get("world_data", {}) as Dictionary


func _location_by_id(view_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for location_value in (view_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if not location_id.is_empty():
			result[location_id] = location
	return result


func _edge_by_id(view_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for edge_value in (view_data.get("edges", []) as Array):
		var edge: Dictionary = edge_value as Dictionary
		var exit_id := str(edge.get("exit_id", ""))
		if not exit_id.is_empty():
			result[exit_id] = edge
	return result


func _different_region_id(view_data: Dictionary, current_region_id: String) -> String:
	for area_value in (view_data.get("region_areas", []) as Array):
		var area: Dictionary = area_value as Dictionary
		var region_id := str(area.get("region_id", ""))
		if not region_id.is_empty() and region_id != current_region_id:
			return region_id
	return ""


func _first_location_id_for_region(view_data: Dictionary, region_id: String) -> String:
	if region_id.is_empty():
		return ""
	for location_value in (view_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		if str(location.get("parent_region_id", "")) == region_id:
			return str(location.get("location_id", ""))
	return ""


func _first_location_id(view_data: Dictionary) -> String:
	for location_value in (view_data.get("locations", []) as Array):
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		if not location_id.is_empty():
			return location_id
	return ""


func _cleanup(success: bool, panel: RegionMapView, world_service: Variant) -> bool:
	if is_instance_valid(panel):
		panel.queue_free()
	world_service.reset_world()
	return success


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
