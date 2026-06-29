extends SceneTree

const BuildingInteriorGeneratorScript := preload("res://scripts/systems/scenes/building_interior_generator.gd")
const VillageRoadGeneratorScript := preload("res://scripts/systems/scenes/village_road_generator.gd")
const SETTLEMENT_SOURCE_PATH := "res://data/locations/smoke_generated_settlement.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var source_data: Dictionary = _load_json_resource(SETTLEMENT_SOURCE_PATH)
	var generator: RefCounted = VillageRoadGeneratorScript.new()
	var generated: Dictionary = generator.generate_location(source_data)
	var validation_errors: Array[String] = generator.validate_location_contract(generated)
	if not validation_errors.is_empty():
		_fail("v60 generated village has validation errors: %s" % str(validation_errors))
		return

	var summary: Dictionary = generated.get("generation_summary", {}) as Dictionary
	if str(summary.get("type", "")) != "agent_settlement_blueprint":
		_fail("v60 default generator did not use agent settlement blueprint: %s" % str(summary.get("type", "")))
		return
	if str(summary.get("default_layout_authority", "")) != "agent_settlement_planner":
		_fail("v60 default layout authority is not the agent planner")
		return
	if bool(summary.get("uses_bsp_layout", true)):
		_fail("v60 default generator still reports BSP layout usage")
		return
	if int(summary.get("compiler_recovery_count", 0)) != 0:
		_fail("v60.3 default generator used compiler path recovery: %s" % str(summary.get("compiler_recovery_log", [])))
		return

	var planner_summary: Dictionary = summary.get("planner", {}) as Dictionary
	if str(planner_summary.get("type", "")) != "agent_settlement_blueprint":
		_fail("v60 planner summary missing agent blueprint type")
		return
	if str(planner_summary.get("control_model", "")) != "open_growth_auction":
		_fail("v60 planner did not use open growth auction control")
		return
	if bool(planner_summary.get("scripted_stage_sequence", true)):
		_fail("v60 planner reports a scripted stage sequence")
		return
	if str(planner_summary.get("required_goal_policy", "")) != "priority_filtered_auction":
		_fail("v60 planner did not protect required goals from optional growth")
		return
	if (planner_summary.get("feature_maps", {}) as Dictionary).is_empty():
		_fail("v60 planner summary missing feature maps")
		return
	for required_agent in ["road_growth", "civilian_plot", "residential_bid", "shop_bid", "public_space", "farm_claim", "training_claim", "gate_claim"]:
		if not (planner_summary.get("committed_agents", []) as Array).has(required_agent):
			_fail("v60 planner did not commit required growth agent: %s" % required_agent)
			return
	if int(planner_summary.get("auction_count", 0)) < 20:
		_fail("v60 planner auction loop did not run enough growth turns")
		return
	if not (planner_summary.get("unmet_goals", []) as Array).is_empty():
		_fail("v60 planner left unmet growth goals: %s" % str(planner_summary.get("unmet_goals", [])))
		return
	if int(planner_summary.get("building_plan_count", 0)) < 3:
		_fail("v60 planner stopped at the minimum residence/shop building loop")
		return
	if not _has_optional_growth_request(planner_summary):
		_fail("v60 planner did not differentiate any optional growth request")
		return
	if not _has_real_candidate_competition(planner_summary):
		_fail("v60 planner did not expose real multi-candidate arbitration")
		return

	var second_generator: RefCounted = VillageRoadGeneratorScript.new()
	var second_generated: Dictionary = second_generator.generate_location(source_data)
	if JSON.stringify(_generation_signature(generated)) != JSON.stringify(_generation_signature(second_generated)):
		_fail("v60 generation is not deterministic for the fixed seed")
		return

	var grid: LocationGrid = LocationGrid.from_dictionary(generated)
	if not grid.is_valid():
		_fail("v60 generated grid is invalid")
		return
	var blockers: Dictionary = _blocking_object_cells(generated)
	var plaza_cell := _entrance_cell(generated, "plaza")
	if plaza_cell == Vector2i(-1, -1):
		_fail("v60 generated village is missing plaza entrance")
		return
	if not _is_open_cell(grid, plaza_cell, blockers):
		_fail("v60 plaza entrance is blocked")
		return
	if int(summary.get("road_cell_count", 0)) <= 0:
		_fail("v60 generated village has no road cells")
		return
	if (generated.get("parcels", []) as Array).is_empty():
		_fail("v60 generated village has no parcels")
		return
	if not _has_multi_side_parcel_access(generated):
		_fail("v60.3 generated parcels did not expose multi-direction access")
		return
	if (generated.get("buildings", []) as Array).size() < 3:
		_fail("v60 generated village compiled too few buildings from agent bids")
		return
	if _first_building_by_archetype(generated, "shop").is_empty():
		_fail("v60 generated village is missing merchant shop building")
		return

	for required_anchor in ["plaza_social_spot", "training_yard_guard_post", "wild_gate_guard_post", "field_work_spot"]:
		if not _assert_reachable_anchor(grid, blockers, plaza_cell, required_anchor):
			return

	if not _assert_building_doors_and_interiors(generated, grid, blockers, plaza_cell):
		return
	if not _assert_schedule_targets(generated, grid, blockers, plaza_cell):
		return

	print("v60 agent settlement smoke test passed")
	quit(0)


