class_name VillageBspGenerator
extends RefCounted

const DEFAULT_WIDTH := 36
const DEFAULT_HEIGHT := 24
const DEFAULT_TILE_SIZE := 32
const MIN_LEAF_SIZE := 6
const TARGET_LEAF_COUNT := 16

var _rng := RandomNumberGenerator.new()
var _width: int = DEFAULT_WIDTH
var _height: int = DEFAULT_HEIGHT
var _tiles: Array[Array] = []
var _reserved_cells: Dictionary = {}
var _objects_by_cell: Dictionary = {}
var _anchor_cells: Dictionary = {}
var _connector_cells: Dictionary = {}
var _road_blockers: Dictionary = {}
var _placement_log: Array[Dictionary] = []
var _generated: Dictionary = {}


func generate_location(source_data: Dictionary) -> Dictionary:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	_rng.seed = int(generator_data.get("seed", 5601))
	var size: Dictionary = generator_data.get("size", source_data.get("size", {})) as Dictionary
	_width = max(24, int(size.get("width", DEFAULT_WIDTH)))
	_height = max(18, int(size.get("height", DEFAULT_HEIGHT)))
	_reset_tiles()

	var leaves: Array[Dictionary] = _build_bsp_leaves()
	_generated = _base_location(source_data)
	var plan: Dictionary = _assign_town_plan(leaves)

	_apply_plaza(plan.get("plaza", {}) as Dictionary)
	_apply_farm(plan.get("farm", {}) as Dictionary)
	_apply_training_yard(plan.get("training", {}) as Dictionary)
	_apply_wild_gate(plan.get("wild_gate", {}) as Dictionary)
	for building_value in (plan.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		_apply_building_spec(building.get("spec", {}) as Dictionary, building.get("leaf", {}) as Dictionary)
	_connect_key_places()
	_add_common_decorations()
	_add_generated_characters()
	_generated["tiles"] = _stringify_tiles()
	_generated["generation_summary"] = {
		"type": "village_bsp",
		"seed": int(generator_data.get("seed", 5601)),
		"leaf_count": leaves.size(),
		"anchor_count": (_generated.get("anchors", []) as Array).size(),
		"object_count": (_generated.get("objects", []) as Array).size(),
		"placement_log": _placement_log.duplicate(true),
	}
	var contract_errors: Array[String] = validate_location_contract(_generated)
	for error in contract_errors:
		push_error("VillageBspGenerator contract error: %s" % error)
	return _generated


func validate_location_contract(location_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var grid: LocationGrid = LocationGrid.from_dictionary(location_data)
	if not grid.is_valid():
		errors.append("generated LocationGrid is invalid")
		return errors

	var blockers: Dictionary = _contract_blocking_object_cells(location_data)
	var plaza_cell: Vector2i = _contract_entrance_cell(location_data, "plaza")
	if plaza_cell == Vector2i(-1, -1):
		errors.append("missing plaza entrance")
		return errors
	if not _contract_is_open_cell(grid, plaza_cell, blockers):
		errors.append("plaza entrance is blocked")

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
			errors.append("missing anchor: %s" % anchor_id)
			continue
		var anchor_cell: Vector2i = _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
		if not _contract_is_open_cell(grid, anchor_cell, blockers):
			errors.append("anchor is blocked: %s at %s" % [anchor_id, anchor_cell])
			continue
		if not _contract_has_path(grid, plaza_cell, anchor_cell, blockers):
			errors.append("anchor is unreachable: %s at %s" % [anchor_id, anchor_cell])
		for activity_value in (anchor.get("activity_cells", []) as Array):
			var activity_cell: Vector2i = _cell_from_dict(activity_value as Dictionary)
			if not _contract_is_open_cell(grid, activity_cell, blockers):
				errors.append("activity cell is blocked: %s at %s" % [anchor_id, activity_cell])

	for object_value in (location_data.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		var object_cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		if not grid.in_bounds(object_cell):
			errors.append("object out of bounds: %s" % str(object_data.get("id", "")))
			continue
		if bool(object_data.get("is_usable", false)) or bool(object_data.get("is_inspectable", false)):
			if not _contract_has_reachable_adjacent_cell(grid, plaza_cell, object_cell, blockers):
				errors.append("object has no reachable interaction side: %s" % str(object_data.get("id", "")))

	for exit_value in (location_data.get("exits", []) as Array):
		var exit_data: Dictionary = exit_value as Dictionary
		var exit_cell: Vector2i = _cell_from_dict(exit_data.get("grid_position", {}) as Dictionary)
		if not _contract_has_path(grid, plaza_cell, exit_cell, blockers):
			errors.append("exit is unreachable: %s" % str(exit_data.get("id", "")))

	for character_value in (location_data.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		for schedule_value in (character.get("schedule", []) as Array):
			var entry: Dictionary = schedule_value as Dictionary
			var anchor_id: String = str(entry.get("anchor_id", ""))
			if anchor_id.is_empty():
				errors.append("schedule entry missing anchor_id: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
			elif grid.get_anchor(anchor_id).is_empty():
				errors.append("schedule references missing anchor: %s" % anchor_id)
			if entry.has("grid_position"):
				errors.append("schedule entry should not hand-author grid_position: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])

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
		"floor_overlays": [],
		"floor_decorations": [],
		"structures": [],
		"roofs": [],
		"entrances": [],
		"anchors": [],
		"exits": [],
		"shops": [{ "id": "field_stall" }],
		"objects": [],
		"characters": [],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
			"generation": "village_bsp",
		},
	}


func _terrain_definitions() -> Dictionary:
	return {
		"g": { "id": "grass", "label": "Grass", "walkable": true, "color": "#5fa35f" },
		"p": { "id": "path", "label": "Village Road", "walkable": true, "color": "#b5975d" },
		"h": { "id": "house_floor", "label": "Home Floor", "walkable": true, "color": "#8b6a42" },
		"c": { "id": "workshop_floor", "label": "Workshop Floor", "walkable": true, "color": "#6f6658" },
		"q": { "id": "shop_floor", "label": "Shop Floor", "walkable": true, "color": "#8b6a42" },
		"a": { "id": "tavern_floor", "label": "Tavern Floor", "walkable": true, "color": "#94704a" },
		"s": { "id": "plaza", "label": "Plaza Stone", "walkable": true, "color": "#8a8170" },
		"f": { "id": "field_plot", "label": "Field Plot", "walkable": true, "plantable": true, "color": "#6f8f4d" },
		"t": { "id": "training_ground", "label": "Training Sand", "walkable": true, "color": "#a8844d" },
		"e": { "id": "exit", "label": "Wild Gate", "walkable": true, "color": "#c8b642" },
	}


func _reset_tiles() -> void:
	_tiles.clear()
	_reserved_cells.clear()
	_objects_by_cell.clear()
	_anchor_cells.clear()
	_connector_cells.clear()
	_road_blockers.clear()
	_placement_log.clear()
	for y in range(_height):
		var row: Array = []
		for _x in range(_width):
			row.append("g")
		_tiles.append(row)


func _build_bsp_leaves() -> Array[Dictionary]:
	var leaves: Array[Dictionary] = [{
		"x": 1,
		"y": 1,
		"w": _width - 2,
		"h": _height - 2,
	}]
	while leaves.size() < TARGET_LEAF_COUNT:
		var split_index := _find_largest_splittable_leaf(leaves)
		if split_index < 0:
			break
		var leaf: Dictionary = leaves[split_index] as Dictionary
		var split_pair: Array[Dictionary] = _split_leaf(leaf)
		if split_pair.size() != 2:
			break
		leaves.remove_at(split_index)
		leaves.append(split_pair[0])
		leaves.append(split_pair[1])
	return leaves


func _find_largest_splittable_leaf(leaves: Array[Dictionary]) -> int:
	var best_index := -1
	var best_area := -1
	for index in range(leaves.size()):
		var leaf: Dictionary = leaves[index] as Dictionary
		var can_split_x: bool = int(leaf.get("w", 0)) >= MIN_LEAF_SIZE * 2
		var can_split_y: bool = int(leaf.get("h", 0)) >= MIN_LEAF_SIZE * 2
		if not can_split_x and not can_split_y:
			continue
		var area: int = int(leaf.get("w", 0)) * int(leaf.get("h", 0))
		if area > best_area:
			best_index = index
			best_area = area
	return best_index


func _split_leaf(leaf: Dictionary) -> Array[Dictionary]:
	var w: int = int(leaf.get("w", 0))
	var h: int = int(leaf.get("h", 0))
	var split_vertical: bool
	if w >= h * 1.25:
		split_vertical = true
	elif h >= w * 1.25:
		split_vertical = false
	else:
		split_vertical = _rng.randi_range(0, 1) == 0

	if split_vertical and w < MIN_LEAF_SIZE * 2:
		split_vertical = false
	if not split_vertical and h < MIN_LEAF_SIZE * 2:
		split_vertical = true

	if split_vertical:
		var left_w := _rng.randi_range(MIN_LEAF_SIZE, w - MIN_LEAF_SIZE)
		return [
			{ "x": int(leaf.get("x", 0)), "y": int(leaf.get("y", 0)), "w": left_w, "h": h },
			{ "x": int(leaf.get("x", 0)) + left_w, "y": int(leaf.get("y", 0)), "w": w - left_w, "h": h },
		]

	var top_h := _rng.randi_range(MIN_LEAF_SIZE, h - MIN_LEAF_SIZE)
	return [
		{ "x": int(leaf.get("x", 0)), "y": int(leaf.get("y", 0)), "w": w, "h": top_h },
		{ "x": int(leaf.get("x", 0)), "y": int(leaf.get("y", 0)) + top_h, "w": w, "h": h - top_h },
	]


func _assign_town_plan(leaves: Array[Dictionary]) -> Dictionary:
	var available: Array[Dictionary] = []
	for leaf in leaves:
		available.append((leaf as Dictionary).duplicate(true))

	var center := Vector2(float(_width) * 0.5, float(_height) * 0.5)
	var plaza_leaf := _take_closest_leaf(available, center)
	var plaza_rect := _inner_rect(plaza_leaf, 8, 5)
	_add_placement_log("plaza", plaza_leaf, "reserved central civic leaf before scoring")
	var wild_leaf := _take_scored_district_leaf(available, "wild_gate", plaza_rect)
	var farm_leaf := _take_scored_district_leaf(available, "farm", plaza_rect)
	var training_leaf := _take_scored_district_leaf(available, "training", plaza_rect)
	var buildings: Array[Dictionary] = []
	for spec_value in _building_specs():
		var spec: Dictionary = spec_value as Dictionary
		if available.is_empty():
			break
		var building_leaf := _take_scored_building_leaf(available, spec, plaza_rect, farm_leaf, wild_leaf, buildings)
		if building_leaf.is_empty():
			_add_placement_log(str(spec.get("id", "")), {}, "skipped: no valid down-facing frontage")
			continue
		buildings.append({
			"spec": (spec as Dictionary).duplicate(true),
			"leaf": building_leaf.duplicate(true),
		})
	return {
		"plaza": plaza_rect,
		"wild_gate": wild_leaf,
		"farm": farm_leaf,
		"training": training_leaf,
		"buildings": buildings,
	}


func _take_closest_leaf(leaves: Array[Dictionary], target: Vector2) -> Dictionary:
	var best_index := 0
	var best_distance := INF
	for index in range(leaves.size()):
		var leaf: Dictionary = leaves[index] as Dictionary
		var center := _leaf_center(leaf)
		var distance := center.distance_squared_to(target)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return leaves.pop_at(best_index) as Dictionary


func _building_specs() -> Array[Dictionary]:
	return [
		{
			"id": "residential",
			"zone_type": "residential",
			"display_name": "Residence",
			"tile": "h",
			"roof": "purple",
			"label": "H",
			"desired_w": 6,
			"desired_h": 5,
			"role": "home",
			"preference": "quiet",
			"anchor_id": "house_sleep_spot",
			"anchor_kind": "bed",
		},
		{
			"id": "workshop",
			"zone_type": "workshop",
			"display_name": "Workshop",
			"tile": "c",
			"roof": "brown",
			"label": "W",
			"desired_w": 6,
			"desired_h": 5,
			"role": "production",
			"preference": "road",
			"anchor_id": "workbench_spot",
			"anchor_kind": "workbench",
		},
		{
			"id": "shop",
			"zone_type": "shop",
			"display_name": "Shop",
			"tile": "q",
			"roof": "blue",
			"label": "S",
			"desired_w": 6,
			"desired_h": 5,
			"role": "commerce",
			"preference": "plaza",
			"anchor_id": "shop_counter_spot",
			"anchor_kind": "shop_counter",
		},
		{
			"id": "tavern",
			"zone_type": "tavern",
			"display_name": "Tavern",
			"tile": "a",
			"roof": "red",
			"label": "T",
			"desired_w": 7,
			"desired_h": 5,
			"role": "social",
			"preference": "plaza",
			"anchor_id": "tavern_table_spot",
			"anchor_kind": "meal",
		},
		{
			"id": "farmer_cottage",
			"zone_type": "residential",
			"display_name": "Farmer Cottage",
			"tile": "h",
			"roof": "green",
			"label": "F",
			"desired_w": 5,
			"desired_h": 4,
			"role": "home",
			"preference": "farm",
			"anchor_id": "farmer_home_spot",
			"anchor_kind": "home",
		},
		{
			"id": "worker_cottage",
			"zone_type": "residential",
			"display_name": "Worker Cottage",
			"tile": "h",
			"roof": "brown",
			"label": "C",
			"desired_w": 5,
			"desired_h": 4,
			"role": "home",
			"preference": "quiet",
			"anchor_id": "worker_home_spot",
			"anchor_kind": "home",
		},
		{
			"id": "storage_shed",
			"zone_type": "storage",
			"display_name": "Storage Shed",
			"tile": "c",
			"roof": "brown",
			"label": "G",
			"desired_w": 5,
			"desired_h": 4,
			"role": "storage",
			"preference": "farm",
			"anchor_id": "storage_spot",
			"anchor_kind": "storage",
		},
		{
			"id": "guardhouse",
			"zone_type": "guard",
			"display_name": "Guardhouse",
			"tile": "t",
			"roof": "blue",
			"label": "G",
			"desired_w": 5,
			"desired_h": 4,
			"role": "guard",
			"preference": "gate",
			"anchor_id": "guardhouse_spot",
			"anchor_kind": "guard_post",
		},
	]


func _take_scored_district_leaf(leaves: Array[Dictionary], district_id: String, plaza_rect: Dictionary) -> Dictionary:
	var best_index := 0
	var best_score := -INF
	for index in range(leaves.size()):
		var leaf: Dictionary = leaves[index] as Dictionary
		var score := _score_district_leaf(leaf, district_id, plaza_rect)
		if score > best_score:
			best_score = score
			best_index = index
	var selected: Dictionary = leaves.pop_at(best_index) as Dictionary
	_add_placement_log(district_id, selected, "score %.2f: %s" % [best_score, _district_score_reason(district_id)])
	return selected


func _score_district_leaf(leaf: Dictionary, district_id: String, plaza_rect: Dictionary) -> float:
	var center: Vector2 = _leaf_center(leaf)
	var area: float = float(int(leaf.get("w", 0)) * int(leaf.get("h", 0)))
	var plaza_distance: float = center.distance_to(_rect_center(plaza_rect))
	var edge: float = _edge_score(center)
	match district_id:
		"farm":
			return area * 0.45 + edge * 10.0 + _west_score(center) * 12.0 - plaza_distance * 0.15
		"training":
			return area * 0.30 + edge * 12.0 + _east_score(center) * 10.0 + _south_score(center) * 4.0
		"wild_gate":
			return edge * 16.0 + _east_score(center) * 18.0 + _south_score(center) * 4.0
		_:
			return area - plaza_distance


func _district_score_reason(district_id: String) -> String:
	match district_id:
		"farm":
			return "large western/edge leaf, kept out of main street routing"
		"training":
			return "edge leaf with room for combat props"
		"wild_gate":
			return "eastern edge leaf for scene transition"
		_:
			return "generic district score"


func _take_scored_building_leaf(
	leaves: Array[Dictionary],
	spec: Dictionary,
	plaza_rect: Dictionary,
	farm_leaf: Dictionary,
	wild_leaf: Dictionary,
	placed_buildings: Array[Dictionary]
) -> Dictionary:
	var best_index := 0
	var best_score := -INF
	var best_reason := ""
	for index in range(leaves.size()):
		var leaf: Dictionary = leaves[index] as Dictionary
		var score_data: Dictionary = _score_building_leaf(leaf, spec, plaza_rect, farm_leaf, wild_leaf, placed_buildings)
		var score: float = float(score_data.get("score", 0.0))
		if score > best_score:
			best_score = score
			best_index = index
			best_reason = str(score_data.get("reason", ""))
	if is_equal_approx(best_score, -INF):
		return {}
	var selected: Dictionary = leaves.pop_at(best_index) as Dictionary
	_add_placement_log(str(spec.get("id", "")), selected, "score %.2f: %s" % [best_score, best_reason])
	return selected


func _score_building_leaf(
	leaf: Dictionary,
	spec: Dictionary,
	plaza_rect: Dictionary,
	farm_leaf: Dictionary,
	wild_leaf: Dictionary,
	placed_buildings: Array[Dictionary]
) -> Dictionary:
	var center: Vector2 = _leaf_center(leaf)
	var plaza_center: Vector2 = _rect_center(plaza_rect)
	var farm_center: Vector2 = _leaf_center(farm_leaf)
	var gate_center: Vector2 = _leaf_center(wild_leaf)
	var rect := _inner_rect(leaf, int(spec.get("desired_w", 6)), int(spec.get("desired_h", 5)))
	var door_info := _choose_building_door(rect, spec, _rect_center_cell(plaza_rect))
	if not _building_frontage_is_valid(door_info):
		return {
			"score": -INF,
			"reason": "rejected: missing valid down-facing frontage",
		}
	var area: float = float(int(leaf.get("w", 0)) * int(leaf.get("h", 0)))
	var score: float = area * 0.08
	var reason_parts: Array[String] = ["fits %.0f cells" % area, "valid %s frontage" % str(door_info.get("facing", "down"))]
	var preference: String = str(spec.get("preference", ""))
	var plaza_distance: float = center.distance_to(plaza_center)
	match preference:
		"plaza":
			score += max(0.0, 30.0 - plaza_distance)
			reason_parts.append("prefers plaza frontage")
		"road":
			score += max(0.0, 22.0 - plaza_distance * 0.6)
			reason_parts.append("prefers a reachable work street")
		"farm":
			score += max(0.0, 28.0 - center.distance_to(farm_center))
			reason_parts.append("prefers farm adjacency")
		"gate":
			score += max(0.0, 30.0 - center.distance_to(gate_center))
			reason_parts.append("prefers gate/security edge")
		"quiet":
			score += _edge_score(center) * 7.0 + min(14.0, plaza_distance * 0.45)
			reason_parts.append("prefers quieter outer lots")

	if str(spec.get("role", "")) == "home":
		score += _residential_cluster_score(center, placed_buildings)
		reason_parts.append("clusters with homes")

	return {
		"score": score,
		"reason": ", ".join(reason_parts),
	}


func _inner_rect(leaf: Dictionary, desired_w: int, desired_h: int) -> Dictionary:
	var margin := 1
	var w: int = min(desired_w, max(3, int(leaf.get("w", 0)) - margin * 2))
	var h: int = min(desired_h, max(3, int(leaf.get("h", 0)) - margin * 2))
	var x: int = int(leaf.get("x", 0)) + margin + max(0, (int(leaf.get("w", 0)) - margin * 2 - w) / 2)
	var y: int = int(leaf.get("y", 0)) + margin + max(0, (int(leaf.get("h", 0)) - margin * 2 - h) / 2)
	return { "x": x, "y": y, "w": w, "h": h }


func _leaf_center(leaf: Dictionary) -> Vector2:
	return Vector2(
		float(int(leaf.get("x", 0))) + float(int(leaf.get("w", 0))) * 0.5,
		float(int(leaf.get("y", 0))) + float(int(leaf.get("h", 0))) * 0.5
	)


func _apply_plaza(rect: Dictionary) -> void:
	_paint_rect(rect, "s")
	_add_zone("plaza_zone", "plaza", "Village Plaza", rect)
	var center := _rect_center_cell(rect)
	var plaza_entry := center + Vector2i(0, 2)
	_add_entrance("plaza", plaza_entry, "down")
	_add_anchor("plaza_social_spot", "social", center + Vector2i(1, 0), "left", [center, center + Vector2i(1, 0)])
	_add_structure("fountain", center + Vector2i(-1, -2), { "grid_size": { "w": 2, "h": 2 }, "blocks_movement": true })
	_add_structure("notice_board", center + Vector2i(2, -1), { "blocks_movement": true })
	_add_structure("bench", center + Vector2i(-3, 2), { "blocks_movement": true })
	_add_object({
		"id": "village_notice",
		"display_name": "Village Notice",
		"grid_position": _dict_cell(center + Vector2i(2, -1)),
		"blocks_movement": false,
		"kind": "inspectable",
		"is_inspectable": true,
		"inspect_text": "This generated village is assembled from BSP districts, semantic anchors, and validated placement slots.",
	})
	_add_object({
		"id": "village_save_stone",
		"display_name": "Plaza Save Stone",
		"grid_position": _dict_cell(center + Vector2i(1, 1)),
		"blocks_movement": true,
		"kind": "save_point",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "save",
		"inspect_text": "A record stone in the generated plaza.",
	})


func _apply_building_spec(spec: Dictionary, leaf: Dictionary) -> void:
	var kind: String = str(spec.get("id", "building"))
	var rect := _inner_rect(leaf, int(spec.get("desired_w", 6)), int(spec.get("desired_h", 5)))
	var plaza_cell := _get_entrance_cell("plaza")
	if plaza_cell == Vector2i(-1, -1):
		plaza_cell = _rect_center_cell(rect)
	var door_info := _choose_building_door(rect, spec, plaza_cell)
	var door: Vector2i = door_info.get("door", Vector2i.ZERO) as Vector2i
	var door_step: Vector2i = door_info.get("step", Vector2i.ZERO) as Vector2i
	var door_facing: String = str(door_info.get("facing", "down"))
	var anchor_cell := _interior_cell_near_door(rect, door)
	var facility_cell := _interior_secondary_cell(rect, door, [anchor_cell])
	var prop_cell := _first_free_interior_cell(rect, [anchor_cell, facility_cell])

	_paint_rect(rect, str(spec.get("tile", "h")))
	_mark_rect_road_blocker(rect)
	_road_blockers.erase(_cell_key(door_step))
	_add_zone("%s_zone" % kind, str(spec.get("zone_type", kind)), str(spec.get("display_name", kind)), rect)
	_add_structure("wall_ring", Vector2i.ZERO, {
		"bounds": rect.duplicate(true),
		"exclude_cells": [_dict_cell(door)],
		"blocks_movement": true,
		"blocks_sight": true,
	})
	_add_structure("door", door)
	_add_building_windows(rect, door, door_facing)
	_add_roof("%s_roof" % kind, str(spec.get("roof", "brown")), rect)
	_connector_cells[kind] = door_step
	_set_path_tile(door_step)
	_reserve_cell(door_step)

	var sign_cell := _sign_cell_for_door(rect, door, door_facing)
	_add_structure("sign_badge", sign_cell, {
		"label": str(spec.get("label", "?")),
		"blocks_movement": true,
		"blocks_sight": true,
	})
	var anchor_id: String = str(spec.get("anchor_id", "%s_anchor" % kind))
	_add_anchor(anchor_id, str(spec.get("anchor_kind", "building")), anchor_cell, _opposite_facing(door_facing))
	_apply_building_role_content(kind, facility_cell, prop_cell, door, door_facing)


func _choose_building_door(rect: Dictionary, spec: Dictionary, target_cell: Vector2i) -> Dictionary:
	match str(spec.get("door_orientation", "down")):
		"toward_target":
			return _choose_door(rect, target_cell)
		_:
			return _choose_down_door(rect)


func _choose_down_door(rect: Dictionary) -> Dictionary:
	var center := _rect_center_cell(rect)
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	var door := Vector2i(clampi(center.x, x0 + 1, x0 + w - 2), y0 + h - 1)
	return { "door": door, "step": door + Vector2i.DOWN, "facing": "down" }


func _building_frontage_is_valid(door_info: Dictionary) -> bool:
	var step: Vector2i = door_info.get("step", Vector2i(-1, -1)) as Vector2i
	if not _in_bounds(step):
		return false
	if _road_blockers.has(_cell_key(step)):
		return false
	return true


func _facility_object(object_id: String, display_name: String, kind: String, cell: Vector2i, extra: Dictionary) -> Dictionary:
	var data := {
		"id": object_id,
		"display_name": display_name,
		"grid_position": _dict_cell(cell),
		"blocks_movement": false,
		"kind": kind,
		"is_inspectable": true,
		"is_usable": true,
	}
	data.merge(extra, true)
	return data


func _apply_building_role_content(kind: String, inside: Vector2i, secondary: Vector2i, door: Vector2i, door_facing: String) -> void:
	match kind:
		"residential":
			_add_object(_facility_object("village_house_bed", "House Bed", "bed", inside, {
				"rest_type": "bed",
				"target_hour": 6,
				"target_minute": 0,
				"full_restore": true,
				"inspect_text": "A bed placed by the generated residence template.",
			}))
			_add_floor_decoration("mailbox", door + _facing_vector(door_facing))
		"workshop":
			_add_structure("anvil", secondary, { "blocks_movement": true })
			_add_structure("material_crates", secondary + Vector2i(1, 0), { "blocks_movement": true })
			_add_object(_facility_object("village_workbench", "Workshop Bench", "workbench", inside, {
				"facility_type": "crafting",
				"recipe_ids": ["debug_tool", "packed_snack", "material_scroll_test"],
				"inspect_text": "A generated workbench connected to the crafting facility.",
			}))
		"shop":
			_add_structure("shop_sign", door + _facing_vector(door_facing), { "blocks_movement": false, "blocks_sight": false })
			_add_structure("goods_crate", secondary, { "blocks_movement": true })
			_add_structure("shelf", secondary + Vector2i(-1, 0), { "blocks_movement": true })
			_add_object(_facility_object("village_shop_counter", "Village Shop", "shop", inside, {
				"facility_type": "shop",
				"shop_id": "field_stall",
				"vendor_character_id": "debug_villager",
				"inspect_text": "A generated shop counter. The vendor schedule resolves to the shop counter anchor.",
			}))
		"tavern":
			_add_structure("table_set", secondary, { "blocks_movement": true })
			_add_structure("barrel", secondary + Vector2i(-1, 0), { "blocks_movement": true })
			_add_object(_facility_object("village_tavern_counter", "Tavern Counter", "inn", inside, {
				"facility_type": "rest",
				"rest_type": "inn",
				"cost": 10,
				"target_hour": 6,
				"target_minute": 0,
				"full_restore": true,
				"inspect_text": "A generated tavern counter for paid rest.",
			}))
		"farmer_cottage":
			_add_floor_decoration("farm_tool", door + _facing_vector(door_facing))
			_add_structure("barrel", secondary, { "blocks_movement": true })
		"worker_cottage":
			_add_floor_decoration("flower_pot", door + _facing_vector(door_facing))
		"storage_shed":
			_add_structure("material_crates", inside, { "blocks_movement": true })
			_add_structure("goods_crate", secondary, { "blocks_movement": true })
		"guardhouse":
			_add_structure("weapon_rack", inside, { "blocks_movement": true })
			_add_structure("counter", secondary, { "blocks_movement": true })


func _choose_door(rect: Dictionary, target_cell: Vector2i) -> Dictionary:
	var center := _rect_center_cell(rect)
	var dx: int = target_cell.x - center.x
	var dy: int = target_cell.y - center.y
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	if absi(dx) > absi(dy):
		if dx >= 0:
			var door_e := Vector2i(x0 + w - 1, clampi(center.y, y0 + 1, y0 + h - 2))
			return { "door": door_e, "step": door_e + Vector2i.RIGHT, "facing": "right" }
		var door_w := Vector2i(x0, clampi(center.y, y0 + 1, y0 + h - 2))
		return { "door": door_w, "step": door_w + Vector2i.LEFT, "facing": "left" }
	if dy >= 0:
		var door_s := Vector2i(clampi(center.x, x0 + 1, x0 + w - 2), y0 + h - 1)
		return { "door": door_s, "step": door_s + Vector2i.DOWN, "facing": "down" }
	var door_n := Vector2i(clampi(center.x, x0 + 1, x0 + w - 2), y0)
	return { "door": door_n, "step": door_n + Vector2i.UP, "facing": "up" }


func _add_building_windows(rect: Dictionary, door: Vector2i, door_facing: String) -> void:
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	var candidates: Array[Vector2i] = []
	if door_facing == "up" or door_facing == "down":
		candidates.append(Vector2i(max(x0 + 1, door.x - 1), door.y))
		candidates.append(Vector2i(min(x0 + w - 2, door.x + 1), door.y))
	else:
		candidates.append(Vector2i(door.x, max(y0 + 1, door.y - 1)))
		candidates.append(Vector2i(door.x, min(y0 + h - 2, door.y + 1)))
	for candidate in candidates:
		if candidate == door:
			continue
		_add_structure("window", candidate, { "blocks_movement": true, "blocks_sight": true })


func _interior_cell_near_door(rect: Dictionary, door: Vector2i) -> Vector2i:
	var center := _rect_center_cell(rect)
	var direction := Vector2i(signi(center.x - door.x), signi(center.y - door.y))
	if direction == Vector2i.ZERO:
		direction = Vector2i.DOWN
	return _clamp_to_rect_inner(door + direction, rect)


func _interior_secondary_cell(rect: Dictionary, door: Vector2i, forbidden_cells: Array = []) -> Vector2i:
	var center := _rect_center_cell(rect)
	var candidates: Array[Vector2i] = [
		center + Vector2i(1, 0),
		center + Vector2i(-1, 0),
		center + Vector2i(0, 1),
		center + Vector2i(0, -1),
		center + Vector2i(1, 1),
		center + Vector2i(-1, 1),
		center + Vector2i(1, -1),
		center + Vector2i(-1, -1),
	]
	var best_cell := center
	var best_distance := -1
	for candidate_value in candidates:
		var candidate := _clamp_to_rect_inner(candidate_value, rect)
		if _cell_array_has(forbidden_cells, candidate):
			continue
		var distance := candidate.distance_squared_to(door)
		if distance > best_distance:
			best_distance = distance
			best_cell = candidate
	if _cell_array_has(forbidden_cells, best_cell):
		return _first_free_interior_cell(rect, forbidden_cells)
	return best_cell


func _first_free_interior_cell(rect: Dictionary, forbidden_cells: Array) -> Vector2i:
	for y in range(int(rect.get("y", 0)) + 1, int(rect.get("y", 0)) + int(rect.get("h", 0)) - 1):
		for x in range(int(rect.get("x", 0)) + 1, int(rect.get("x", 0)) + int(rect.get("w", 0)) - 1):
			var candidate := Vector2i(x, y)
			if _cell_array_has(forbidden_cells, candidate):
				continue
			return candidate
	return _rect_center_cell(rect)


func _cell_array_has(cells: Array, target: Vector2i) -> bool:
	for cell_value in cells:
		var cell: Vector2i = cell_value as Vector2i
		if cell == target:
			return true
	return false


func _clamp_to_rect_inner(cell: Vector2i, rect: Dictionary) -> Vector2i:
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	return Vector2i(clampi(cell.x, x0 + 1, x0 + w - 2), clampi(cell.y, y0 + 1, y0 + h - 2))


func _sign_cell_for_door(rect: Dictionary, door: Vector2i, door_facing: String) -> Vector2i:
	var side := _facing_vector(door_facing)
	var tangent := Vector2i(-side.y, side.x)
	return _clamp_to_rect_edge(door + tangent, rect)


func _clamp_to_rect_edge(cell: Vector2i, rect: Dictionary) -> Vector2i:
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	return Vector2i(clampi(cell.x, x0, x0 + w - 1), clampi(cell.y, y0, y0 + h - 1))


func _apply_farm(leaf: Dictionary) -> void:
	var rect: Dictionary = _inner_rect(leaf, max(7, int(leaf.get("w", 0)) - 2), max(5, int(leaf.get("h", 0)) - 2))
	_paint_rect(rect, "f")
	_mark_rect_road_blocker(rect)
	_add_zone("farm_zone", "farm", "Farm Plots", rect)
	var work_cell := _rect_center_cell(rect)
	var access_cell := _farm_access_cell(rect)
	_road_blockers.erase(_cell_key(access_cell))
	_connector_cells["farm"] = access_cell
	_set_path_tile(access_cell)
	_add_anchor("field_work_spot", "farm_work", work_cell, "down")
	_add_structure("scarecrow", work_cell + Vector2i(-2, -1), { "blocks_movement": true })
	_add_structure("fence", Vector2i(int(rect.get("x", 0)), int(rect.get("y", 0))), { "orientation": "horizontal", "blocks_movement": true })
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


func _apply_training_yard(leaf: Dictionary) -> void:
	var rect: Dictionary = _inner_rect(leaf, max(7, int(leaf.get("w", 0)) - 2), max(5, int(leaf.get("h", 0)) - 2))
	_paint_rect(rect, "t")
	_add_zone("training_zone", "training", "Training Yard", rect)
	var guard_cell := _rect_center_cell(rect) + Vector2i(-2, 0)
	var dummy_a := _rect_center_cell(rect) + Vector2i(2, -1)
	var dummy_b := _rect_center_cell(rect) + Vector2i(2, 1)
	var access_cell := _edge_cell_toward(rect, _get_entrance_cell("plaza"))
	_connector_cells["training"] = access_cell
	_add_anchor("training_yard_guard_post", "training", guard_cell, "left", [guard_cell, guard_cell + Vector2i(1, 0)])
	_add_structure("weapon_rack", guard_cell + Vector2i(0, -2), { "blocks_movement": true })
	_add_structure("target", dummy_a + Vector2i(1, -1), { "blocks_movement": true })
	_add_structure("wood_stump", dummy_b + Vector2i(-1, 1), { "blocks_movement": true })
	_add_training_dummy("village_training_dummy_melee", dummy_a, ["basic_attack", "guard"], { "strength": 4, "agility": 2, "vitality": 5 })
	_add_training_dummy("village_training_dummy_ranged", dummy_b, ["quick_shot", "guard"], { "strength": 2, "agility": 4, "vitality": 4 })


func _apply_wild_gate(leaf: Dictionary) -> void:
	var y := clampi(int(_leaf_center(leaf).y), 2, _height - 3)
	var exit_cell := Vector2i(_width - 1, y)
	_set_tile(exit_cell, "e")
	var gate_anchor := exit_cell + Vector2i(-2, 0)
	_add_zone("wilderness_gate_zone", "wild_entrance", "Wild Gate", {
		"x": max(1, _width - 6),
		"y": max(1, y - 1),
		"w": 5,
		"h": 3,
	})
	_add_entrance("from_wild", gate_anchor, "left")
	_add_anchor("wild_gate_guard_post", "guard_post", gate_anchor + Vector2i(-1, 0), "right", [gate_anchor + Vector2i(-1, 0), gate_anchor])
	_connector_cells["wild_gate"] = gate_anchor
	_add_exit("wild_gate", exit_cell, "res://scenes/locations/test_clearing.tscn", "west_gate")
	_add_structure("signpost", gate_anchor + Vector2i(1, 0), { "blocks_movement": true })
	_add_object({
		"id": "village_wild_gate_sign",
		"display_name": "Wild Gate Sign",
		"grid_position": _dict_cell(gate_anchor + Vector2i(1, 0)),
		"blocks_movement": true,
		"kind": "inspectable",
		"is_inspectable": true,
		"inspect_text": "The generated road leaves town here.",
	})


func _connect_key_places() -> void:
	var plaza_cell := _get_entrance_cell("plaza")
	for connector_value in _connector_cells.values():
		var connector: Vector2i = connector_value as Vector2i
		if connector != Vector2i(-1, -1):
			_route_and_carve_path(plaza_cell, connector)

	for exit_data in (_generated.get("exits", []) as Array):
		var exit_cell: Vector2i = _cell_from_dict((exit_data as Dictionary).get("grid_position", {}) as Dictionary)
		_route_and_carve_path(plaza_cell, exit_cell)
		_set_tile(exit_cell, "e")


func _add_common_decorations() -> void:
	for anchor_id in ["plaza_social_spot", "field_work_spot", "wild_gate_guard_post"]:
		var cell := _get_anchor_cell(anchor_id)
		if cell != Vector2i(-1, -1):
			_add_floor_decoration("road_pebbles", cell + Vector2i(0, 1))
	_add_floor_decoration("flower_patch", _get_entrance_cell("plaza") + Vector2i(-3, -2), { "palette": "spring" })
	_add_floor_decoration("grass_clump", Vector2i(2, _height - 3))
	_add_floor_decoration("stone", Vector2i(_width - 3, _height - 3))


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


func _add_generated_characters() -> void:
	(_generated.get("characters", []) as Array).append({
		"id": "debug_player",
		"source": "res://data/characters/debug_player.json",
		"spawn_at_entrance": true,
		"facing": "down",
	})
	(_generated.get("characters", []) as Array).append({
		"id": "debug_villager",
		"source": "res://data/characters/debug_villager.json",
		"facing": "down",
		"schedule": [
			_schedule_entry("home_morning", "06:00", "07:29", "house_sleep_spot", "left", "rest", "getting ready at home"),
			_schedule_entry("shop_morning", "07:30", "11:59", "shop_counter_spot", "down", "shopkeep", "tending the shop"),
			_schedule_entry("tavern_lunch", "12:00", "12:59", "tavern_table_spot", "right", "eat", "having lunch at the tavern"),
			_schedule_entry("shop_afternoon", "13:00", "17:59", "shop_counter_spot", "down", "shopkeep", "tending the shop"),
			_schedule_entry("tavern_evening", "18:00", "20:59", "tavern_table_spot", "right", "social", "eating at the tavern"),
			_schedule_entry("home_night", "21:00", "05:59", "house_sleep_spot", "left", "sleep", "resting at home"),
		],
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


func _schedule_entry(
	entry_id: String,
	start_time: String,
	end_time: String,
	anchor_id: String,
	facing: String,
	activity_type: String,
	activity: String
) -> Dictionary:
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


func _paint_rect(rect: Dictionary, key: String) -> void:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			_set_tile(Vector2i(x, y), key)


func _route_and_carve_path(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var path: Array[Vector2i] = _find_road_path(from_cell, to_cell)
	if path.is_empty():
		path = _fallback_edge_path(from_cell, to_cell)
	for cell in path:
		_set_path_tile(cell)


func _set_path_tile(cell: Vector2i) -> void:
	if not _in_bounds(cell):
		return
	var key := _tile_at(cell)
	if key == "g":
		_set_tile(cell, "p")


func _find_road_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not _in_bounds(from_cell) or not _in_bounds(to_cell):
		return empty
	var frontier: Array[Vector2i] = [from_cell]
	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = { _cell_key(from_cell): 0.0 }
	while not frontier.is_empty():
		var current_index := _lowest_cost_frontier_index(frontier, cost_so_far, to_cell)
		var current: Vector2i = frontier.pop_at(current_index) as Vector2i
		if current == to_cell:
			return _rebuild_road_path(came_from, from_cell, to_cell)

		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next_cell: Vector2i = current + direction
			if not _road_can_enter(next_cell, to_cell):
				continue
			var current_cost: float = float(cost_so_far.get(_cell_key(current), 0.0))
			var next_cost: float = current_cost + _road_cell_cost(next_cell)
			var next_key := _cell_key(next_cell)
			if cost_so_far.has(next_key) and next_cost >= float(cost_so_far.get(next_key, 0.0)):
				continue
			cost_so_far[next_key] = next_cost
			came_from[next_key] = current
			if not frontier.has(next_cell):
				frontier.append(next_cell)
	return empty


func _lowest_cost_frontier_index(frontier: Array[Vector2i], cost_so_far: Dictionary, target_cell: Vector2i) -> int:
	var best_index := 0
	var best_score := INF
	for index in range(frontier.size()):
		var cell: Vector2i = frontier[index] as Vector2i
		var score: float = float(cost_so_far.get(_cell_key(cell), 0.0)) + float(absi(cell.x - target_cell.x) + absi(cell.y - target_cell.y)) * 1.2
		if score < best_score:
			best_score = score
			best_index = index
	return best_index


func _road_can_enter(cell: Vector2i, target_cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	if cell == target_cell:
		return true
	if _road_blockers.has(_cell_key(cell)):
		return false
	var key := _tile_at(cell)
	if key == "f":
		return false
	if key == "h" or key == "c" or key == "q" or key == "a":
		return false
	return true


func _road_cell_cost(cell: Vector2i) -> float:
	var key := _tile_at(cell)
	match key:
		"p":
			return 1.0
		"s":
			return 1.2
		"g":
			return 3.0
		"t":
			return 8.0
		"e":
			return 1.0
		_:
			return 12.0


func _rebuild_road_path(came_from: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := to_cell
	while cursor != from_cell:
		path.push_front(cursor)
		var cursor_key := _cell_key(cursor)
		if not came_from.has(cursor_key):
			return []
		cursor = came_from.get(cursor_key, from_cell) as Vector2i
	return path


func _fallback_edge_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var edge_y := clampi(_height - 3, 1, _height - 2)
	var cursor := from_cell
	while cursor.y != edge_y:
		cursor.y += 1 if edge_y > cursor.y else -1
		path.append(cursor)
	while cursor.x != to_cell.x:
		cursor.x += 1 if to_cell.x > cursor.x else -1
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if to_cell.y > cursor.y else -1
		path.append(cursor)
	return path


func _set_tile(cell: Vector2i, key: String) -> void:
	if not _in_bounds(cell):
		return
	(_tiles[cell.y] as Array)[cell.x] = key


func _tile_at(cell: Vector2i) -> String:
	if not _in_bounds(cell):
		return ""
	return str((_tiles[cell.y] as Array)[cell.x])


func _stringify_tiles() -> Array[String]:
	var result: Array[String] = []
	for row_value in _tiles:
		var row: Array = row_value as Array
		var text := ""
		for cell_key in row:
			text += str(cell_key)
		result.append(text)
	return result


func _add_zone(zone_id: String, zone_type: String, display_name: String, bounds: Dictionary) -> void:
	(_generated.get("zones", []) as Array).append({
		"id": zone_id,
		"type": zone_type,
		"display_name": display_name,
		"bounds": bounds.duplicate(true),
	})


func _add_structure(structure_type: String, cell: Vector2i, extra: Dictionary = {}) -> void:
	var entry := {
		"type": structure_type,
	}
	if extra.has("bounds"):
		entry["bounds"] = (extra.get("bounds", {}) as Dictionary).duplicate(true)
	else:
		entry["grid_position"] = _dict_cell(cell)
	entry.merge(extra, true)
	(_generated.get("structures", []) as Array).append(entry)


func _add_roof(roof_id: String, palette: String, bounds: Dictionary) -> void:
	(_generated.get("roofs", []) as Array).append({
		"id": roof_id,
		"palette": palette,
		"bounds": {
			"x": int(bounds.get("x", 0)),
			"y": int(bounds.get("y", 0)),
			"w": int(bounds.get("w", 0)),
			"h": max(3, int(bounds.get("h", 0)) - 1),
		},
		"hide_bounds": bounds.duplicate(true),
	})


func _add_floor_decoration(decoration_type: String, cell: Vector2i, extra: Dictionary = {}) -> void:
	if not _in_bounds(cell):
		return
	var entry := {
		"type": decoration_type,
		"grid_position": _dict_cell(cell),
	}
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
	_reserve_cell(cell)
	(_generated.get("anchors", []) as Array).append(anchor)


func _add_exit(exit_id: String, cell: Vector2i, target_scene_path: String, target_entrance_id: String) -> void:
	(_generated.get("exits", []) as Array).append({
		"id": exit_id,
		"grid_position": _dict_cell(cell),
		"target_scene_path": target_scene_path,
		"target_entrance_id": target_entrance_id,
	})


func _add_object(object_data: Dictionary) -> void:
	var cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
	_objects_by_cell[_cell_key(cell)] = str(object_data.get("id", ""))
	(_generated.get("objects", []) as Array).append(object_data)


func _reserve_cell(cell: Vector2i) -> void:
	_reserved_cells[_cell_key(cell)] = true


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


func _rect_center(rect: Dictionary) -> Vector2:
	return Vector2(
		float(int(rect.get("x", 0))) + float(int(rect.get("w", 0))) * 0.5,
		float(int(rect.get("y", 0))) + float(int(rect.get("h", 0))) * 0.5
	)


func _edge_score(center: Vector2) -> float:
	var dx: float = min(center.x, float(_width) - center.x) / max(1.0, float(_width) * 0.5)
	var dy: float = min(center.y, float(_height) - center.y) / max(1.0, float(_height) * 0.5)
	return 1.0 - min(dx, dy)


func _west_score(center: Vector2) -> float:
	return 1.0 - clampf(center.x / max(1.0, float(_width)), 0.0, 1.0)


func _east_score(center: Vector2) -> float:
	return clampf(center.x / max(1.0, float(_width)), 0.0, 1.0)


func _south_score(center: Vector2) -> float:
	return clampf(center.y / max(1.0, float(_height)), 0.0, 1.0)


func _residential_cluster_score(center: Vector2, placed_buildings: Array[Dictionary]) -> float:
	var best := 0.0
	for building_value in placed_buildings:
		var building: Dictionary = building_value as Dictionary
		var spec: Dictionary = building.get("spec", {}) as Dictionary
		if str(spec.get("role", "")) != "home":
			continue
		var leaf: Dictionary = building.get("leaf", {}) as Dictionary
		best = maxf(best, 12.0 - center.distance_to(_leaf_center(leaf)) * 0.5)
	return best


func _add_placement_log(subject: String, leaf: Dictionary, reason: String) -> void:
	_placement_log.append({
		"subject": subject,
		"leaf": leaf.duplicate(true),
		"reason": reason,
	})


func _mark_rect_road_blocker(rect: Dictionary) -> void:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			_road_blockers[_cell_key(Vector2i(x, y))] = true


func _farm_access_cell(rect: Dictionary) -> Vector2i:
	return _edge_cell_toward(rect, _get_entrance_cell("plaza"))


func _edge_cell_toward(rect: Dictionary, target_cell: Vector2i) -> Vector2i:
	var center := _rect_center_cell(rect)
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	var dx: int = target_cell.x - center.x
	var dy: int = target_cell.y - center.y
	if absi(dx) > absi(dy):
		if dx >= 0:
			return Vector2i(clampi(x0 + w, 0, _width - 1), clampi(center.y, y0, y0 + h - 1))
		return Vector2i(clampi(x0 - 1, 0, _width - 1), clampi(center.y, y0, y0 + h - 1))
	if dy >= 0:
		return Vector2i(clampi(center.x, x0, x0 + w - 1), clampi(y0 + h, 0, _height - 1))
	return Vector2i(clampi(center.x, x0, x0 + w - 1), clampi(y0 - 1, 0, _height - 1))


func _facing_vector(facing: String) -> Vector2i:
	match facing:
		"up":
			return Vector2i.UP
		"right":
			return Vector2i.RIGHT
		"left":
			return Vector2i.LEFT
		_:
			return Vector2i.DOWN


func _opposite_facing(facing: String) -> String:
	match facing:
		"up":
			return "down"
		"down":
			return "up"
		"left":
			return "right"
		"right":
			return "left"
		_:
			return "down"


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
		var cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
		blockers[_cell_key(cell)] = str(object_data.get("id", ""))
	return blockers


func _contract_has_reachable_adjacent_cell(
	grid: LocationGrid,
	start_cell: Vector2i,
	target_cell: Vector2i,
	blockers: Dictionary
) -> bool:
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
