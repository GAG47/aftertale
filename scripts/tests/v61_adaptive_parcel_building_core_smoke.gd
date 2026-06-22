extends SceneTree

const VillageRoadGeneratorScript := preload("res://scripts/systems/scenes/village_road_generator.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = _load_json_resource("res://data/locations/test_village.json")
	var generator: RefCounted = VillageRoadGeneratorScript.new()
	var generated: Dictionary = generator.generate_location(source_data)
	var validation_errors: Array[String] = generator.validate_location_contract(generated)
	if not validation_errors.is_empty():
		_fail("v61 generated village has validation errors: %s" % str(validation_errors))
		return

	var summary: Dictionary = generated.get("generation_summary", {}) as Dictionary
	if str(summary.get("type", "")) != "agent_settlement_blueprint":
		_fail("v61 default generator did not use agent settlement blueprint")
		return
	if str(summary.get("parcel_shape_model", "")) != "cell_set_organic_growth_lot":
		_fail("v61 generator did not expose organic cell-set parcel model")
		return
	if str(summary.get("building_placement_model", "")) != "south_door_core_fitted_to_parcel_cells":
		_fail("v61 generator did not expose cell-set building core placement model")
		return
	if int(summary.get("compiler_recovery_count", 0)) != 0:
		_fail("v61 generator used compiler recovery: %s" % str(summary.get("compiler_recovery_log", [])))
		return
	for failure_value in (summary.get("building_adaptation_failures", []) as Array):
		var failure: Dictionary = failure_value as Dictionary
		if bool(failure.get("required", false)):
			_fail("v61 required building adaptation failed: %s" % str(failure))
			return
	var planner_summary: Dictionary = summary.get("planner", {}) as Dictionary
	if str(planner_summary.get("required_goal_policy", "")) != "priority_filtered_auction":
		_fail("v61 planner did not use required goal priority arbitration")
		return
	if not (planner_summary.get("required_goal_failures", []) as Array).is_empty():
		_fail("v61 planner left required goal failures: %s" % str(planner_summary.get("required_goal_failures", [])))
		return
	if str(planner_summary.get("parcel_shape_model", "")) != "cell_set_organic_growth_lot":
		_fail("v61 planner did not expose organic parcel shape model")
		return

	var parcel_cell_keys_by_id: Dictionary = {}
	var irregular_parcel_count := 0
	for parcel_value in (generated.get("parcels", []) as Array):
		var parcel: Dictionary = parcel_value as Dictionary
		var parcel_id := str(parcel.get("id", ""))
		var cells: Array = parcel.get("cells", []) as Array
		var bounds: Dictionary = parcel.get("bounds", {}) as Dictionary
		if parcel_id.is_empty() or cells.is_empty():
			_fail("v61 parcel missing id or cell set: %s" % parcel_id)
			return
		if int(parcel.get("cell_count", -1)) != cells.size():
			_fail("v61 parcel cell_count mismatch: %s" % parcel_id)
			return
		if not str(parcel.get("shape_model", "")).begins_with("cell_set"):
			_fail("v61 parcel is not marked as a cell-set shape: %s" % parcel_id)
			return
		if str(parcel.get("shape_model", "")) == "cell_set_notched_lot":
			_fail("v61 parcel still uses the transitional notched shape: %s" % parcel_id)
			return
		if str(parcel.get("growth_model", "")) != "frontier_expansion_from_road_access":
			_fail("v61 parcel did not record organic frontier growth: %s" % parcel_id)
			return
		var cell_keys := _cell_key_set(cells)
		parcel_cell_keys_by_id[parcel_id] = cell_keys
		var access_cell := _cell_from_dict(parcel.get("access_cell", {}) as Dictionary)
		if not cell_keys.has(_cell_key(access_cell)):
			_fail("v61 parcel access cell is outside its cell set: %s" % parcel_id)
			return
		if cells.size() < int(bounds.get("w", 0)) * int(bounds.get("h", 0)):
			irregular_parcel_count += 1
	if irregular_parcel_count <= 0:
		_fail("v61 generated no irregular parcel cell sets")
		return

	var building_count := 0
	var adaptive_yard_slot_count := 0
	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		building_count += 1
		var building_id := str(building.get("id", ""))
		var parcel_id := str(building.get("parcel_id", ""))
		var parcel_cell_keys: Dictionary = parcel_cell_keys_by_id.get(parcel_id, {}) as Dictionary
		if parcel_cell_keys.is_empty():
			_fail("v61 building references a parcel without cells: %s" % building_id)
			return
		if str(building.get("door_side", "")) != "south":
			_fail("v61 building door side is not south: %s" % building_id)
			return
		var core_placement: Dictionary = building.get("core_placement", {}) as Dictionary
		if str(core_placement.get("model", "")) != "south_door_core_fitted_to_parcel_cells":
			_fail("v61 building missing adaptive core placement record: %s" % building_id)
			return
		if str(core_placement.get("door_policy", "")) != "south_only":
			_fail("v61 building core does not enforce south-only doors: %s" % building_id)
			return
		var bounds: Dictionary = building.get("bounds", {}) as Dictionary
		if not _rect_inside_cell_set(bounds, parcel_cell_keys):
			_fail("v61 building core footprint leaves parcel cells: %s" % building_id)
			return
		var door := _cell_from_dict(building.get("door", {}) as Dictionary)
		var doorstep := _cell_from_dict(building.get("doorstep", {}) as Dictionary)
		if door.y != int(bounds.get("y", 0)) + int(bounds.get("h", 0)) - 1:
			_fail("v61 building door is not on the south edge: %s" % building_id)
			return
		if not parcel_cell_keys.has(_cell_key(door)) or not parcel_cell_keys.has(_cell_key(doorstep)):
			_fail("v61 building door or doorstep leaves parcel cells: %s" % building_id)
			return
		for path_value in (building.get("yard_path", []) as Array):
			var path_cell := _cell_from_dict(path_value as Dictionary)
			if not parcel_cell_keys.has(_cell_key(path_cell)):
				_fail("v61 yard path leaves parcel cells: %s" % building_id)
				return
		adaptive_yard_slot_count += (building.get("adaptive_yard_slots", []) as Array).size()
	if building_count < 3:
		_fail("v61 generated too few building cores")
		return
	if adaptive_yard_slot_count <= 0:
		_fail("v61 generated no parcel-adaptive yard slots")
		return

	print("v61 adaptive parcel building core smoke test passed")
	quit(0)


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _cell_key_set(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		result[_cell_key(cell)] = true
	return result


func _rect_inside_cell_set(rect: Dictionary, cell_keys: Dictionary) -> bool:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			if not cell_keys.has(_cell_key(Vector2i(x, y))):
				return false
	return true


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
