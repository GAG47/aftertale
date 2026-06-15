class_name VillageRoadGenerator
extends RefCounted

const DEFAULT_WIDTH := 36
const DEFAULT_HEIGHT := 24
const DEFAULT_TILE_SIZE := 32

var _rng := RandomNumberGenerator.new()
var _width: int = DEFAULT_WIDTH
var _height: int = DEFAULT_HEIGHT
var _tiles: Array[Array] = []
var _anchor_cells: Dictionary = {}
var _placement_log: Array[Dictionary] = []
var _generated: Dictionary = {}


func generate_location(source_data: Dictionary) -> Dictionary:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	_rng.seed = int(generator_data.get("seed", 5601))
	var size: Dictionary = generator_data.get("size", source_data.get("size", {})) as Dictionary
	_width = max(24, int(size.get("width", DEFAULT_WIDTH)))
	_height = max(18, int(size.get("height", DEFAULT_HEIGHT)))
	_reset_tiles()

	var road_skeleton := _build_road_skeleton()
	_generated = _base_location(source_data)
	_apply_road_skeleton(road_skeleton)
	_apply_plaza(road_skeleton.get("plaza", {}) as Dictionary)
	_apply_farm(road_skeleton.get("farm", {}) as Dictionary)
	_apply_training_yard(road_skeleton.get("training", {}) as Dictionary)
	_apply_wild_gate(road_skeleton.get("gate", {}) as Dictionary)
	_add_common_decorations()
	_add_generated_characters()
	_generated["tiles"] = _stringify_tiles()
	_generated["generation_summary"] = {
		"type": "village_road_skeleton",
		"seed": int(generator_data.get("seed", 5601)),
		"road_cell_count": (road_skeleton.get("road_cells", []) as Array).size(),
		"branch_count": (road_skeleton.get("branches", []) as Array).size(),
		"placement_log": _placement_log.duplicate(true),
	}

	var contract_errors := validate_location_contract(_generated)
	for error in contract_errors:
		push_error("VillageRoadGenerator contract error: %s" % error)
	return _generated