func _generation_signature(generated: Dictionary) -> Dictionary:
	var buildings: Array[Dictionary] = []
	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		buildings.append({
			"id": str(building.get("id", "")),
			"archetype_id": str(building.get("archetype_id", "")),
			"prefab_id": str(building.get("prefab_id", "")),
			"bounds": (building.get("bounds", {}) as Dictionary).duplicate(true),
			"doorstep": (building.get("doorstep", {}) as Dictionary).duplicate(true),
		})
	var anchors: Array[Dictionary] = []
	for anchor_value in (generated.get("anchors", []) as Array):
		var anchor: Dictionary = anchor_value as Dictionary
		anchors.append({
			"id": str(anchor.get("id", "")),
			"kind": str(anchor.get("kind", "")),
			"grid_position": (anchor.get("grid_position", {}) as Dictionary).duplicate(true),
		})
	var parcels: Array[Dictionary] = []
	for parcel_value in (generated.get("parcels", []) as Array):
		var parcel: Dictionary = parcel_value as Dictionary
		parcels.append({
			"id": str(parcel.get("id", "")),
			"semantic_zone_id": str(parcel.get("semantic_zone_id", "")),
			"bounds": (parcel.get("bounds", {}) as Dictionary).duplicate(true),
			"door_slot": (parcel.get("door_slot", {}) as Dictionary).duplicate(true),
		})
	return {
		"tiles": (generated.get("tiles", []) as Array).duplicate(),
		"parcels": parcels,
		"buildings": buildings,
		"anchors": anchors,
	}


func _has_real_candidate_competition(planner_summary: Dictionary) -> bool:
	var competitive_turns := 0
	for auction_value in (planner_summary.get("auction_log", []) as Array):
		var auction: Dictionary = auction_value as Dictionary
		if int(auction.get("candidate_count", 0)) >= 3:
			competitive_turns += 1
	return competitive_turns >= 8


func _has_optional_growth_request(planner_summary: Dictionary) -> bool:
	var assigned_requests: Array = planner_summary.get("assigned_request_ids", []) as Array
	for request_id in ["workshop", "tavern", "farmer_cottage", "worker_cottage", "storage_shed", "guardhouse"]:
		if assigned_requests.has(request_id):
			return true
	return false


func _has_multi_side_parcel_access(generated: Dictionary) -> bool:
	var sides: Dictionary = {}
	for parcel_value in (generated.get("parcels", []) as Array):
		var parcel: Dictionary = parcel_value as Dictionary
		var side := str(parcel.get("access_side", ""))
		if not side.is_empty():
			sides[side] = true
	return sides.size() >= 2


func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}


func _assert_building_doors_and_interiors(generated: Dictionary, grid: LocationGrid, blockers: Dictionary, plaza_cell: Vector2i) -> bool:
	var interior_source: Dictionary = _load_json_resource("res://data/locations/generated_building_interior.json")
	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var building_id := str(building.get("id", ""))
		var exterior_anchor_id := str(building.get("exterior_door_anchor_id", ""))
		if exterior_anchor_id.is_empty() or grid.get_anchor(exterior_anchor_id).is_empty():
			_fail("v60 building missing exterior door anchor: %s" % building_id)
			return false
		var doorstep := _cell_from_dict(building.get("doorstep", {}) as Dictionary)
		if not _is_open_cell(grid, doorstep, blockers):
			_fail("v60 building door frontage is blocked: %s" % building_id)
			return false
		if not _has_path(grid, plaza_cell, doorstep, blockers):
			_fail("v60 building door frontage is unreachable: %s" % building_id)
			return false
		var interior_id := str(building.get("interior_location_id", ""))
		var manifest := _interior_manifest(generated, interior_id)
		if manifest.is_empty():
			_fail("v60 building missing interior manifest: %s" % building_id)
			return false
		var interior_generator: RefCounted = BuildingInteriorGeneratorScript.new()
		var interior_data: Dictionary = interior_generator.generate_location(interior_source, manifest.get("generation_context", {}) as Dictionary)
		var interior_grid := LocationGrid.from_dictionary(interior_data)
		if not interior_grid.is_valid():
			_fail("v60 generated interior grid is invalid: %s" % interior_id)
			return false
		for interior_anchor in ["entry", "exit", "primary"]:
			if interior_grid.get_anchor(interior_anchor).is_empty():
				_fail("v60 generated interior missing anchor %s in %s" % [interior_anchor, interior_id])
				return false
	return true


