extends SceneTree

const VillageBspGeneratorScript := preload("res://scripts/systems/scenes/village_bsp_generator.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = DefinitionLoader.load_location("res://data/locations/test_village.json")
	var generator: RefCounted = VillageBspGeneratorScript.new()
	var generated: Dictionary = generator.generate_location(source_data)
	var grid: LocationGrid = LocationGrid.from_dictionary(generated)
	if not grid.is_valid():
		_fail("v56 generated village grid is invalid")
		return

	var object_blockers: Dictionary = _blocking_object_cells(generated)
	var plaza_cell: Vector2i = _entrance_cell(generated, "plaza")
	if plaza_cell == Vector2i(-1, -1):
		_fail("v56 generated village is missing plaza entrance")
		return
	if not _is_open_cell(grid, plaza_cell, object_blockers):
		_fail("v56 plaza entrance is not open")
		return

	for anchor_id in [
		"house_sleep_spot",
		"workbench_spot",
		"shop_counter_spot",
		"tavern_table_spot",
		"plaza_social_spot",
		"training_yard_guard_post",
		"wild_gate_guard_post",
		"field_work_spot",
	]:
		var anchor: Dictionary = grid.get_anchor(anchor_id)
		if anchor.is_empty():
			_fail("v56 generated village missing anchor: %s" % anchor_id)
			return
		var anchor_cell: Vector2i = _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
		if not _is_open_cell(grid, anchor_cell, object_blockers):
			_fail("v56 generated anchor is blocked: %s at %s" % [anchor_id, anchor_cell])
			return
		if not _has_path(grid, plaza_cell, anchor_cell, object_blockers):
			_fail("v56 generated anchor is unreachable: %s at %s" % [anchor_id, anchor_cell])
			return
		for activity_value in (anchor.get("activity_cells", []) as Array):
			var activity_cell := _cell_from_dict(activity_value as Dictionary)
			if not _is_open_cell(grid, activity_cell, object_blockers):
				_fail("v56 generated activity cell is blocked: %s at %s" % [anchor_id, activity_cell])
				return

	for object_value in (generated.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		var object_cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		if not grid.in_bounds(object_cell):
			_fail("v56 generated object out of bounds: %s" % str(object_data.get("id", "")))
			return
		if bool(object_data.get("is_usable", false)) or bool(object_data.get("is_inspectable", false)):
			if not _has_reachable_adjacent_cell(grid, plaza_cell, object_cell, object_blockers):
				_fail("v56 generated object has no reachable interaction side: %s" % str(object_data.get("id", "")))
				return

	for exit_value in (generated.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_cell: Vector2i = _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not _has_path(grid, plaza_cell, exit_cell, object_blockers):
			_fail("v56 generated exit is unreachable: %s" % str(exit_data.get("id", "")))
			return

	for roof_value in (generated.get("roofs", []) as Array):
		var roof: Dictionary = roof_value as Dictionary
		if (roof.get("hide_bounds", {}) as Dictionary).is_empty():
			_fail("v56 generated roof missing hide_bounds: %s" % str(roof.get("id", "")))
			return

	for character_value in (generated.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		for schedule_value in (character.get("schedule", []) as Array):
			var entry: Dictionary = schedule_value as Dictionary
			var anchor_id: String = str(entry.get("anchor_id", ""))
			if anchor_id.is_empty():
				_fail("v56 schedule entry missing anchor_id: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
				return
			if entry.has("grid_position"):
				_fail("v56 schedule entry should not hand-author grid_position: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
				return
			if grid.get_anchor(anchor_id).is_empty():
				_fail("v56 schedule references missing generated anchor: %s" % anchor_id)
				return

	print("v56 scene generation smoke test passed")
	quit(0)


func _blocking_object_cells(generated: Dictionary) -> Dictionary:
	var blockers: Dictionary = {}
	for object_value in (generated.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		if not bool(object_data.get("blocks_movement", true)):
			continue
		var cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		blockers[_cell_key(cell)] = str(object_data.get("id", ""))
	return blockers


func _has_reachable_adjacent_cell(grid: LocationGrid, start_cell: Vector2i, target_cell: Vector2i, blockers: Dictionary) -> bool:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var adjacent: Vector2i = target_cell + direction
		if not _is_open_cell(grid, adjacent, blockers):
			continue
		if _has_path(grid, start_cell, adjacent, blockers):
			return true
	return false


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
			var next_cell: Vector2i = current + direction
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