func validate_location_contract(location_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var grid := LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		errors.append("generated LocationGrid is invalid")
		return errors

	if not (location_data.get("buildings", []) as Array).is_empty():
		errors.append("v60.1 road skeleton must not generate buildings")
	if not (location_data.get("parcels", []) as Array).is_empty():
		errors.append("v60.1 road skeleton must not generate parcels")
	if not (location_data.get("interiors", []) as Array).is_empty():
		errors.append("v60.1 road skeleton must not generate interiors")
	if location_data.has("building_prefabs") or location_data.has("building_prefab_catalog"):
		errors.append("v60.1 road skeleton must not expose building prefab data")

	var blockers := _contract_blocking_object_cells(location_data)
	var plaza_cell := _contract_entrance_cell(location_data, "plaza")
	if plaza_cell == Vector2i(-1, -1):
		errors.append("missing plaza entrance")
		return errors
	if not _contract_is_open_cell(grid, plaza_cell, blockers):
		errors.append("plaza entrance is blocked")

	var town_zone_ids: Dictionary = {}
	for zone_value in (location_data.get("town_zones", []) as Array):
		var zone: Dictionary = zone_value as Dictionary
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty():
			errors.append("town zone missing id")
			continue
		town_zone_ids[zone_id] = true
	for required_zone in ["plaza", "farm", "training", "gate"]:
		if not town_zone_ids.has(required_zone):
			errors.append("generated village missing required town zone: %s" % required_zone)

	for anchor_id in ["plaza_social_spot", "field_work_spot", "training_yard_guard_post", "wild_gate_guard_post"]:
		var anchor := grid.get_anchor(anchor_id)
		if anchor.is_empty():
			errors.append("missing anchor: %s" % anchor_id)
			continue
		var anchor_cell := _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
		if not _contract_is_open_cell(grid, anchor_cell, blockers):
			errors.append("anchor is blocked: %s at %s" % [anchor_id, anchor_cell])
			continue
		if not _contract_has_path(grid, plaza_cell, anchor_cell, blockers):
			errors.append("anchor is unreachable: %s at %s" % [anchor_id, anchor_cell])

	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_cell := _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not _contract_has_path(grid, plaza_cell, exit_cell, blockers):
			errors.append("exit is unreachable: %s" % str(exit_data.get("id", "")))

	for object_value in (location_data.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		var object_cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		if not grid.in_bounds(object_cell):
			errors.append("object out of bounds: %s" % str(object_data.get("id", "")))
			continue
		if bool(object_data.get("is_usable", false)) or bool(object_data.get("is_inspectable", false)):
			if not _contract_has_reachable_adjacent_cell(grid, plaza_cell, object_cell, blockers):
				errors.append("object has no reachable interaction side: %s" % str(object_data.get("id", "")))

	return errors


func _base_location(source_data: Dictionary) -> Dictionary:
	return {
		"id": str(source_data.get("id", "test_village")),
		"display_name": str(source_data.get("display_name", "Generated Village")),
		"size": { "width": _width, "height": _height },
		"tile_size": int(source_data.get("tile_size", DEFAULT_TILE_SIZE)),
		"default_entrance": "plaza",
		"tiles": [],
		"terrain": _terrain_definitions(),
		"zones": [],
		"town_zones": [],
		"floor_overlays": [],
		"floor_decorations": [],
		"structures": [],
		"roofs": [],
		"entrances": [],
		"anchors": [],
		"exits": [],
		"shops": [],
		"objects": [],
		"characters": [],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
			"generation": "village_road_skeleton",
		},
	}


func _terrain_definitions() -> Dictionary:
	return {
		"g": { "id": "grass", "label": "Grass", "walkable": true, "color": "#5fa35f" },
		"p": { "id": "path", "label": "Village Road", "walkable": true, "color": "#b5975d" },
		"s": { "id": "plaza", "label": "Plaza Stone", "walkable": true, "color": "#8a8170" },
		"f": { "id": "field_plot", "label": "Field Plot", "walkable": true, "plantable": true, "color": "#6f8f4d" },
		"t": { "id": "training_ground", "label": "Training Sand", "walkable": true, "color": "#a8844d" },
		"e": { "id": "exit", "label": "Wild Gate", "walkable": true, "color": "#c8b642" },
	}


func _reset_tiles() -> void:
	_tiles.clear()
	_anchor_cells.clear()
	_placement_log.clear()
	for y in range(_height):
		var row: Array = []
		for _x in range(_width):
			row.append("g")
		_tiles.append(row)


func _build_road_skeleton() -> Dictionary:
	var road_cells: Array[Vector2i] = []
	var branches: Array[Dictionary] = []
	var main_y := clampi(int(float(_height) * 0.58) + _rng.randi_range(-1, 1), 8, _height - 6)
	var main_path := _build_west_east_path(main_y)
	_add_path_to_road_cells(road_cells, main_path)

	var upper_x := clampi(int(float(_width) * 0.36) + _rng.randi_range(-2, 2), 8, _width - 10)
	var lower_x := clampi(int(float(_width) * 0.64) + _rng.randi_range(-2, 2), 10, _width - 8)
	var upper_path := _build_branch_path(Vector2i(upper_x, _path_y_at_x(main_path, upper_x)), 5, -1, 8)
	var lower_path := _build_branch_path(Vector2i(lower_x, _path_y_at_x(main_path, lower_x)), _height - 5, 1, -7)
	_add_path_to_road_cells(road_cells, upper_path)
	_add_path_to_road_cells(road_cells, lower_path)
	branches.append({ "id": "north_lane", "cells": _cells_to_dicts(upper_path) })
	branches.append({ "id": "south_lane", "cells": _cells_to_dicts(lower_path) })

	var plaza_x := clampi(int(float(_width) * 0.52), 10, _width - 10)
	var plaza_y := _path_y_at_x(main_path, plaza_x)
	var plaza := _clamped_rect({ "x": plaza_x - 4, "y": plaza_y - 2, "w": 8, "h": 5 })
	var farm := _clamped_rect({ "x": _width - 10, "y": 2, "w": 8, "h": 7 })
	var training := _clamped_rect({ "x": 2, "y": max(2, main_y - 5), "w": 7, "h": 5 })
	var gate := _clamped_rect({ "x": _width - 6, "y": max(1, main_y - 1), "w": 5, "h": 3 })

	_placement_log.append({
		"subject": "road_skeleton",
		"reason": "The road graph is generated before any lot, building, or anchor work.",
		"candidate": {
			"main_road_length": main_path.size(),
			"branch_count": branches.size(),
			"road_cell_count": road_cells.size(),
		},
	})
	return {
		"main_path": main_path,
		"branches": branches,
		"road_cells": road_cells,
		"plaza": plaza,
		"farm": farm,
		"training": training,
		"gate": gate,
	}


func _build_west_east_path(start_y: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var y := start_y
	for x in range(0, _width):
		if x > 4 and x < _width - 5 and x % 7 == 0:
			y = clampi(y + _rng.randi_range(-1, 1), 7, _height - 5)
		path.append(Vector2i(x, y))
	return path


func _build_branch_path(start: Vector2i, target_y: int, vertical_step: int, horizontal_length: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := start
	while cursor.y != target_y:
		cursor.y += vertical_step
		cursor.y = clampi(cursor.y, 1, _height - 2)
		path.append(cursor)
	var horizontal_step := 1 if horizontal_length >= 0 else -1
	for _i in range(absi(horizontal_length)):
		cursor.x = clampi(cursor.x + horizontal_step, 1, _width - 2)
		path.append(cursor)
	return path


func _apply_road_skeleton(road_skeleton: Dictionary) -> void:
	for road_cell in (road_skeleton.get("road_cells", []) as Array):
		_set_tile(road_cell as Vector2i, "p")


func _apply_plaza(rect: Dictionary) -> void:
	_paint_rect(rect, "s")
	_add_town_zone("plaza", "civic_core", rect)
	var center := _rect_center_cell(rect)
	var plaza_entry := center + Vector2i(0, 2)
	_add_entrance("plaza", plaza_entry, "down")
	_add_anchor("plaza_social_spot", "social", center + Vector2i(2, 1), "left", [center + Vector2i(1, 1), center + Vector2i(2, 1)])
	_add_structure("fountain", center + Vector2i(-1, -1), { "grid_size": { "w": 2, "h": 2 }, "blocks_movement": true })
	_add_structure("notice_board", center + Vector2i(3, -1), { "blocks_movement": true })
	_add_object({
		"id": "village_notice",
		"display_name": "Village Notice",
		"grid_position": _dict_cell(center + Vector2i(3, -1)),
		"blocks_movement": false,
		"kind": "inspectable",
		"is_inspectable": true,
		"inspect_text": "A temporary marker for the generated road skeleton.",
	})


func _apply_farm(rect: Dictionary) -> void:
	_paint_rect(rect, "f")
	_add_town_zone("farm", "farm_block", rect)
	var work_cell := _rect_center_cell(rect)
	_add_anchor("field_work_spot", "farm_work", work_cell, "down")
	_add_structure("scarecrow", work_cell + Vector2i(-2, -1), { "blocks_movement": true })
	_add_floor_decoration("bucket", work_cell + Vector2i(2, 1))
	_add_floor_decoration("farm_tool", work_cell + Vector2i(-3, 2))
	_add_object({
		"id": "village_seed_pouch",
		"display_name": "Seed Pouch",
		"grid_position": _dict_cell(work_cell + Vector2i(1, 1)),
		"blocks_movement": false,
		"kind": "drop",
		"is_inspectable": true,
		"is_pickable": true,
		"inspect_text": "A generated field pickup placed near the farm anchor.",
		"item": {
			"source": "res://data/items/debug_seed.json",
			"quantity": 3,
		},
	})


func _apply_training_yard(rect: Dictionary) -> void:
	_paint_rect(rect, "t")
	_add_town_zone("training", "training_yard", rect)
	var guard_cell := _rect_center_cell(rect) + Vector2i(-2, 0)
	var dummy_a := _rect_center_cell(rect) + Vector2i(2, -1)
	var dummy_b := _rect_center_cell(rect) + Vector2i(2, 1)
	_add_anchor("training_yard_guard_post", "training", guard_cell, "left", [guard_cell, guard_cell + Vector2i(1, 0)])
	_add_structure("weapon_rack", guard_cell + Vector2i(0, -2), { "blocks_movement": true })
	_add_structure("target", dummy_a + Vector2i(1, -1), { "blocks_movement": true })
	_add_training_dummy("village_training_dummy_melee", dummy_a, ["basic_attack", "guard"], { "strength": 4, "agility": 2, "vitality": 5 })
	_add_training_dummy("village_training_dummy_ranged", dummy_b, ["quick_shot", "guard"], { "strength": 2, "agility": 4, "vitality": 4 })


func _apply_wild_gate(rect: Dictionary) -> void:
	_add_town_zone("gate", "wild_gate", rect)
	var y := clampi(_rect_center_cell(rect).y, 2, _height - 3)
	var exit_cell := Vector2i(_width - 1, y)
	var gate_anchor := exit_cell + Vector2i(-2, 0)
	_set_tile(exit_cell, "e")
	_set_tile(gate_anchor, "p")
	_add_entrance("from_wild", gate_anchor, "left")
	_add_anchor("wild_gate_guard_post", "guard_post", gate_anchor + Vector2i(-1, 0), "right", [gate_anchor + Vector2i(-1, 0), gate_anchor])
	_add_exit("wild_gate", exit_cell, "res://scenes/locations/test_clearing.tscn", "west_gate")
	_add_structure("signpost", gate_anchor + Vector2i(1, 0), { "blocks_movement": true })


func _add_common_decorations() -> void:
	for anchor_id in ["plaza_social_spot", "field_work_spot", "wild_gate_guard_post"]:
		var cell := _get_anchor_cell(anchor_id)
		if cell != Vector2i(-1, -1):
			_add_floor_decoration("road_pebbles", cell + Vector2i(0, 1))
	_add_floor_decoration("flower_patch", _get_entrance_cell("plaza") + Vector2i(-3, -2), { "palette": "spring" })
	_add_floor_decoration("grass_clump", Vector2i(2, _height - 3))
	_add_floor_decoration("stone", Vector2i(_width - 3, _height - 3))


func _add_generated_characters() -> void:
	(_generated.get("characters", []) as Array).append({
		"id": "debug_player",
		"source": "res://data/characters/debug_player.json",
		"spawn_at_entrance": true,
		"facing": "down",
	})
	(_generated.get("characters", []) as Array).append({
		"id": "debug_guard",
		"source": "res://data/characters/debug_guard.json",
		"facing": "left",
		"schedule": [
			_schedule_entry("training_morning", "06:00", "11:59", "training_yard_guard_post", "left", "train", "watching the training yard"),
			_schedule_entry("plaza_midday_patrol", "12:00", "13:59", "plaza_social_spot", "left", "patrol", "checking the plaza"),
			_schedule_entry("training_afternoon", "14:00", "17:59", "training_yard_guard_post", "left", "train", "watching the training yard"),
			_schedule_entry("gate_night", "18:00", "05:59", "wild_gate_guard_post", "right", "patrol", "guarding the wild gate"),
		],
	})


func _add_training_dummy(character_id: String, cell: Vector2i, skills: Array, attributes: Dictionary) -> void:
	(_generated.get("characters", []) as Array).append({
		"id": character_id,
		"display_name": "Training Dummy",
		"source": "res://data/characters/debug_training_dummy.json",
		"grid_position": _dict_cell(cell),
		"facing": "left",
		"skills": skills.duplicate(),
		"attributes": attributes.duplicate(true),
	})


func _schedule_entry(entry_id: String, start_time: String, end_time: String, anchor_id: String, facing: String, activity_type: String, activity: String) -> Dictionary:
	return {
		"id": entry_id,
		"start": start_time,
		"end": end_time,
		"location_id": str(_generated.get("id", "test_village")),
		"anchor_id": anchor_id,
		"facing": facing,
		"activity_type": activity_type,
		"activity": activity,
		"movement": "walk",
	}


func _add_path_to_road_cells(road_cells: Array[Vector2i], path: Array[Vector2i]) -> void:
	for cell in path:
		if not road_cells.has(cell):
			road_cells.append(cell)


func _path_y_at_x(path: Array[Vector2i], x: int) -> int:
	var best_y := int(float(_height) * 0.58)
	var best_distance := 99999
	for cell in path:
		var distance := absi(cell.x - x)
		if distance < best_distance:
			best_distance = distance
			best_y = cell.y
	return best_y


func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for cell in cells:
		rows.append(_dict_cell(cell))
	return rows


func _paint_rect(rect: Dictionary, key: String) -> void:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			_set_tile(Vector2i(x, y), key)


func _set_tile(cell: Vector2i, key: String) -> void:
	if not _in_bounds(cell):
		return
	(_tiles[cell.y] as Array)[cell.x] = key


func _stringify_tiles() -> Array[String]:
	var result: Array[String] = []
	for row_value in _tiles:
		var row: Array = row_value as Array
		var text := ""
		for cell_key in row:
			text += str(cell_key)
		result.append(text)
	return result


func _add_town_zone(zone_id: String, zone_type: String, bounds: Dictionary) -> void:
	(_generated.get("town_zones", []) as Array).append({
		"id": zone_id,
		"type": zone_type,
		"bounds": bounds.duplicate(true),
		"source": "road_skeleton",
	})
	(_generated.get("zones", []) as Array).append({
		"id": "%s_zone" % zone_id,
		"type": zone_type,
		"display_name": zone_id.capitalize(),
		"bounds": bounds.duplicate(true),
	})


func _add_structure(structure_type: String, cell: Vector2i, extra: Dictionary = {}) -> void:
	var entry := { "type": structure_type, "grid_position": _dict_cell(cell) }
	entry.merge(extra, true)
	(_generated.get("structures", []) as Array).append(entry)


func _add_floor_decoration(decoration_type: String, cell: Vector2i, extra: Dictionary = {}) -> void:
	if not _in_bounds(cell):
		return
	var entry := { "type": decoration_type, "grid_position": _dict_cell(cell) }
	entry.merge(extra, true)
	(_generated.get("floor_decorations", []) as Array).append(entry)


func _add_entrance(entrance_id: String, cell: Vector2i, facing: String) -> void:
	(_generated.get("entrances", []) as Array).append({
		"id": entrance_id,
		"grid_position": _dict_cell(cell),
		"facing": facing,
	})


func _add_anchor(anchor_id: String, kind: String, cell: Vector2i, facing: String, activity_cells: Array = []) -> void:
	var anchor := {
		"id": anchor_id,
		"kind": kind,
		"grid_position": _dict_cell(cell),
		"facing": facing,
	}
	if not activity_cells.is_empty():
		var cells: Array[Dictionary] = []
		for cell_value in activity_cells:
			var activity_cell: Vector2i = cell_value as Vector2i
			if _in_bounds(activity_cell):
				cells.append(_dict_cell(activity_cell))
		anchor["activity_cells"] = cells
	_anchor_cells[anchor_id] = cell
	(_generated.get("anchors", []) as Array).append(anchor)


func _add_exit(exit_id: String, cell: Vector2i, target_scene_path: String, target_entrance_id: String) -> void:
	(_generated.get("exits", []) as Array).append({
		"id": exit_id,
		"grid_position": _dict_cell(cell),
		"target_scene_path": target_scene_path,
		"target_entrance_id": target_entrance_id,
	})


func _add_object(object_data: Dictionary) -> void:
	(_generated.get("objects", []) as Array).append(object_data)


func _get_anchor_cell(anchor_id: String) -> Vector2i:
	if _anchor_cells.has(anchor_id):
		return _anchor_cells[anchor_id] as Vector2i
	return Vector2i(-1, -1)


func _get_entrance_cell(entrance_id: String) -> Vector2i:
	for entrance_value in (_generated.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return _cell_from_dict(entrance.get("grid_position", {}) as Dictionary)
	return Vector2i(-1, -1)


func _rect_center_cell(rect: Dictionary) -> Vector2i:
	return Vector2i(
		int(rect.get("x", 0)) + int(rect.get("w", 0)) / 2,
		int(rect.get("y", 0)) + int(rect.get("h", 0)) / 2
	)


func _clamped_rect(rect: Dictionary) -> Dictionary:
	var x := clampi(int(rect.get("x", 0)), 1, _width - 2)
	var y := clampi(int(rect.get("y", 0)), 1, _height - 2)
	var w: int = min(int(rect.get("w", 1)), _width - 1 - x)
	var h: int = min(int(rect.get("h", 1)), _height - 1 - y)
	return { "x": x, "y": y, "w": max(1, w), "h": max(1, h) }


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _width and cell.y < _height


func _contract_blocking_object_cells(location_data: Dictionary) -> Dictionary:
	var blockers: Dictionary = {}
	for object_value in (location_data.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		if not bool(object_data.get("blocks_movement", true)):
			continue
		var cell := _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		blockers[_cell_key(cell)] = str(object_data.get("id", ""))
	return blockers


func _contract_has_reachable_adjacent_cell(grid: LocationGrid, start_cell: Vector2i, target_cell: Vector2i, blockers: Dictionary) -> bool:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var adjacent: Vector2i = target_cell + direction
		if not _contract_is_open_cell(grid, adjacent, blockers):
			continue
		if _contract_has_path(grid, start_cell, adjacent, blockers):
			return true
	return false


func _contract_has_path(grid: LocationGrid, start_cell: Vector2i, target_cell: Vector2i, blockers: Dictionary) -> bool:
	if not _contract_is_open_cell(grid, start_cell, blockers):
		return false
	if not _contract_is_open_cell(grid, target_cell, blockers):
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
			if not _contract_is_open_cell(grid, next_cell, blockers):
				continue
			visited[key] = true
			frontier.append(next_cell)
	return false


func _contract_is_open_cell(grid: LocationGrid, cell: Vector2i, blockers: Dictionary) -> bool:
	if not grid.in_bounds(cell):
		return false
	if not grid.is_walkable(cell):
		return false
	return not blockers.has(_cell_key(cell))


func _contract_entrance_cell(location_data: Dictionary, entrance_id: String) -> Vector2i:
	for entrance_value in (location_data.get("entrances", []) as Array):
		var entrance: Dictionary = entrance_value as Dictionary
		if str(entrance.get("id", "")) == entrance_id:
			return _cell_from_dict(entrance.get("grid_position", {}) as Dictionary)
	return Vector2i(-1, -1)
