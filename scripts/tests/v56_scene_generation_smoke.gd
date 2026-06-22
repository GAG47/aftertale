extends SceneTree

const VillageRoadGeneratorScript := preload("res://scripts/systems/scenes/village_road_generator.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = _load_json_resource("res://data/locations/test_village.json")
	var generator: RefCounted = VillageRoadGeneratorScript.new()
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

	var required_anchor_ids: Array[String] = [
		"plaza_social_spot",
		"training_yard_guard_post",
		"wild_gate_guard_post",
		"field_work_spot",
	]
	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		required_anchor_ids.append(str(building.get("exterior_door_anchor_id", "")))
	if (generated.get("buildings", []) as Array).is_empty():
		_fail("v56 generated village has no building instances")
		return
	if (generated.get("interiors", []) as Array).is_empty():
		_fail("v56 generated village has no interior instances")
		return
	if (generated.get("parcels", []) as Array).is_empty():
		_fail("v57 generated village has no parcels")
		return
	if (generated.get("building_prefabs", []) as Array).is_empty():
		_fail("v57 generated village has no placeholder building prefab library")
		return
	if str(generated.get("building_prefab_catalog", "")).is_empty():
		_fail("v58 generated village missing building prefab catalog source")
		return
	var town_zone_ids: Dictionary = {}
	for zone_value in (generated.get("town_zones", []) as Array):
		var zone: Dictionary = zone_value as Dictionary
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty():
			_fail("v59 generated town zone missing id")
			return
		town_zone_ids[zone_id] = true
	for required_zone in ["plaza", "residential", "market", "farm", "training", "gate"]:
		if not town_zone_ids.has(required_zone):
			_fail("v59 generated village missing town zone: %s" % required_zone)
			return

	var parcel_ids: Dictionary = {}
	for parcel_value in (generated.get("parcels", []) as Array):
		var parcel: Dictionary = parcel_value as Dictionary
		var parcel_id := str(parcel.get("id", ""))
		if parcel_id.is_empty():
			_fail("v57 generated parcel missing id")
			return
		parcel_ids[parcel_id] = true
		if str(parcel.get("door_side", "")) != "south":
			_fail("v57 generated parcel door side is not south: %s" % parcel_id)
			return
		if (parcel.get("door_slot", {}) as Dictionary).is_empty():
			_fail("v57 generated parcel missing door_slot: %s" % parcel_id)
			return
		var semantic_zone_id := str(parcel.get("semantic_zone_id", ""))
		if semantic_zone_id.is_empty() or not town_zone_ids.has(semantic_zone_id):
			_fail("v59 generated parcel missing valid semantic zone: %s / %s" % [parcel_id, semantic_zone_id])
			return

	var prefab_ids: Dictionary = {}
	for prefab_value in (generated.get("building_prefabs", []) as Array):
		var prefab: Dictionary = prefab_value as Dictionary
		var prefab_id := str(prefab.get("id", ""))
		if prefab_id.is_empty():
			_fail("v57 generated building prefab missing id")
			return
		prefab_ids[prefab_id] = true
		if str(prefab.get("door_side", "")) != "south":
			_fail("v57 generated building prefab door side is not south: %s" % prefab_id)
			return
		var exterior_slot_contract: Dictionary = prefab.get("exterior_slot_contract", {}) as Dictionary
		if str(exterior_slot_contract.get("content_source", "")) != "prefab_declared_only":
			_fail("v58 generated building prefab must declare prefab-only exterior slot source: %s" % prefab_id)
			return
		if str(exterior_slot_contract.get("coordinate_space", "")) != "prefab_local_grid":
			_fail("v58 generated building prefab must use prefab_local_grid exterior slots: %s" % prefab_id)
			return
		var visual: Dictionary = prefab.get("visual", {}) as Dictionary
		if str(visual.get("placeholder_style", "")).is_empty():
			_fail("v58 generated building prefab missing visual placeholder style: %s" % prefab_id)
			return
		for slot_value in (prefab.get("exterior_slots", []) as Array):
			var slot: Dictionary = slot_value as Dictionary
			if str(slot.get("id", "")).is_empty():
				_fail("v58 generated building prefab exterior slot missing id: %s" % prefab_id)
				return
			if (slot.get("local_position", {}) as Dictionary).is_empty():
				_fail("v58 generated building prefab exterior slot missing local_position: %s" % prefab_id)
				return
			if bool(slot.get("blocks_movement", false)) or bool(slot.get("blocks_sight", false)):
				_fail("v58 generated building prefab exterior slot blocks gameplay: %s / %s" % [prefab_id, str(slot.get("id", ""))])
				return

	var floor_overlay_counts: Dictionary = {
		"parcel_surface": 0,
		"front_clearance": 0,
		"front_path": 0,
		"building_foundation": 0,
	}
	for overlay_value in (generated.get("floor_overlays", []) as Array):
		var overlay: Dictionary = overlay_value as Dictionary
		var overlay_type := str(overlay.get("type", ""))
		if floor_overlay_counts.has(overlay_type):
			floor_overlay_counts[overlay_type] = int(floor_overlay_counts.get(overlay_type, 0)) + 1
	var building_count := (generated.get("buildings", []) as Array).size()
	for overlay_type in floor_overlay_counts.keys():
		if int(floor_overlay_counts.get(overlay_type, 0)) < building_count:
			_fail("v58 generated village missing parcel presentation overlays: %s" % overlay_type)
			return

	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var building_id := str(building.get("id", ""))
		if not parcel_ids.has(str(building.get("parcel_id", ""))):
			_fail("v57 generated building references missing parcel: %s" % building_id)
			return
		if not prefab_ids.has(str(building.get("prefab_id", ""))):
			_fail("v57 generated building references missing prefab: %s" % building_id)
			return
		if str(building.get("door_side", "")) != "south":
			_fail("v57 generated building door side is not south: %s" % building_id)
			return
		var prefab_contract: Dictionary = building.get("prefab_contract", {}) as Dictionary
		var building_slot_contract: Dictionary = prefab_contract.get("exterior_slot_contract", {}) as Dictionary
		if str(building_slot_contract.get("content_source", "")) != "prefab_declared_only":
			_fail("v58 generated building missing prefab-only exterior slot contract: %s" % building_id)
			return
		var declared_slots: Array = prefab_contract.get("exterior_slots", []) as Array
		var materialized_slots: Array = building.get("materialized_exterior_slots", []) as Array
		var core_placement: Dictionary = building.get("core_placement", {}) as Dictionary
		var uses_adaptive_core := str(core_placement.get("model", "")) == "south_door_core_fitted_to_parcel_cells"
		if not uses_adaptive_core and materialized_slots.size() != declared_slots.size():
			_fail("v58 generated building did not materialize all declared exterior slots: %s" % building_id)
			return

	for anchor_id in required_anchor_ids:
		if anchor_id.is_empty():
			_fail("v56 generated building missing exterior door anchor id")
			return
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
			var scheduled_location_id := str(entry.get("location_id", str(generated.get("id", ""))))
			var anchor_id: String = str(entry.get("anchor_id", ""))
			if anchor_id.is_empty():
				_fail("v56 schedule entry missing anchor_id: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
				return
			if entry.has("grid_position"):
				_fail("v56 schedule entry should not hand-author grid_position: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
				return
			if scheduled_location_id == str(generated.get("id", "")) and grid.get_anchor(anchor_id).is_empty():
				_fail("v56 schedule references missing generated anchor: %s" % anchor_id)
				return
			if scheduled_location_id != str(generated.get("id", "")):
				var anchors_by_location: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
				var transition_anchor_id := str(anchors_by_location.get(str(generated.get("id", "")), ""))
				if transition_anchor_id.is_empty():
					_fail("v56 cross-scene schedule missing transition anchor: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
					return
				if grid.get_anchor(transition_anchor_id).is_empty():
					_fail("v56 cross-scene schedule references missing transition anchor: %s" % transition_anchor_id)
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


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


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
