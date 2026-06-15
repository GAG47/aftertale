extends SceneTree

const VillageRoadGeneratorScript := preload("res://scripts/systems/scenes/village_road_generator.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = DefinitionLoader.load_location("res://data/locations/test_village.json")
	var generator: RefCounted = VillageRoadGeneratorScript.new()
	var generated: Dictionary = generator.generate_location(source_data)
	var grid: LocationGrid = LocationGrid.from_dictionary(generated)
	if not grid.is_valid():
		_fail("v60.1 generated village grid is invalid")
		return

	if not (generated.get("buildings", []) as Array).is_empty():
		_fail("v60.1 must not generate buildings")
		return
	if not (generated.get("parcels", []) as Array).is_empty():
		_fail("v60.1 must not generate parcels")
		return
	if not (generated.get("interiors", []) as Array).is_empty():
		_fail("v60.1 must not generate interiors")
		return
	if generated.has("building_prefabs") or generated.has("building_prefab_catalog"):
		_fail("v60.1 must not expose building prefab data")
		return

	var object_blockers := _blocking_object_cells(generated)
	var plaza_cell := _entrance_cell(generated, "plaza")
	if plaza_cell == Vector2i(-1, -1):
		_fail("v60.1 generated village is missing plaza entrance")
		return
	if not _is_open_cell(grid, plaza_cell, object_blockers):
		_fail("v60.1 plaza entrance is not open")
		return

	var town_zone_ids: Dictionary = {}
	for zone_value in (generated.get("town_zones", []) as Array):
		var zone: Dictionary = zone_value as Dictionary
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty():
			_fail("v60.1 generated town zone missing id")
			return
		town_zone_ids[zone_id] = true
	for required_zone in ["plaza", "farm", "training", "gate"]:
		if not town_zone_ids.has(required_zone):
			_fail("v60.1 generated village missing town zone: %s" % required_zone)
			return

	for anchor_id in ["plaza_social_spot", "training_yard_guard_post", "wild_gate_guard_post", "field_work_spot"]:
		var anchor: Dictionary = grid.get_anchor(anchor_id)
		if anchor.is_empty():
			_fail("v60.1 generated village missing anchor: %s" % anchor_id)
			return
		var anchor_cell := _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
		if not _is_open_cell(grid, anchor_cell, object_blockers):
			_fail("v60.1 generated anchor is blocked: %s at %s" % [anchor_id, anchor_cell])
			return
		if not _has_path(grid, plaza_cell, anchor_cell, object_blockers):
			_fail("v60.1 generated anchor is unreachable: %s at %s" % [anchor_id, anchor_cell])
			return

	for exit_value in (generated.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not _has_path(grid, plaza_cell, exit_cell, object_blockers):
			_fail("v60.1 generated exit is unreachable: %s" % str(exit_data.get("id", "")))
			return

	var summary: Dictionary = generated.get("generation_summary", {}) as Dictionary
	if str(summary.get("type", "")) != "village_road_skeleton":
		_fail("v60.1 generated summary has wrong type")
		return
	if int(summary.get("road_cell_count", 0)) <= 0:
		_fail("v60.1 generated road skeleton has no road cells")
		return
	if int(summary.get("branch_count", 0)) < 2:
		_fail("v60.1 generated road skeleton has too few branches")
		return

	print("v60.1 road skeleton smoke test passed")
	quit(0)


func _blocking_object_cells(generated: Dictionary) -> Dictionary:
	var blockers: Dictionary = {}
	for object_value in (generated.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		if not bool(object_data.get("blocks_movement", true)):
			continue
		var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		blockers[_cell_key(cell)] = str(object_data.get("id", ""))
	return blockers


func _has_path(grid: LocationGrid, start_cell: Vector2i, target_cell: Vector2i, blockers: Dictionary) -> bool:
	if not _is_open_cell(grid, start_cell, blockers):
		return false
	if not _is_open_cell(grid, target_cell, blockers):
		return false
	var frontier: Array[Vector2i] = [start_cell]
	var visited: Dictionary = { _cell_key(start_cell): true }
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front() as Vector2i
		if current == target_cell:
			return true
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next_cell := current + direction
			var key := _cell_key(next_cell)
			if visited.has(key):
				continue
			if not _is_open_cell(grid, next_cell, blockers):
				continue
			visited[key] = true
			frontier.append(next_cell)
	return false


func _is_open_cell(grid: LocationGrid, cell: Vector2i, blockers: Dictionary) -> bool:
	if not grid.in_bounds(cell):
		return false
	if not grid.is_walkable(cell):
		return false
	return not blockers.has(_cell_key(cell))


func _entrance_cell(generated: Dictionary, entrance_id: String) -> Vector2i:
	for entrance_value in (generated.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return _cell_from_dict(entrance.get("grid_position", {}) as Dictionary)
	return Vector2i(-1, -1)


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