func _assert_schedule_targets(generated: Dictionary, grid: LocationGrid, blockers: Dictionary, plaza_cell: Vector2i) -> bool:
	var found_merchant_shop := false
	var found_guard_training := false
	var found_guard_gate := false
	var shop_building := _first_building_by_archetype(generated, "shop")
	for character_value in (generated.get("characters", []) as Array):
		var character: Dictionary = character_value as Dictionary
		var character_id := str(character.get("id", ""))
		if character_id != "debug_villager" and character_id != "debug_guard":
			continue
		for schedule_value in (character.get("schedule", []) as Array):
			var entry: Dictionary = schedule_value as Dictionary
			var location_id := str(entry.get("location_id", str(generated.get("id", ""))))
			var anchor_id := str(entry.get("anchor_id", ""))
			if anchor_id.is_empty():
				_fail("v60 schedule entry missing anchor id: %s / %s" % [character_id, str(entry.get("id", ""))])
				return false
			if entry.has("grid_position"):
				_fail("v60 schedule entry should resolve through anchors, not grid_position: %s / %s" % [character_id, str(entry.get("id", ""))])
				return false
			if character_id == "debug_villager" and not shop_building.is_empty() and location_id == str(shop_building.get("interior_location_id", "")) and anchor_id == "primary":
				found_merchant_shop = true
			if character_id == "debug_guard" and anchor_id == "training_yard_guard_post":
				found_guard_training = true
			if character_id == "debug_guard" and anchor_id == "wild_gate_guard_post":
				found_guard_gate = true
			if location_id == str(generated.get("id", "")):
				if not _assert_reachable_anchor(grid, blockers, plaza_cell, anchor_id):
					return false
			else:
				var transition_anchor_id := str((entry.get("transition_anchor_by_location", {}) as Dictionary).get(str(generated.get("id", "")), ""))
				if transition_anchor_id.is_empty():
					_fail("v60 cross-scene schedule missing exterior transition anchor: %s / %s" % [character_id, str(entry.get("id", ""))])
					return false
				if not _assert_reachable_anchor(grid, blockers, plaza_cell, transition_anchor_id):
					return false
				if _interior_manifest(generated, location_id).is_empty():
					_fail("v60 cross-scene schedule references missing interior location: %s" % location_id)
					return false
	if not found_merchant_shop:
		_fail("v60 merchant schedule did not keep the generated shop primary anchor")
		return false
	if not found_guard_training or not found_guard_gate:
		_fail("v60 guard schedule did not keep training and gate anchors")
		return false
	return true


func _assert_reachable_anchor(grid: LocationGrid, blockers: Dictionary, plaza_cell: Vector2i, anchor_id: String) -> bool:
	var anchor: Dictionary = grid.get_anchor(anchor_id)
	if anchor.is_empty():
		_fail("v60 missing anchor: %s" % anchor_id)
		return false
	var anchor_cell := _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
	if not _is_open_cell(grid, anchor_cell, blockers):
		_fail("v60 anchor is blocked: %s at %s" % [anchor_id, anchor_cell])
		return false
	if not _has_path(grid, plaza_cell, anchor_cell, blockers):
		_fail("v60 anchor is unreachable: %s at %s" % [anchor_id, anchor_cell])
		return false
	return true


func _first_building_by_archetype(generated: Dictionary, archetype_id: String) -> Dictionary:
	for building_value in (generated.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		if str(building.get("archetype_id", "")) == archetype_id:
			return building
	return {}


func _interior_manifest(generated: Dictionary, interior_id: String) -> Dictionary:
	for manifest_value in (generated.get("interiors", []) as Array):
		var manifest: Dictionary = manifest_value as Dictionary
		if str(manifest.get("location_id", "")) == interior_id:
			return manifest
	return {}


func _blocking_object_cells(generated: Dictionary) -> Dictionary:
	var blockers: Dictionary = {}
	for object_value in (generated.get("objects", []) as Array):
		var object_data: Dictionary = object_value as Dictionary
		if not bool(object_data.get("blocks_movement", true)):
			continue
		var cell: Vector2i = _cell_from_dict(object_data.get("grid_position", {}) as Dictionary)
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
