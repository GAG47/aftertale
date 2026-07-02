class_name VillageRoadGenerator
extends RefCounted

const DEFAULT_WIDTH := 36
const DEFAULT_HEIGHT := 24
const DEFAULT_TILE_SIZE := 32
const DEFAULT_BUILDING_PREFAB_CATALOG := "res://data/generation/building_prefabs.json"
const AgentSettlementPlannerScript := preload("res://scripts/systems/scenes/agent_settlement_planner.gd")
const BuildingPrefabCatalogScript := preload("res://scripts/systems/scenes/building_prefab_catalog.gd")

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
var _compiler_recovery_log: Array[Dictionary] = []
var _parcels: Array[Dictionary] = []
var _building_instances: Array[Dictionary] = []
var _interior_manifests: Array[Dictionary] = []
var _town_character_rows: Array[Dictionary] = []
var _building_adaptation_failures: Array[Dictionary] = []
var _building_prefabs: Array[Dictionary] = []
var _building_prefab_catalog_path: String = DEFAULT_BUILDING_PREFAB_CATALOG
var _generated: Dictionary = {}
var _uses_legacy_layout: bool = false


func generate_location(source_data: Dictionary) -> Dictionary:
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	_rng.seed = int(generator_data.get("seed", 5601))
	var size: Dictionary = generator_data.get("size", source_data.get("size", {})) as Dictionary
	_width = max(24, int(size.get("width", DEFAULT_WIDTH)))
	_height = max(18, int(size.get("height", DEFAULT_HEIGHT)))
	_reset_tiles()
	_building_prefab_catalog_path = str(generator_data.get("building_prefab_catalog", DEFAULT_BUILDING_PREFAB_CATALOG))
	_building_prefabs = BuildingPrefabCatalogScript.load_prefabs(_building_prefab_catalog_path)
	if _building_prefabs.is_empty():
		push_error("VillageRoadGenerator has no building prefabs from catalog: %s" % _building_prefab_catalog_path)

	var planner_blueprint: Dictionary = {}
	var road_plan: Dictionary = {}
	var uses_legacy_layout := _layout_uses_legacy_road_first(generator_data)
	_uses_legacy_layout = uses_legacy_layout
	_generated = _base_location(source_data)
	var generated_state: Dictionary = _generated.get("state", {}) as Dictionary
	generated_state["generation"] = "legacy_village_road_first" if uses_legacy_layout else "agent_settlement_blueprint"
	_generated["state"] = generated_state
	var plan: Dictionary = {}
	if uses_legacy_layout:
		road_plan = _build_road_plan()
		_apply_road_skeleton(road_plan)
		plan = _assign_town_plan(road_plan)
	else:
		planner_blueprint = _run_agent_blueprint_planner(source_data, generator_data)
		road_plan = _road_plan_from_agent_blueprint(planner_blueprint)
		_apply_planner_roads(road_plan)
		plan = _compile_agent_blueprint_plan(planner_blueprint)

	_apply_plaza(plan.get("plaza", {}) as Dictionary)
	_apply_farm(plan.get("farm", {}) as Dictionary)
	_apply_training_yard(plan.get("training", {}) as Dictionary)
	_apply_wild_gate(plan.get("wild_gate", {}) as Dictionary)
	var building_index := 0
	for building_value in (plan.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		building_index += 1
		_apply_building_spec(
			building.get("spec", {}) as Dictionary,
			building.get("lot", {}) as Dictionary,
			building_index,
			building.get("parcel", {}) as Dictionary,
			building.get("prefab", {}) as Dictionary,
			building.get("placement", {}) as Dictionary
		)
	if uses_legacy_layout:
		_connect_key_places(true)
	_apply_planned_decorations(plan.get("decoration_slots", []) as Array)
	_add_common_decorations()
	_add_generated_characters()
	_refresh_interior_character_contexts()
	_generated["tiles"] = _stringify_tiles()
	_generated["generation_summary"] = {
		"type": "legacy_village_road_first" if uses_legacy_layout else "agent_settlement_blueprint",
		"seed": int(generator_data.get("seed", 5601)),
		"default_layout_authority": "legacy_road_first" if uses_legacy_layout else "agent_settlement_planner",
		"uses_bsp_layout": false,
		"road_cell_count": (road_plan.get("road_cells", []) as Array).size(),
		"frontage_candidate_count": (plan.get("frontage_candidates", []) as Array).size(),
		"planner": planner_blueprint.get("planning_summary", {}) if not planner_blueprint.is_empty() else {},
		"anchor_count": (_generated.get("anchors", []) as Array).size(),
		"object_count": (_generated.get("objects", []) as Array).size(),
		"compiler_recovery_count": _compiler_recovery_log.size(),
		"compiler_recovery_log": _compiler_recovery_log.duplicate(true),
		"parcel_shape_model": "cell_set_organic_growth_lot" if not uses_legacy_layout else "rectangular_legacy_lot",
		"building_placement_model": "south_door_core_fitted_to_parcel_cells" if not uses_legacy_layout else "legacy_frontage_prefab_fit",
		"building_adaptation_failure_count": _building_adaptation_failures.size(),
		"building_adaptation_failures": _building_adaptation_failures.duplicate(true),
		"placement_log": _placement_log.duplicate(true),
	}
	var contract_errors: Array[String] = validate_location_contract(_generated)
	for error in contract_errors:
		push_error("VillageRoadGenerator contract error: %s" % error)
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
	errors.append_array(_contract_validate_road_network(grid))
	var generation_summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	var is_agent_settlement := str(generation_summary.get("type", "")) == "agent_settlement_blueprint"
	if is_agent_settlement and int(generation_summary.get("compiler_recovery_count", 0)) > 0:
		errors.append("agent settlement used compiler path recovery: %s" % str(generation_summary.get("compiler_recovery_log", [])))
	if is_agent_settlement:
		if str(generation_summary.get("parcel_shape_model", "")) != "cell_set_organic_growth_lot":
			errors.append("agent settlement must expose organic cell-set parcel shape model")
		if str(generation_summary.get("building_placement_model", "")) != "south_door_core_fitted_to_parcel_cells":
			errors.append("agent settlement must fit south-door building cores into parcel cells")
		for failure_value in (generation_summary.get("building_adaptation_failures", []) as Array):
			var failure: Dictionary = failure_value as Dictionary
			if bool(failure.get("required", false)):
				errors.append("required building core adaptation failed: %s" % str(failure))

	var town_zone_ids: Dictionary = {}
	for zone_value in (location_data.get("town_zones", []) as Array):
		var zone: Dictionary = zone_value as Dictionary
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty():
			errors.append("town zone missing id")
			continue
		town_zone_ids[zone_id] = true
	if town_zone_ids.is_empty():
		errors.append("generated village missing semantic town zones")
	var required_zone_ids := _contract_required_zone_ids(location_data)
	if _contract_is_agent_settlement(location_data) and required_zone_ids.is_empty():
		errors.append("agent planner summary missing required_zone_ids")
	for required_zone in required_zone_ids:
		if not town_zone_ids.has(required_zone):
			errors.append("generated village missing required town zone: %s" % required_zone)

	var parcel_ids: Dictionary = {}
	var parcel_cell_keys_by_id: Dictionary = {}
	for parcel_value in (location_data.get("parcels", []) as Array):
		var parcel: Dictionary = parcel_value as Dictionary
		var parcel_id := str(parcel.get("id", ""))
		if parcel_id.is_empty():
			errors.append("parcel missing id")
			continue
		parcel_ids[parcel_id] = true
		if str(parcel.get("door_side", "")) != "south":
			errors.append("ordinary parcel door_side must be south: %s" % parcel_id)
		var access_side := str(parcel.get("access_side", ""))
		if access_side.is_empty() or not ["north", "east", "south", "west"].has(access_side):
			errors.append("parcel missing valid access_side: %s" % parcel_id)
		if (parcel.get("door_slot", {}) as Dictionary).is_empty():
			errors.append("parcel missing door_slot: %s" % parcel_id)
		if (parcel.get("road_anchor", {}) as Dictionary).is_empty():
			errors.append("parcel missing road_anchor: %s" % parcel_id)
		var semantic_zone_id := str(parcel.get("semantic_zone_id", ""))
		if semantic_zone_id.is_empty():
			errors.append("parcel missing semantic_zone_id: %s" % parcel_id)
		elif not town_zone_ids.has(semantic_zone_id):
			errors.append("parcel references missing semantic town zone: %s / %s" % [parcel_id, semantic_zone_id])
		var parcel_cells: Array = parcel.get("cells", []) as Array
		var parcel_cell_keys := _parcel_cell_key_set(parcel, not is_agent_settlement)
		parcel_cell_keys_by_id[parcel_id] = parcel_cell_keys
		if is_agent_settlement:
			if parcel_cells.is_empty():
				errors.append("agent parcel missing cell set: %s" % parcel_id)
			if int(parcel.get("cell_count", -1)) != parcel_cells.size():
				errors.append("agent parcel cell_count does not match cells: %s" % parcel_id)
			if not str(parcel.get("shape_model", "")).begins_with("cell_set"):
				errors.append("agent parcel missing cell-set shape model: %s" % parcel_id)
			var access_cell := _cell_from_dict(parcel.get("access_cell", {}) as Dictionary)
			if access_cell == Vector2i(-1, -1) or not parcel_cell_keys.has(_cell_key(access_cell)):
				errors.append("agent parcel access cell is outside parcel cells: %s" % parcel_id)

	var prefab_ids: Dictionary = {}
	for prefab_value in (location_data.get("building_prefabs", []) as Array):
		var prefab: Dictionary = prefab_value as Dictionary
		var prefab_id := str(prefab.get("id", ""))
		if prefab_id.is_empty():
			errors.append("building prefab missing id")
			continue
		prefab_ids[prefab_id] = true
		if str(prefab.get("door_side", "")) != "south":
			errors.append("ordinary building prefab door_side must be south: %s" % prefab_id)
		var exterior_slot_contract: Dictionary = prefab.get("exterior_slot_contract", {}) as Dictionary
		if str(exterior_slot_contract.get("content_source", "")) != "prefab_declared_only":
			errors.append("building prefab exterior slots must come from prefab declarations: %s" % prefab_id)
		if str(exterior_slot_contract.get("coordinate_space", "")) != "prefab_local_grid":
			errors.append("building prefab exterior slots must use prefab_local_grid: %s" % prefab_id)
		var visual: Dictionary = prefab.get("visual", {}) as Dictionary
		if str(visual.get("render_kind", "")) != "placeholder_facade":
			errors.append("building prefab missing render_kind placeholder_facade: %s" % prefab_id)
		if str(visual.get("placeholder_style", "")).is_empty():
			errors.append("building prefab missing placeholder style: %s" % prefab_id)
		for slot_value in (prefab.get("exterior_slots", []) as Array):
			var slot: Dictionary = slot_value as Dictionary
			if str(slot.get("id", "")).is_empty():
				errors.append("building prefab exterior slot missing id: %s" % prefab_id)
			if (slot.get("local_position", {}) as Dictionary).is_empty():
				errors.append("building prefab exterior slot missing local_position: %s / %s" % [prefab_id, str(slot.get("id", ""))])
			if bool(slot.get("blocks_movement", false)) or bool(slot.get("blocks_sight", false)):
				errors.append("v58 exterior slots must not block gameplay cells: %s / %s" % [prefab_id, str(slot.get("id", ""))])

	var floor_overlay_counts: Dictionary = {
		"parcel_surface": 0,
		"front_clearance": 0,
		"front_path": 0,
		"building_foundation": 0,
	}
	for overlay_value in (location_data.get("floor_overlays", []) as Array):
		var overlay: Dictionary = overlay_value as Dictionary
		var overlay_type := str(overlay.get("type", ""))
		if floor_overlay_counts.has(overlay_type):
			floor_overlay_counts[overlay_type] = int(floor_overlay_counts.get(overlay_type, 0)) + 1

	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var building_id := str(building.get("id", ""))
		var parcel_id := str(building.get("parcel_id", ""))
		var prefab_id := str(building.get("prefab_id", ""))
		if not parcel_ids.has(parcel_id):
			errors.append("building references missing parcel: %s / %s" % [building_id, parcel_id])
		if not prefab_ids.has(prefab_id):
			errors.append("building references missing prefab: %s / %s" % [building_id, prefab_id])
		if str(building.get("door_side", "")) != "south":
			errors.append("ordinary building door_side must be south: %s" % building_id)
		var prefab_contract: Dictionary = building.get("prefab_contract", {}) as Dictionary
		var building_slot_contract: Dictionary = prefab_contract.get("exterior_slot_contract", {}) as Dictionary
		if str(building_slot_contract.get("content_source", "")) != "prefab_declared_only":
			errors.append("building missing prefab-only exterior slot contract: %s" % building_id)
		var declared_slots: Array = prefab_contract.get("exterior_slots", []) as Array
		var materialized_slots: Array = building.get("materialized_exterior_slots", []) as Array
		var core_placement: Dictionary = building.get("core_placement", {}) as Dictionary
		var uses_adaptive_core := str(core_placement.get("model", "")) == "south_door_core_fitted_to_parcel_cells"
		if not uses_adaptive_core and materialized_slots.size() != declared_slots.size():
			errors.append("building did not materialize all declared exterior slots: %s" % building_id)
		if is_agent_settlement:
			if not uses_adaptive_core:
				errors.append("agent building missing adaptive core placement record: %s" % building_id)
			if str(core_placement.get("door_policy", "")) != "south_only":
				errors.append("agent building core does not enforce south-only doors: %s" % building_id)
			var parcel_cell_keys: Dictionary = parcel_cell_keys_by_id.get(parcel_id, {}) as Dictionary
			if parcel_cell_keys.is_empty():
				errors.append("agent building parcel has no cell keys: %s / %s" % [building_id, parcel_id])
			else:
				var bounds: Dictionary = building.get("bounds", {}) as Dictionary
				if not _rect_inside_cell_set(bounds, parcel_cell_keys):
					errors.append("agent building core footprint is outside parcel cells: %s" % building_id)
				var door := _cell_from_dict(building.get("door", {}) as Dictionary)
				var doorstep := _cell_from_dict(building.get("doorstep", {}) as Dictionary)
				if door.y != int(bounds.get("y", 0)) + int(bounds.get("h", 0)) - 1:
					errors.append("agent building door is not on south edge: %s" % building_id)
				if not parcel_cell_keys.has(_cell_key(door)):
					errors.append("agent building door is outside parcel cells: %s" % building_id)
				if not parcel_cell_keys.has(_cell_key(doorstep)):
					errors.append("agent building doorstep is outside parcel cells: %s" % building_id)
				for path_value in (building.get("yard_path", []) as Array):
					var path_cell := _cell_from_dict(path_value as Dictionary)
					if not parcel_cell_keys.has(_cell_key(path_cell)):
						errors.append("agent building yard path leaves parcel cells: %s at %s" % [building_id, path_cell])
				for yard_value in (building.get("yard_cells", []) as Array):
					var yard_cell := _cell_from_dict(yard_value as Dictionary)
					if not parcel_cell_keys.has(_cell_key(yard_cell)):
						errors.append("agent building yard cell leaves parcel cells: %s at %s" % [building_id, yard_cell])

	var building_count := (location_data.get("buildings", []) as Array).size()
	for overlay_type in floor_overlay_counts.keys():
		if int(floor_overlay_counts.get(overlay_type, 0)) < building_count:
			errors.append("missing parcel presentation overlay type: %s" % str(overlay_type))
	errors.append_array(_contract_validate_required_buildings(location_data))
	errors.append_array(_contract_validate_interiors_and_transitions(location_data, grid, blockers, plaza_cell))

	var required_anchor_ids: Array[String] = [
		"plaza_social_spot",
		"training_yard_guard_post",
		"wild_gate_guard_post",
		"field_work_spot",
	]
	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		required_anchor_ids.append(str(building.get("exterior_door_anchor_id", "")))

	for anchor_id in required_anchor_ids:
		if anchor_id.is_empty():
			errors.append("building is missing exterior door anchor id")
			continue
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
			var scheduled_location_id := str(entry.get("location_id", str(location_data.get("id", ""))))
			var anchor_id: String = str(entry.get("anchor_id", ""))
			if anchor_id.is_empty():
				errors.append("schedule entry missing anchor_id: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
			elif scheduled_location_id == str(location_data.get("id", "")):
				var schedule_anchor: Dictionary = grid.get_anchor(anchor_id)
				if schedule_anchor.is_empty():
					errors.append("schedule references missing anchor: %s" % anchor_id)
				else:
					var schedule_anchor_cell: Vector2i = _cell_from_dict(schedule_anchor.get("grid_position", {}) as Dictionary)
					if not _contract_is_open_cell(grid, schedule_anchor_cell, blockers):
						errors.append("schedule anchor is blocked: %s at %s" % [anchor_id, schedule_anchor_cell])
					elif not _contract_has_path(grid, plaza_cell, schedule_anchor_cell, blockers):
						errors.append("schedule anchor is unreachable: %s at %s" % [anchor_id, schedule_anchor_cell])
			elif scheduled_location_id != str(location_data.get("id", "")):
				var anchors_by_location: Dictionary = entry.get("transition_anchor_by_location", {}) as Dictionary
				var transition_anchor_id := str(anchors_by_location.get(str(location_data.get("id", "")), ""))
				if transition_anchor_id.is_empty():
					errors.append("cross-scene schedule missing transition anchor for source location: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])
				elif grid.get_anchor(transition_anchor_id).is_empty():
					errors.append("cross-scene schedule references missing transition anchor: %s" % transition_anchor_id)
				if not _contract_schedule_interior_anchor_is_valid(location_data, scheduled_location_id, anchor_id):
					errors.append("cross-scene schedule references invalid interior anchor: %s / %s" % [scheduled_location_id, anchor_id])
			if entry.has("grid_position"):
				errors.append("schedule entry should not hand-author grid_position: %s / %s" % [str(character.get("id", "")), str(entry.get("id", ""))])

	errors.append_array(_contract_validate_decoration_slots(location_data, required_anchor_ids))

	return errors


func _base_location(source_data: Dictionary) -> Dictionary:
	return {
		"id": str(source_data.get("id", "")),
		"display_name": str(source_data.get("display_name", "Generated Village")),
		"size": { "width": _width, "height": _height },
		"tile_size": int(source_data.get("tile_size", DEFAULT_TILE_SIZE)),
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
		"town_zones": [],
		"parcels": [],
		"building_requests": [],
		"buildings": [],
		"building_prefab_catalog": _building_prefab_catalog_path,
		"building_prefabs": _building_prefabs.duplicate(true),
		"interiors": [],
		"transitions": [],
		"state": {
			"danger_level": 0,
			"owner_faction": "field_neutral",
			"generation": "agent_settlement_blueprint",
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
	_compiler_recovery_log.clear()
	_parcels.clear()
	_building_instances.clear()
	_interior_manifests.clear()
	_town_character_rows.clear()
	_building_adaptation_failures.clear()
	_building_prefabs.clear()
	for y in range(_height):
		var row: Array = []
		for _x in range(_width):
			row.append("g")
		_tiles.append(row)


func _layout_uses_legacy_road_first(generator_data: Dictionary) -> bool:
	return str(generator_data.get("layout_planner", "agent_settlement_planner")) == "legacy_road_first"


func _run_agent_blueprint_planner(source_data: Dictionary, generator_data: Dictionary) -> Dictionary:
	var planner: RefCounted = AgentSettlementPlannerScript.new()
	return planner.plan({
		"source_location_id": str(source_data.get("id", "")),
		"seed": int(generator_data.get("seed", 5601)),
		"width": _width,
		"height": _height,
		"planning_steps": int(generator_data.get("planning_steps", 72)),
		"building_requests": _building_requests(),
	})


func _road_plan_from_agent_blueprint(blueprint: Dictionary) -> Dictionary:
	return {
		"main_path": [],
		"branch_paths": [],
		"road_cells": (blueprint.get("road_cells", []) as Array).duplicate(),
		"plaza": (blueprint.get("plaza", {}) as Dictionary).duplicate(true),
		"farm": (blueprint.get("farm", {}) as Dictionary).duplicate(true),
		"training": (blueprint.get("training", {}) as Dictionary).duplicate(true),
		"wild_gate": (blueprint.get("wild_gate", {}) as Dictionary).duplicate(true),
	}


func _compile_agent_blueprint_plan(blueprint: Dictionary) -> Dictionary:
	var plaza_rect: Dictionary = blueprint.get("plaza", {}) as Dictionary
	var farm_rect: Dictionary = blueprint.get("farm", {}) as Dictionary
	var training_rect: Dictionary = blueprint.get("training", {}) as Dictionary
	var wild_gate_rect: Dictionary = blueprint.get("wild_gate", {}) as Dictionary
	var buildings: Array[Dictionary] = []
	var building_requests: Array[Dictionary] = []
	var parcel_index := 0
	for request_value in (blueprint.get("building_requests", []) as Array):
		var planned_request: Dictionary = request_value as Dictionary
		var spec: Dictionary = planned_request.get("request", {}) as Dictionary
		var lot: Dictionary = planned_request.get("lot", {}) as Dictionary
		if spec.is_empty() or lot.is_empty():
			continue
		parcel_index += 1
		var parcel := _parcel_from_frontage_lot(lot, spec, "parcel_%03d" % parcel_index)
		var placement := _choose_prefab_placement(parcel, spec)
		if placement.is_empty():
			_add_placement_log(str(spec.get("id", "")), lot, "skipped: agent parcel did not fit any prefab placement")
			_record_building_adaptation_failure(spec, lot, "no south-door building core fits parcel cell set")
			continue
		var prefab: Dictionary = placement.get("prefab", {}) as Dictionary
		buildings.append({
			"spec": spec.duplicate(true),
			"lot": lot.duplicate(true),
			"parcel": parcel,
			"prefab": prefab,
			"placement": placement,
		})
		building_requests.append({
			"id": str(spec.get("id", "")),
			"role": str(spec.get("role", "")),
			"zone_type": str(spec.get("zone_type", "")),
			"parcel_id": str(parcel.get("id", "")),
			"semantic_zone_id": str(parcel.get("semantic_zone_id", "")),
			"prefab_id": str(prefab.get("id", "")),
			"source": "agent_building_role",
		})

	_generated["building_requests"] = building_requests
	_generated["town_zones"] = _town_zone_rows_from_road_plan(
		plaza_rect,
		farm_rect,
		training_rect,
		wild_gate_rect,
		buildings,
		"agent_blueprint_assignment"
	)
	return {
		"plaza": plaza_rect,
		"wild_gate": wild_gate_rect,
		"farm": farm_rect,
		"training": training_rect,
		"buildings": buildings,
		"frontage_candidates": (blueprint.get("frontage_candidates", []) as Array).duplicate(true),
		"decoration_slots": (blueprint.get("decoration_slots", []) as Array).duplicate(true),
	}


func _build_road_plan() -> Dictionary:
	var road_cells: Array[Vector2i] = []
	var main_path := _build_main_road_path()
	_append_path_cells(road_cells, main_path)

	var plaza_x := clampi(int(float(_width) * 0.52) + _rng.randi_range(-2, 2), 10, _width - 10)
	var plaza_road_y := _path_y_at_x(main_path, plaza_x)
	var plaza_rect := _clamped_rect({
		"x": plaza_x - 4,
		"y": plaza_road_y - 2,
		"w": 8,
		"h": 5,
	})

	var branch_paths: Array[Array] = []
	var north_branch := _build_branch_path(main_path, plaza_x - 7, 7 + _rng.randi_range(-1, 1), -8)
	var south_branch := _build_branch_path(main_path, plaza_x + 5, _height - 4, 9)
	branch_paths.append(north_branch)
	branch_paths.append(south_branch)
	for branch_value in branch_paths:
		_append_path_cells(road_cells, branch_value as Array)

	var farm_rect := _clamped_rect({
		"x": _width - 10,
		"y": 2,
		"w": 8,
		"h": 7,
	})
	var training_rect := _clamped_rect({
		"x": 2,
		"y": clampi(plaza_road_y - 5, 2, _height - 8),
		"w": 7,
		"h": 5,
	})
	var gate_rect := _clamped_rect({
		"x": _width - 6,
		"y": clampi(_path_y_at_x(main_path, _width - 2) - 1, 1, _height - 4),
		"w": 5,
		"h": 3,
	})

	return {
		"main_path": main_path,
		"branch_paths": branch_paths,
		"road_cells": road_cells,
		"plaza": plaza_rect,
		"farm": farm_rect,
		"training": training_rect,
		"wild_gate": gate_rect,
	}


func _build_main_road_path() -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var y := clampi(int(float(_height) * 0.60) + _rng.randi_range(-1, 1), 9, _height - 6)
	for x in range(1, _width - 1):
		if x > 3 and x < _width - 4 and x % 6 == 0:
			y = clampi(y + _rng.randi_range(-1, 1), 8, _height - 5)
		path.append(Vector2i(x, y))
	return path


func _build_branch_path(main_path: Array[Vector2i], start_x: int, target_y: int, horizontal_length: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var start := Vector2i(clampi(start_x, 2, _width - 3), _path_y_at_x(main_path, start_x))
	var cursor := start
	while cursor.y != target_y:
		cursor.y += 1 if target_y > cursor.y else -1
		path.append(cursor)

	var step := 1 if horizontal_length >= 0 else -1
	for _i in range(absi(horizontal_length)):
		cursor.x = clampi(cursor.x + step, 2, _width - 3)
		path.append(cursor)
	return path


func _append_path_cells(road_cells: Array[Vector2i], path: Array) -> void:
	for cell_value in path:
		var cell: Vector2i = cell_value as Vector2i
		if not road_cells.has(cell):
			road_cells.append(cell)


func _path_y_at_x(path: Array[Vector2i], x: int) -> int:
	var best_y := int(float(_height) * 0.60)
	var best_dx := 99999
	for cell in path:
		var dx := absi(cell.x - x)
		if dx < best_dx:
			best_dx = dx
			best_y = cell.y
	return best_y


func _apply_road_skeleton(road_plan: Dictionary) -> void:
	for cell_value in (road_plan.get("road_cells", []) as Array):
		_set_path_tile(cell_value as Vector2i)
	_add_placement_log("road_skeleton", {
		"road_cell_count": (road_plan.get("road_cells", []) as Array).size(),
	}, "road-first skeleton is generated before zones, parcels, buildings, and anchors")


func _apply_planner_roads(road_plan: Dictionary) -> void:
	for cell_value in (road_plan.get("road_cells", []) as Array):
		_set_path_tile(cell_value as Vector2i)
	_add_placement_log("planner_road_commits", {
		"road_cell_count": (road_plan.get("road_cells", []) as Array).size(),
	}, "agent-committed road cells materialized without compiler path recovery")


func _assign_town_plan(road_plan: Dictionary) -> Dictionary:
	var plaza_rect: Dictionary = road_plan.get("plaza", {}) as Dictionary
	var farm_rect: Dictionary = road_plan.get("farm", {}) as Dictionary
	var training_rect: Dictionary = road_plan.get("training", {}) as Dictionary
	var wild_gate_rect: Dictionary = road_plan.get("wild_gate", {}) as Dictionary
	var special_rects: Array[Dictionary] = [
		plaza_rect.duplicate(true),
		farm_rect.duplicate(true),
		training_rect.duplicate(true),
		wild_gate_rect.duplicate(true),
	]
	var frontage_candidates := _collect_frontage_lots(road_plan.get("road_cells", []) as Array, special_rects)
	_add_placement_log("frontage_scan", {
		"candidate_count": frontage_candidates.size(),
	}, "lots are scanned from cells north of existing roads, so ordinary south-facing doors can connect back to the road network")

	var available := frontage_candidates.duplicate(true)
	var buildings: Array[Dictionary] = []
	var used_lots: Array[Dictionary] = []
	var parcel_index := 0
	for spec_value in _building_requests():
		var spec: Dictionary = spec_value as Dictionary
		var lot := _take_frontage_building_lot(available, spec, plaza_rect, farm_rect, wild_gate_rect, buildings, used_lots)
		if lot.is_empty():
			_add_placement_log(str(spec.get("id", "")), {}, "skipped: no road-facing lot fits a south-door prefab contract")
			continue
		lot["semantic_zone_id"] = _semantic_zone_for_request(spec)
		used_lots.append(lot.duplicate(true))
		parcel_index += 1
		var parcel := _parcel_from_frontage_lot(lot, spec, "parcel_%03d" % parcel_index)
		var placement := _choose_prefab_placement(parcel, spec)
		var prefab: Dictionary = placement.get("prefab", {}) as Dictionary
		buildings.append({
			"spec": spec.duplicate(true),
			"lot": lot.duplicate(true),
			"parcel": parcel,
			"prefab": prefab,
			"placement": placement,
		})

	_generated["town_zones"] = _town_zone_rows_from_road_plan(plaza_rect, farm_rect, training_rect, wild_gate_rect, buildings)
	return {
		"plaza": plaza_rect,
		"wild_gate": wild_gate_rect,
		"farm": farm_rect,
		"training": training_rect,
		"buildings": buildings,
		"frontage_candidates": frontage_candidates,
	}


func _semantic_zone_for_request(request: Dictionary) -> String:
	match str(request.get("id", "")):
		"shop", "workshop":
			return "market"
		"tavern":
			return "tavern"
		"farmer_cottage":
			return "farm_service"
		"storage_shed":
			return "farm_storage"
		"guardhouse":
			return "gate_service"
		_:
			return "residential"


func _town_zone_rows_from_road_plan(
	plaza_rect: Dictionary,
	farm_rect: Dictionary,
	training_rect: Dictionary,
	wild_gate_rect: Dictionary,
	buildings: Array[Dictionary],
	source: String = "road_frontage_assignment"
) -> Array[Dictionary]:
	var bounds_by_zone: Dictionary = {
		"plaza": plaza_rect.duplicate(true),
		"farm": farm_rect.duplicate(true),
		"training": training_rect.duplicate(true),
		"gate": wild_gate_rect.duplicate(true),
	}
	var type_by_zone: Dictionary = {
		"plaza": "civic_core",
		"farm": "farm_block",
		"training": "training_yard",
		"gate": "east_gate",
		"residential": "residential_cluster",
		"market": "market_frontage",
		"tavern": "social_frontage",
		"farm_service": "farm_service_lot",
		"farm_storage": "farm_storage_lot",
		"gate_service": "gate_service_lot",
	}
	for building_value in buildings:
		var building: Dictionary = building_value as Dictionary
		var lot: Dictionary = building.get("lot", {}) as Dictionary
		var zone_id := str(lot.get("semantic_zone_id", ""))
		if zone_id.is_empty():
			continue
		if bounds_by_zone.has(zone_id):
			bounds_by_zone[zone_id] = _union_rect(bounds_by_zone.get(zone_id, {}) as Dictionary, lot)
		else:
			bounds_by_zone[zone_id] = lot.duplicate(true)

	var rows: Array[Dictionary] = []
	for zone_id in bounds_by_zone.keys():
		rows.append({
			"id": str(zone_id),
			"type": str(type_by_zone.get(str(zone_id), "road_frontage_zone")),
			"bounds": (bounds_by_zone.get(zone_id, {}) as Dictionary).duplicate(true),
			"source": source,
		})
	return rows


func _building_requests() -> Array[Dictionary]:
	return [
		{
			"id": "residential",
			"zone_type": "residential",
			"display_name": "Residence",
			"role": "home",
			"preference": "quiet",
			"allowed_archetypes": ["residential"],
			"yard_policy": "small_residential_yard",
		},
		{
			"id": "workshop",
			"zone_type": "workshop",
			"display_name": "Workshop",
			"role": "production",
			"preference": "road",
			"allowed_archetypes": ["workshop"],
			"yard_policy": "workshop_service_yard",
		},
		{
			"id": "shop",
			"zone_type": "shop",
			"display_name": "Shop",
			"role": "commerce",
			"preference": "plaza",
			"allowed_archetypes": ["shop"],
			"yard_policy": "clear_frontage",
		},
		{
			"id": "tavern",
			"zone_type": "tavern",
			"display_name": "Tavern",
			"role": "social",
			"preference": "plaza",
			"allowed_archetypes": ["tavern"],
			"yard_policy": "clear_frontage",
		},
		{
			"id": "farmer_cottage",
			"zone_type": "residential",
			"display_name": "Farmer Cottage",
			"role": "home",
			"preference": "farm",
			"allowed_archetypes": ["farmer_cottage", "residential"],
			"yard_policy": "farmyard",
		},
		{
			"id": "worker_cottage",
			"zone_type": "residential",
			"display_name": "Worker Cottage",
			"role": "home",
			"preference": "quiet",
			"allowed_archetypes": ["worker_cottage", "residential"],
			"yard_policy": "small_residential_yard",
		},
		{
			"id": "storage_shed",
			"zone_type": "storage",
			"display_name": "Storage Shed",
			"role": "storage",
			"preference": "farm",
			"allowed_archetypes": ["storage_shed"],
			"yard_policy": "farmyard",
		},
		{
			"id": "guardhouse",
			"zone_type": "guard",
			"display_name": "Guardhouse",
			"role": "guard",
			"preference": "gate",
			"allowed_archetypes": ["guardhouse"],
			"yard_policy": "clear_frontage",
		},
	]


func _collect_frontage_lots(road_cells: Array, reserved_rects: Array[Dictionary]) -> Array[Dictionary]:
	var lots: Array[Dictionary] = []
	var seen: Dictionary = {}
	var index := 0
	for road_value in road_cells:
		var road_cell: Vector2i = road_value as Vector2i
		if road_cell.y < 7:
			continue
		if road_cell.x < 3 or road_cell.x > _width - 4:
			continue
		var lot := _frontage_lot_for_road_cell(road_cell, index + 1)
		if lot.is_empty():
			continue
		if _lot_overlaps_any_reserved_rect(lot, reserved_rects):
			continue
		var key := "%d,%d,%d,%d" % [
			int(lot.get("x", 0)),
			int(lot.get("y", 0)),
			int(lot.get("w", 0)),
			int(lot.get("h", 0)),
		]
		if seen.has(key):
			continue
		seen[key] = true
		index += 1
		lot["lot_id"] = "frontage_%03d" % index
		lots.append(lot)
	return lots


func _frontage_lot_for_road_cell(road_cell: Vector2i, index: int) -> Dictionary:
	var lot_w := 7
	var lot_h := 6
	var bounds := {
		"x": road_cell.x - int(lot_w / 2),
		"y": road_cell.y - lot_h,
		"w": lot_w,
		"h": lot_h,
	}
	bounds = _clamped_rect(bounds)
	if int(bounds.get("h", 0)) < 5:
		return {}
	if int(bounds.get("y", 0)) + int(bounds.get("h", 0)) > road_cell.y:
		return {}
	return {
		"lot_id": "frontage_%03d" % index,
		"x": int(bounds.get("x", 0)),
		"y": int(bounds.get("y", 0)),
		"w": int(bounds.get("w", 0)),
		"h": int(bounds.get("h", 0)),
		"frontage_cell": _dict_cell(road_cell),
		"frontage_side": "south",
		"semantic_zone_id": "",
	}


func _take_frontage_building_lot(
	available: Array,
	spec: Dictionary,
	plaza_rect: Dictionary,
	farm_rect: Dictionary,
	wild_gate_rect: Dictionary,
	placed_buildings: Array[Dictionary],
	used_lots: Array[Dictionary]
) -> Dictionary:
	var best_index := -1
	var best_score := -INF
	var best_reason := ""
	for index in range(available.size()):
		var lot: Dictionary = available[index] as Dictionary
		if _lot_overlaps_any_reserved_rect(lot, used_lots):
			continue
		var score_data := _score_frontage_lot(lot, spec, plaza_rect, farm_rect, wild_gate_rect, placed_buildings)
		var score := float(score_data.get("score", -INF))
		if score > best_score:
			best_score = score
			best_index = index
			best_reason = str(score_data.get("reason", ""))
	if best_index < 0 or is_equal_approx(best_score, -INF):
		return {}

	var selected: Dictionary = available.pop_at(best_index) as Dictionary
	_add_placement_log(str(spec.get("id", "")), selected, "score %.2f: %s" % [best_score, best_reason])
	return selected


func _score_frontage_lot(
	lot: Dictionary,
	spec: Dictionary,
	plaza_rect: Dictionary,
	farm_rect: Dictionary,
	wild_gate_rect: Dictionary,
	placed_buildings: Array[Dictionary]
) -> Dictionary:
	var center := _rect_center(lot)
	var plaza_center: Vector2 = _rect_center(plaza_rect)
	var farm_center: Vector2 = _rect_center(farm_rect)
	var gate_center: Vector2 = _rect_center(wild_gate_rect)
	var parcel := _parcel_from_frontage_lot(lot, spec, "score_probe")
	var placement := _choose_prefab_placement(parcel, spec)
	if placement.is_empty():
		return {
			"score": -INF,
			"reason": "rejected: no prefab fits this road-facing lot",
		}
	var area := float(int(lot.get("w", 0)) * int(lot.get("h", 0)))
	var score := area * 0.04
	var prefab: Dictionary = placement.get("prefab", {}) as Dictionary
	var reason_parts: Array[String] = [
		"frontage lot fits %.0f cells" % area,
		"prefab %s snaps south door toward road" % str(prefab.get("id", "")),
	]
	var preference: String = str(spec.get("preference", ""))
	var plaza_distance: float = center.distance_to(plaza_center)
	match preference:
		"plaza":
			score += max(0.0, 36.0 - plaza_distance * 2.4)
			reason_parts.append("prefers frontage near civic road")
		"road":
			score += max(0.0, 24.0 - plaza_distance)
			reason_parts.append("prefers a visible work street")
		"farm":
			score += max(0.0, 34.0 - center.distance_to(farm_center) * 1.7)
			reason_parts.append("prefers road frontage near farm")
		"gate":
			score += max(0.0, 38.0 - center.distance_to(gate_center) * 2.0)
			reason_parts.append("prefers gate road frontage")
		"quiet":
			score += min(18.0, plaza_distance * 0.7)
			if center.y > float(_height) * 0.62:
				score += 10.0
				reason_parts.append("prefers lower residential lane")
			else:
				reason_parts.append("prefers quieter branch frontage")

	if str(spec.get("role", "")) == "home":
		score += _residential_cluster_score(center, placed_buildings)
		reason_parts.append("clusters with homes")

	return {
		"score": score,
		"reason": ", ".join(reason_parts),
	}


func _parcel_from_frontage_lot(lot: Dictionary, request: Dictionary, parcel_id: String) -> Dictionary:
	var bounds := {
		"x": int(lot.get("x", 0)),
		"y": int(lot.get("y", 0)),
		"w": int(lot.get("w", 0)),
		"h": int(lot.get("h", 0)),
	}
	var margin := 1
	var buildable_area := {
		"x": int(bounds.get("x", 0)) + margin,
		"y": int(bounds.get("y", 0)),
		"w": max(1, int(bounds.get("w", 0)) - margin * 2),
		"h": max(1, int(bounds.get("h", 0))),
	}
	var parcel_cells: Array[Dictionary] = (lot.get("cells", []) as Array).duplicate(true)
	if parcel_cells.is_empty():
		if _uses_legacy_layout:
			parcel_cells = _rect_cell_dicts(bounds)
	var buildable_cells := _cells_inside_rect(parcel_cells, buildable_area)
	return {
		"id": parcel_id,
		"district_id": str(lot.get("semantic_zone_id", request.get("preference", "village"))),
		"semantic_zone_id": str(lot.get("semantic_zone_id", "")),
		"bounds": bounds,
		"shape_model": str(lot.get("shape_model", "rectangular_legacy_lot" if _uses_legacy_layout else "cell_set_missing_lot")),
		"growth_model": str(lot.get("growth_model", "legacy_rectangular_frontage" if _uses_legacy_layout else "")),
		"cells": parcel_cells,
		"cell_count": parcel_cells.size(),
		"organic_target_cell_count": int(lot.get("organic_target_cell_count", parcel_cells.size())),
		"buildable_area": buildable_area,
		"buildable_cells": buildable_cells,
		"frontage_cell": (lot.get("frontage_cell", {}) as Dictionary).duplicate(true),
		"access_cell": (lot.get("access_cell", lot.get("frontage_cell", {})) as Dictionary).duplicate(true),
		"access_side": str(lot.get("access_side", lot.get("frontage_side", "south"))),
		"frontage_side": str(lot.get("frontage_side", lot.get("access_side", "south"))),
		"door_side": "south",
		"allowed_archetypes": (request.get("allowed_archetypes", []) as Array).duplicate(),
		"yard_policy": str(request.get("yard_policy", "clear_frontage")),
		"required_clearance": 1,
		"road_anchor": {},
		"door_slot": {},
		"yard_bounds": {},
	}


func _choose_prefab_placement(parcel: Dictionary, request: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for prefab_value in _building_prefabs:
		var prefab: Dictionary = prefab_value as Dictionary
		var placement := _placement_for_prefab(parcel, request, prefab)
		if placement.is_empty():
			continue
		var score := _score_prefab_placement(parcel, request, prefab, placement)
		if score > best_score:
			best_score = score
			best = placement
			best["score"] = score
	return best


func _placement_for_prefab(parcel: Dictionary, request: Dictionary, prefab: Dictionary) -> Dictionary:
	if not _prefab_matches_request(prefab, request):
		return {}
	if str(prefab.get("door_side", "south")) != "south":
		return {}

	var yard_policy: String = str(parcel.get("yard_policy", "clear_frontage"))
	if not _string_array_has(prefab.get("allowed_yard_policies", []) as Array, yard_policy):
		return {}

	var buildable: Dictionary = parcel.get("buildable_area", {}) as Dictionary
	var footprint: Dictionary = prefab.get("footprint_size", {}) as Dictionary
	var w: int = int(footprint.get("w", 0))
	var h: int = int(footprint.get("h", 0))
	var clearance: int = maxi(1, int(prefab.get("required_front_clearance", 1)))
	if w <= 0 or h <= 0:
		return {}
	if w > int(buildable.get("w", 0)) or h + clearance > int(buildable.get("h", 0)):
		return {}

	var entry_cell := _cell_from_dict(parcel.get("access_cell", parcel.get("frontage_cell", {})) as Dictionary)
	var parcel_cell_keys := _parcel_cell_key_set(parcel, _uses_legacy_layout)
	if parcel_cell_keys.is_empty() or not parcel_cell_keys.has(_cell_key(entry_cell)):
		return {}
	var best: Dictionary = {}
	var best_score := -INF
	var min_x: int = int(buildable.get("x", 0))
	var max_x: int = int(buildable.get("x", 0)) + int(buildable.get("w", 0)) - w
	var min_y: int = int(buildable.get("y", 0))
	var max_y: int = int(buildable.get("y", 0)) + int(buildable.get("h", 0)) - h - clearance
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var rect: Dictionary = { "x": x, "y": y, "w": w, "h": h }
			if not _rect_inside_cell_set(rect, parcel_cell_keys):
				continue
			if _cell_in_rect(entry_cell, rect):
				continue
			var door_info: Dictionary = _south_door_for_prefab(rect, prefab)
			if not _building_frontage_is_valid(door_info):
				continue
			var door: Vector2i = door_info.get("door", Vector2i.ZERO) as Vector2i
			var step: Vector2i = door_info.get("step", Vector2i.ZERO) as Vector2i
			if not parcel_cell_keys.has(_cell_key(step)):
				continue
			var yard_path := _yard_path_between(entry_cell, step, parcel, rect)
			if yard_path.is_empty():
				continue
			var yard_cells := _adaptive_yard_cells(parcel, rect, yard_path)
			var score := 20.0 - float(yard_path.size()) * 0.8
			score += minf(6.0, float(yard_cells.size()) * 0.35)
			score -= absf(float(x) - (float(min_x + max_x) * 0.5)) * 0.25
			score -= absf(float(y) - (float(min_y + max_y) * 0.5)) * 0.18
			if score <= best_score:
				continue
			best_score = score
			best = {
				"prefab": prefab.duplicate(true),
				"building_bounds": rect,
				"door": _dict_cell(door),
				"doorstep": _dict_cell(step),
				"door_facing": "down",
				"front_clearance": clearance,
				"yard_policy": yard_policy,
				"yard_bounds": { "x": x, "y": y + h, "w": w, "h": clearance },
				"yard_cells": _dict_path(yard_cells),
				"parcel_entry": _dict_cell(entry_cell),
				"yard_path": _dict_path(yard_path),
				"core_placement": {
					"model": "south_door_core_fitted_to_parcel_cells",
					"door_policy": "south_only",
					"source": "building_core_search",
				},
			}
	return best


func _score_prefab_placement(parcel: Dictionary, request: Dictionary, prefab: Dictionary, placement: Dictionary) -> float:
	var buildable: Dictionary = parcel.get("buildable_area", {}) as Dictionary
	var footprint: Dictionary = prefab.get("footprint_size", {}) as Dictionary
	var unused_w := float(int(buildable.get("w", 0)) - int(footprint.get("w", 0)))
	var unused_h := float(int(buildable.get("h", 0)) - int(footprint.get("h", 0)) - int(placement.get("front_clearance", 1)))
	var score := 20.0 - absf(unused_w) * 0.7 - absf(unused_h) * 0.45
	if str(prefab.get("role", "")) == str(request.get("role", "")):
		score += 6.0
	if _string_array_has(prefab.get("archetype_tags", []) as Array, str(request.get("id", ""))):
		score += 4.0
	return score


func _prefab_matches_request(prefab: Dictionary, request: Dictionary) -> bool:
	var tags: Array = prefab.get("archetype_tags", []) as Array
	for archetype_value in (request.get("allowed_archetypes", []) as Array):
		if _string_array_has(tags, str(archetype_value)):
			return true
	return false


func _string_array_has(values: Array, target: String) -> bool:
	for value in values:
		if str(value) == target:
			return true
	return false


func _clamped_rect(rect: Dictionary) -> Dictionary:
	var x := clampi(int(rect.get("x", 0)), 1, _width - 2)
	var y := clampi(int(rect.get("y", 0)), 1, _height - 2)
	var w: int = min(int(rect.get("w", 1)), _width - 1 - x)
	var h: int = min(int(rect.get("h", 1)), _height - 1 - y)
	return {
		"x": x,
		"y": y,
		"w": max(1, w),
		"h": max(1, h),
	}


func _inner_rect(rect: Dictionary, desired_w: int, desired_h: int) -> Dictionary:
	var margin := 1
	var w: int = min(desired_w, max(3, int(rect.get("w", 0)) - margin * 2))
	var h: int = min(desired_h, max(3, int(rect.get("h", 0)) - margin * 2))
	var x: int = int(rect.get("x", 0)) + margin + max(0, (int(rect.get("w", 0)) - margin * 2 - w) / 2)
	var y: int = int(rect.get("y", 0)) + margin + max(0, (int(rect.get("h", 0)) - margin * 2 - h) / 2)
	return { "x": x, "y": y, "w": w, "h": h }


func _apply_plaza(rect: Dictionary) -> void:
	if rect.is_empty():
		return
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
		"inspect_text": "This generated village is assembled from a road-first skeleton, semantic anchors, and validated placement slots.",
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


func _apply_building_spec(spec: Dictionary, lot: Dictionary, instance_number: int, parcel: Dictionary, prefab: Dictionary, placement: Dictionary) -> void:
	var archetype_id: String = str(spec.get("id", "building"))
	var instance_id := "b%03d" % instance_number
	var exterior_location_id := str(_generated.get("id", ""))
	var interior_location_id := "%s__interior_%s" % [exterior_location_id, instance_id]
	var display_name := str(prefab.get("display_name", spec.get("display_name", "Building")))
	var rect: Dictionary = placement.get("building_bounds", {}) as Dictionary
	if rect.is_empty():
		rect = _inner_rect(lot, 4, 3)
	var door: Vector2i = _cell_from_dict(placement.get("door", {}) as Dictionary)
	var door_step: Vector2i = _cell_from_dict(placement.get("doorstep", {}) as Dictionary)
	var parcel_entry: Vector2i = _cell_from_dict(placement.get("parcel_entry", parcel.get("access_cell", {}) as Dictionary))
	var door_facing: String = str(placement.get("door_facing", "down"))
	var return_entrance_id := "%s.return" % instance_id
	var exterior_return_spawn_id := "%s.outside" % instance_id
	var interior_slots := _interior_slots_for_archetype(archetype_id)
	var interior_entry_entrance_id := str(interior_slots.get("entry", "entry"))
	var interior_entry_spawn_id := "%s.entry" % instance_id
	var interior_exit_anchor_id := str(interior_slots.get("exit", "exit"))
	var exterior_door_anchor_id := "%s.exterior_door" % instance_id
	var parcel_id := str(parcel.get("id", "parcel_%03d" % instance_number))
	var yard_policy := str(placement.get("yard_policy", parcel.get("yard_policy", "clear_frontage")))
	var prefab_visual: Dictionary = prefab.get("visual", {}) as Dictionary

	_mark_rect_road_blocker(rect)
	_road_blockers.erase(_cell_key(door_step))
	parcel["id"] = parcel_id
	parcel["building_instance_id"] = instance_id
	parcel["building_prefab_id"] = str(prefab.get("id", ""))
	parcel["building_footprint"] = rect.duplicate(true)
	parcel["door_slot"] = _dict_cell(door)
	parcel["road_anchor"] = _dict_cell(parcel_entry if parcel_entry != Vector2i(-1, -1) else door_step)
	parcel["yard_bounds"] = (placement.get("yard_bounds", {}) as Dictionary).duplicate(true)
	parcel["yard_cells"] = (placement.get("yard_cells", []) as Array).duplicate(true)
	parcel["core_placement"] = (placement.get("core_placement", {}) as Dictionary).duplicate(true)
	_parcels.append(parcel.duplicate(true))
	(_generated.get("parcels", []) as Array).append(parcel.duplicate(true))
	_add_parcel_surface_overlays(parcel, placement)
	_add_zone("%s.zone" % instance_id, str(prefab.get("zone_type", spec.get("zone_type", archetype_id))), display_name, rect)
	_add_structure("building_prefab_placeholder", Vector2i.ZERO, {
		"bounds": rect.duplicate(true),
		"presentation_layer": "game",
		"blocks_movement": false,
		"blocks_sight": false,
		"prefab_id": str(prefab.get("id", "")),
		"archetype_id": archetype_id,
		"zone_type": str(prefab.get("zone_type", spec.get("zone_type", archetype_id))),
		"role": str(prefab.get("role", spec.get("role", ""))),
		"door": _dict_cell(door),
		"door_side": "south",
		"visual": prefab_visual.duplicate(true),
	})
	_add_structure("wall_ring", Vector2i.ZERO, {
		"bounds": rect.duplicate(true),
		"exclude_cells": [_dict_cell(door)],
		"presentation_layer": "game",
		"blocks_movement": true,
		"blocks_sight": true,
		"prefab_id": str(prefab.get("id", "")),
		"archetype_id": archetype_id,
		"zone_type": str(prefab.get("zone_type", spec.get("zone_type", archetype_id))),
		"visual": prefab_visual.duplicate(true),
	})
	_add_structure("door", door, { "presentation_layer": "game" })
	_add_roof("%s.roof" % instance_id, _roof_palette_for_prefab(prefab), _roof_bounds_for_prefab(rect), rect, str(prefab.get("id", "")), archetype_id)
	_connector_cells[instance_id] = door_step
	_apply_yard_path(placement.get("yard_path", []) as Array)
	var adaptive_yard_slots := _apply_adaptive_yard(parcel, placement, rect, door, door_step, instance_id, yard_policy)
	_set_path_tile(door_step)
	_reserve_cell(door_step)
	_add_entrance(return_entrance_id, door_step, door_facing)
	_add_anchor(exterior_door_anchor_id, "building_door", door_step, _opposite_facing(door_facing))

	var building_instance := {
		"id": instance_id,
		"archetype_id": archetype_id,
		"prefab_id": str(prefab.get("id", "")),
		"parcel_id": parcel_id,
		"display_name": display_name,
		"role": str(prefab.get("role", spec.get("role", ""))),
		"zone_type": str(prefab.get("zone_type", spec.get("zone_type", archetype_id))),
		"exterior_location_id": exterior_location_id,
		"interior_location_id": interior_location_id,
		"bounds": rect.duplicate(true),
		"door": _dict_cell(door),
		"doorstep": _dict_cell(door_step),
		"parcel_entry": _dict_cell(parcel_entry),
		"yard_path": (placement.get("yard_path", []) as Array).duplicate(true),
		"door_facing": door_facing,
		"door_side": "south",
		"front_clearance": int(placement.get("front_clearance", 1)),
		"yard_policy": yard_policy,
		"yard_bounds": (placement.get("yard_bounds", {}) as Dictionary).duplicate(true),
		"yard_cells": (placement.get("yard_cells", []) as Array).duplicate(true),
		"core_placement": (placement.get("core_placement", {}) as Dictionary).duplicate(true),
		"adaptive_yard_slots": adaptive_yard_slots,
		"visual": prefab_visual.duplicate(true),
		"prefab_contract": prefab.duplicate(true),
		"exterior_door_anchor_id": exterior_door_anchor_id,
		"return_entrance_id": return_entrance_id,
		"exterior_return_spawn_id": exterior_return_spawn_id,
		"interior_entry_entrance_id": interior_entry_entrance_id,
		"interior_entry_spawn_id": interior_entry_spawn_id,
		"interior_exit_anchor_id": interior_exit_anchor_id,
		"world_enter_exit_id": "%s.enter" % interior_location_id,
		"world_leave_exit_id": "%s.leave" % interior_location_id,
		"interior_slots": interior_slots,
	}
	building_instance["materialized_exterior_slots"] = _materialize_prefab_exterior_slots(building_instance, prefab, rect, door, door_step)
	_building_instances.append(building_instance)
	(_generated.get("buildings", []) as Array).append(building_instance.duplicate(true))

	var interior_context := {
		"location_id": interior_location_id,
		"exterior_location_id": exterior_location_id,
		"building_instance": building_instance.duplicate(true),
		"archetype_id": archetype_id,
		"display_name": display_name,
		"characters": [],
		"entry_entrance_id": interior_entry_entrance_id,
		"entry_spawn_id": interior_entry_spawn_id,
		"entry_facing": "up",
		"exit_anchor_id": interior_exit_anchor_id,
		"return_entrance_id": return_entrance_id,
		"return_spawn_id": exterior_return_spawn_id,
		"world_leave_exit_id": str(building_instance.get("world_leave_exit_id", "")),
	}
	var interior_manifest := {
		"location_id": interior_location_id,
		"building_instance_id": instance_id,
		"source_scene_path": "res://scenes/locations/generated_building_interior.tscn",
		"entry_entrance_id": interior_entry_entrance_id,
		"entry_spawn_id": interior_entry_spawn_id,
		"entry_facing": "up",
		"exit_anchor_id": interior_exit_anchor_id,
		"return_entrance_id": return_entrance_id,
		"return_spawn_id": exterior_return_spawn_id,
		"return_facing": door_facing,
		"generation_context": interior_context,
	}
	_interior_manifests.append(interior_manifest)
	(_generated.get("interiors", []) as Array).append(interior_manifest.duplicate(true))
	_add_transition_edge(exterior_location_id, exterior_door_anchor_id, interior_location_id, interior_entry_entrance_id, instance_id, {
		"target_spawn_id": interior_entry_spawn_id,
	})
	_add_transition_edge(interior_location_id, interior_exit_anchor_id, exterior_location_id, return_entrance_id, instance_id, {
		"target_spawn_id": exterior_return_spawn_id,
	})
	_add_building_door_object(building_instance, door)


func _add_building_door_object(building_instance: Dictionary, door: Vector2i) -> void:
	var instance_id := str(building_instance.get("id", "building"))
	var display_name := str(building_instance.get("display_name", instance_id))
	_add_object({
		"id": "%s.door" % instance_id,
		"display_name": "%s Door" % display_name,
		"grid_position": _dict_cell(door),
		"blocks_movement": true,
		"kind": "door",
		"is_inspectable": true,
		"is_usable": true,
		"facility_type": "scene_transition",
		"target_scene_path": "res://scenes/locations/generated_building_interior.tscn",
		"target_entrance_id": str(building_instance.get("interior_entry_entrance_id", "")),
		"return_entrance_id": str(building_instance.get("return_entrance_id", "")),
		"world_exit_id": str(building_instance.get("world_enter_exit_id", "")),
		"inspect_text": "A generated exterior door. Interact to enter the building interior.",
		"transition_context": {
			"location_id": str(building_instance.get("interior_location_id", "")),
			"exterior_location_id": str(building_instance.get("exterior_location_id", "")),
			"building_instance": building_instance.duplicate(true),
			"archetype_id": str(building_instance.get("archetype_id", "")),
			"display_name": display_name,
			"characters": _town_character_rows.duplicate(true),
			"entry_entrance_id": str(building_instance.get("interior_entry_entrance_id", "")),
			"entry_spawn_id": str(building_instance.get("interior_entry_spawn_id", "")),
			"exit_anchor_id": str(building_instance.get("interior_exit_anchor_id", "")),
			"return_entrance_id": str(building_instance.get("return_entrance_id", "")),
			"return_spawn_id": str(building_instance.get("exterior_return_spawn_id", "")),
			"world_leave_exit_id": str(building_instance.get("world_leave_exit_id", "")),
		},
	})


func _interior_slots_for_archetype(archetype_id: String) -> Dictionary:
	match archetype_id:
		"workshop":
			return { "primary": "workbench", "entry": "entry", "exit": "exit" }
		"shop":
			return { "primary": "counter", "entry": "entry", "exit": "exit" }
		"tavern":
			return { "primary": "table", "entry": "entry", "exit": "exit" }
		"storage_shed":
			return { "primary": "storage", "entry": "entry", "exit": "exit" }
		"guardhouse":
			return { "primary": "guard_post", "entry": "entry", "exit": "exit" }
		_:
			return { "primary": "bed", "entry": "entry", "exit": "exit" }


func _add_transition_edge(
	from_location_id: String,
	from_anchor_id: String,
	to_location_id: String,
	to_anchor_id: String,
	building_instance_id: String,
	extra: Dictionary = {}
) -> void:
	var row := {
		"from_location_id": from_location_id,
		"from_anchor_id": from_anchor_id,
		"to_location_id": to_location_id,
		"to_anchor_id": to_anchor_id,
		"building_instance_id": building_instance_id,
	}
	row.merge(extra, true)
	(_generated.get("transitions", []) as Array).append(row)


func _materialize_prefab_exterior_slots(
	building_instance: Dictionary,
	prefab: Dictionary,
	building_bounds: Dictionary,
	door: Vector2i,
	door_step: Vector2i
) -> Array[Dictionary]:
	var materialized: Array[Dictionary] = []
	var yard_bounds: Dictionary = building_instance.get("yard_bounds", {}) as Dictionary
	for slot_value in (prefab.get("exterior_slots", []) as Array):
		var slot: Dictionary = slot_value as Dictionary
		var resolved: Dictionary = _resolve_prefab_exterior_slot(slot, building_instance, building_bounds, yard_bounds, door, door_step)
		if resolved.is_empty():
			_add_placement_log(str(building_instance.get("id", "")), building_bounds, "skipped invalid exterior slot: %s" % str(slot.get("id", "")))
			continue

		materialized.append(resolved.duplicate(true))
		match str(resolved.get("kind", "")):
			"floor_decoration":
				_add_floor_decoration(str(resolved.get("type", "")), _cell_from_dict(resolved.get("grid_position", {}) as Dictionary), _exterior_slot_draw_data(resolved))
			"structure":
				_add_structure(str(resolved.get("type", "")), _cell_from_dict(resolved.get("grid_position", {}) as Dictionary), _exterior_slot_draw_data(resolved))
			_:
				_add_placement_log(str(building_instance.get("id", "")), building_bounds, "skipped unknown exterior slot kind: %s" % str(resolved.get("id", "")))
	return materialized


func _resolve_prefab_exterior_slot(
	slot: Dictionary,
	building_instance: Dictionary,
	building_bounds: Dictionary,
	yard_bounds: Dictionary,
	door: Vector2i,
	door_step: Vector2i
) -> Dictionary:
	if bool(slot.get("blocks_movement", false)) or bool(slot.get("blocks_sight", false)):
		return {}

	var local_position: Dictionary = slot.get("local_position", {}) as Dictionary
	if local_position.is_empty():
		return {}

	var cell := Vector2i(
		int(building_bounds.get("x", 0)) + int(local_position.get("x", 0)),
		int(building_bounds.get("y", 0)) + int(local_position.get("y", 0))
	)
	if not _in_bounds(cell):
		return {}
	if cell == door or cell == door_step:
		return {}
	if _reserved_cells.has(_cell_key(cell)):
		return {}

	var placement_layer := str(slot.get("placement_layer", "yard"))
	if placement_layer == "yard":
		var yard_cell_keys := _cell_key_set_from_dicts(building_instance.get("yard_cells", []) as Array)
		if not yard_cell_keys.is_empty():
			if not yard_cell_keys.has(_cell_key(cell)):
				return {}
		elif not _cell_in_rect(cell, yard_bounds):
			return {}
	if placement_layer != "facade" and _cell_in_rect(cell, building_bounds):
		return {}

	var resolved: Dictionary = slot.duplicate(true)
	resolved["grid_position"] = _dict_cell(cell)
	resolved["prefab_id"] = str(building_instance.get("prefab_id", ""))
	resolved["building_instance_id"] = str(building_instance.get("id", ""))
	resolved["presentation_layer"] = "game"
	resolved["presentation_source"] = "prefab_exterior_slot"
	resolved["blocks_movement"] = false
	resolved["blocks_sight"] = false
	return resolved


func _exterior_slot_draw_data(slot: Dictionary) -> Dictionary:
	var draw_data: Dictionary = slot.duplicate(true)
	draw_data.erase("kind")
	draw_data.erase("local_position")
	return draw_data


func _add_parcel_surface_overlays(parcel: Dictionary, placement: Dictionary) -> void:
	var bounds: Dictionary = parcel.get("bounds", {}) as Dictionary
	var parcel_cells: Array = parcel.get("cells", []) as Array
	if not parcel_cells.is_empty():
		for cell_value in parcel_cells:
			_add_floor_overlay("parcel_surface", _cell_rect(_cell_from_dict(cell_value as Dictionary)), {
				"parcel_id": str(parcel.get("id", "")),
				"yard_policy": str(parcel.get("yard_policy", "clear_frontage")),
				"zone_type": str(parcel.get("district_id", "")),
				"shape_model": str(parcel.get("shape_model", "")),
				"presentation_layer": "debug",
			})
	elif not bounds.is_empty():
		_add_floor_overlay("parcel_surface", bounds, {
			"parcel_id": str(parcel.get("id", "")),
			"yard_policy": str(parcel.get("yard_policy", "clear_frontage")),
			"zone_type": str(parcel.get("district_id", "")),
			"presentation_layer": "debug",
		})

	var yard_cells: Array = placement.get("yard_cells", []) as Array
	var yard_bounds: Dictionary = placement.get("yard_bounds", {}) as Dictionary
	if not yard_cells.is_empty():
		for cell_value in yard_cells:
			_add_floor_overlay("front_clearance", _cell_rect(_cell_from_dict(cell_value as Dictionary)), {
				"parcel_id": str(parcel.get("id", "")),
				"yard_policy": str(placement.get("yard_policy", parcel.get("yard_policy", "clear_frontage"))),
				"presentation_layer": "debug",
			})
	elif not yard_bounds.is_empty():
		_add_floor_overlay("front_clearance", yard_bounds, {
			"parcel_id": str(parcel.get("id", "")),
			"yard_policy": str(placement.get("yard_policy", parcel.get("yard_policy", "clear_frontage"))),
			"presentation_layer": "debug",
		})

	var yard_path: Array = placement.get("yard_path", []) as Array
	if not yard_path.is_empty():
		for cell_value in yard_path:
			_add_floor_overlay("front_path", _cell_rect(_cell_from_dict(cell_value as Dictionary)), {
				"parcel_id": str(parcel.get("id", "")),
				"yard_policy": str(placement.get("yard_policy", parcel.get("yard_policy", "clear_frontage"))),
				"presentation_layer": "game",
			})
	elif not yard_bounds.is_empty():
		_add_floor_overlay("front_path", yard_bounds, {
			"parcel_id": str(parcel.get("id", "")),
			"yard_policy": str(placement.get("yard_policy", parcel.get("yard_policy", "clear_frontage"))),
			"presentation_layer": "game",
		})

	var footprint: Dictionary = placement.get("building_bounds", {}) as Dictionary
	if not footprint.is_empty():
		_add_floor_overlay("building_foundation", footprint, {
			"parcel_id": str(parcel.get("id", "")),
			"presentation_layer": "game",
		})


func _roof_palette_for_prefab(prefab: Dictionary) -> String:
	var visual: Dictionary = prefab.get("visual", {}) as Dictionary
	return str(visual.get("roof_palette", "brown"))


func _roof_bounds_for_prefab(rect: Dictionary) -> Dictionary:
	return {
		"x": int(rect.get("x", 0)),
		"y": int(rect.get("y", 0)),
		"w": int(rect.get("w", 0)),
		"h": max(1, int(rect.get("h", 0)) - 1),
	}


func _south_door_for_prefab(rect: Dictionary, prefab: Dictionary) -> Dictionary:
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	var door_offset := int(prefab.get("door_offset", int(w / 2)))
	var door := Vector2i(clampi(x0 + door_offset, x0 + 1, x0 + w - 2), y0 + h - 1)
	return { "door": door, "step": door + Vector2i.DOWN, "facing": "down" }


func _building_frontage_is_valid(door_info: Dictionary) -> bool:
	var step: Vector2i = door_info.get("step", Vector2i(-1, -1)) as Vector2i
	if not _in_bounds(step):
		return false
	if _road_blockers.has(_cell_key(step)):
		return false
	return true


func _rect_cell_dicts(rect: Dictionary) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			cells.append(_dict_cell(Vector2i(x, y)))
	return cells


func _cells_inside_rect(cells: Array, rect: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		if _cell_in_rect(cell, rect):
			result.append(_dict_cell(cell))
	return result


func _parcel_cell_key_set(parcel: Dictionary, allow_bounds_fallback: bool = true) -> Dictionary:
	var result: Dictionary = {}
	var cells: Array = parcel.get("cells", []) as Array
	if cells.is_empty():
		if not allow_bounds_fallback:
			return result
		cells = _rect_cell_dicts(parcel.get("bounds", {}) as Dictionary)
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		if cell == Vector2i(-1, -1):
			continue
		result[_cell_key(cell)] = true
	return result


func _rect_inside_cell_set(rect: Dictionary, cell_keys: Dictionary) -> bool:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			if not cell_keys.has(_cell_key(Vector2i(x, y))):
				return false
	return true


func _adaptive_yard_cells(parcel: Dictionary, building_bounds: Dictionary, yard_path: Array[Vector2i]) -> Array[Vector2i]:
	var path_keys: Dictionary = {}
	for path_cell in yard_path:
		path_keys[_cell_key(path_cell)] = true
	var result: Array[Vector2i] = []
	for cell_value in (parcel.get("cells", []) as Array):
		var cell := _cell_from_dict(cell_value as Dictionary)
		if cell == Vector2i(-1, -1):
			continue
		if _cell_in_rect(cell, building_bounds):
			continue
		if path_keys.has(_cell_key(cell)):
			continue
		result.append(cell)
	return result


func _yard_path_between(entry_cell: Vector2i, door_step: Vector2i, parcel_data: Dictionary, building_bounds: Dictionary) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if entry_cell == Vector2i(-1, -1) or door_step == Vector2i(-1, -1):
		return empty
	var parcel_cell_keys := _parcel_cell_key_set(parcel_data, _uses_legacy_layout)
	if parcel_cell_keys.is_empty():
		return empty
	if not parcel_cell_keys.has(_cell_key(entry_cell)) or not parcel_cell_keys.has(_cell_key(door_step)):
		return empty
	if _cell_in_rect(entry_cell, building_bounds):
		return empty
	var frontier: Array[Vector2i] = [entry_cell]
	var came_from: Dictionary = {}
	var visited: Dictionary = { _cell_key(entry_cell): true }
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front() as Vector2i
		if current == door_step:
			return _rebuild_yard_path(came_from, entry_cell, door_step)
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next_cell: Vector2i = current + direction
			var key := _cell_key(next_cell)
			if visited.has(key):
				continue
			if not parcel_cell_keys.has(key):
				continue
			if _cell_in_rect(next_cell, building_bounds) and next_cell != door_step:
				continue
			visited[key] = true
			came_from[key] = current
			frontier.append(next_cell)
	return empty


func _rebuild_yard_path(came_from: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [to_cell]
	var cursor := to_cell
	while cursor != from_cell:
		var cursor_key := _cell_key(cursor)
		if not came_from.has(cursor_key):
			return []
		cursor = came_from.get(cursor_key, from_cell) as Vector2i
		path.push_front(cursor)
	return path


func _dict_path(path: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in path:
		result.append(_dict_cell(cell))
	return result


func _apply_yard_path(path: Array) -> void:
	for cell_value in path:
		var cell := _cell_from_dict(cell_value as Dictionary)
		if cell == Vector2i(-1, -1):
			continue
		_set_path_tile(cell)


func _apply_adaptive_yard(
	parcel: Dictionary,
	placement: Dictionary,
	building_bounds: Dictionary,
	door: Vector2i,
	door_step: Vector2i,
	building_instance_id: String,
	yard_policy: String
) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var path_keys: Dictionary = {}
	for path_value in (placement.get("yard_path", []) as Array):
		path_keys[_cell_key(_cell_from_dict(path_value as Dictionary))] = true
	var limit := 3 if yard_policy != "clear_frontage" else 1
	for cell_value in (placement.get("yard_cells", []) as Array):
		if slots.size() >= limit:
			break
		var cell := _cell_from_dict(cell_value as Dictionary)
		var key := _cell_key(cell)
		if cell == Vector2i(-1, -1) or cell == door or cell == door_step:
			continue
		if _cell_in_rect(cell, building_bounds) or path_keys.has(key):
			continue
		if _reserved_cells.has(key) or _objects_by_cell.has(key):
			continue
		if _tile_at(cell) == "p":
			continue
		var decoration_type := _adaptive_yard_decoration_type(yard_policy, slots.size())
		var slot := {
			"id": "%s.yard_%02d" % [building_instance_id, slots.size() + 1],
			"type": decoration_type,
			"grid_position": _dict_cell(cell),
			"source": "parcel_adaptive_yard",
			"yard_policy": yard_policy,
			"blocks_movement": false,
		}
		_add_floor_decoration(decoration_type, cell, {
			"presentation_source": "parcel_adaptive_yard",
			"building_instance_id": building_instance_id,
			"parcel_id": str(parcel.get("id", "")),
			"yard_policy": yard_policy,
			"blocks_movement": false,
		})
		slots.append(slot)
	return slots


func _adaptive_yard_decoration_type(yard_policy: String, index: int) -> String:
	match yard_policy:
		"farmyard":
			return "flower_patch" if index % 2 == 0 else "farm_tool"
		"workshop_service_yard":
			return "stone" if index % 2 == 0 else "bucket"
		"small_residential_yard":
			return "flower_pot" if index % 2 == 0 else "flower_patch"
		_:
			return "grass_clump"


func _apply_farm(area: Dictionary) -> void:
	if area.is_empty():
		return
	var rect: Dictionary = area.duplicate(true)
	_paint_rect(rect, "f")
	_mark_rect_road_blocker(rect)
	_add_zone("farm_zone", "farm", "Farm Plots", rect)
	var work_cell := _rect_center_cell(rect)
	var access_cell := _cell_from_dict(area.get("access_cell", {}) as Dictionary)
	if access_cell == Vector2i(-1, -1):
		if not _uses_legacy_layout:
			_compiler_recovery_log.append({
				"area": area.duplicate(true),
				"reason": "agent farm area missing planner access_cell",
			})
			return
		access_cell = _farm_access_cell(rect)
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


func _apply_training_yard(area: Dictionary) -> void:
	if area.is_empty():
		return
	var rect: Dictionary = area.duplicate(true)
	_paint_rect(rect, "t")
	_add_zone("training_zone", "training", "Training Yard", rect)
	var guard_cell := _rect_center_cell(rect) + Vector2i(-2, 0)
	var dummy_a := _rect_center_cell(rect) + Vector2i(2, -1)
	var dummy_b := _rect_center_cell(rect) + Vector2i(2, 1)
	var access_cell := _cell_from_dict(area.get("access_cell", {}) as Dictionary)
	if access_cell == Vector2i(-1, -1):
		if not _uses_legacy_layout:
			_compiler_recovery_log.append({
				"area": area.duplicate(true),
				"reason": "agent training area missing planner access_cell",
			})
			return
		access_cell = _edge_cell_toward(rect, _get_entrance_cell("plaza"))
	_connector_cells["training"] = access_cell
	_set_path_tile(access_cell)
	_add_anchor("training_yard_guard_post", "training", guard_cell, "left", [guard_cell, guard_cell + Vector2i(1, 0)])
	_add_structure("weapon_rack", guard_cell + Vector2i(0, -2), { "blocks_movement": true })
	_add_structure("target", dummy_a + Vector2i(1, -1), { "blocks_movement": true })
	_add_structure("wood_stump", dummy_b + Vector2i(-1, 1), { "blocks_movement": true })
	_add_training_dummy("village_training_dummy_melee", dummy_a, ["basic_attack", "guard"], { "strength": 4, "agility": 2, "vitality": 5 })
	_add_training_dummy("village_training_dummy_ranged", dummy_b, ["quick_shot", "guard"], { "strength": 2, "agility": 4, "vitality": 4 })


func _apply_wild_gate(area: Dictionary) -> void:
	if area.is_empty():
		return
	var access_cell := _cell_from_dict(area.get("access_cell", {}) as Dictionary)
	if access_cell == Vector2i(-1, -1):
		if not _uses_legacy_layout:
			_compiler_recovery_log.append({
				"area": area.duplicate(true),
				"reason": "agent gate area missing planner access_cell",
			})
			return
		access_cell = Vector2i(_width - 3, clampi(int(_rect_center(area).y), 2, _height - 3))
	var y := clampi(access_cell.y, 2, _height - 3)
	var exit_cell := Vector2i(_width - 1, y)
	_set_tile(exit_cell, "e")
	var gate_anchor := access_cell
	for x in range(mini(gate_anchor.x, exit_cell.x), maxi(gate_anchor.x, exit_cell.x)):
		_set_path_tile(Vector2i(x, y))
	_add_zone("wilderness_gate_zone", "wild_entrance", "Wild Gate", {
		"x": max(1, _width - 6),
		"y": max(1, y - 1),
		"w": 5,
		"h": 3,
	})
	_add_entrance("from_wild", gate_anchor, "left")
	_add_anchor("wild_gate_guard_post", "guard_post", gate_anchor + Vector2i(-1, 0), "right", [gate_anchor + Vector2i(-1, 0), gate_anchor])
	_connector_cells["settlement_exit_east"] = gate_anchor
	_add_exit("settlement_exit_east", exit_cell, "", "")
	var sign_cell := gate_anchor + Vector2i(0, 1)
	if not _in_bounds(sign_cell):
		sign_cell = gate_anchor + Vector2i(0, -1)
	_add_structure("signpost", sign_cell, { "blocks_movement": true })
	_add_object({
		"id": "village_wild_gate_sign",
		"display_name": "Wild Gate Sign",
		"grid_position": _dict_cell(sign_cell),
		"blocks_movement": true,
		"kind": "inspectable",
		"is_inspectable": true,
		"inspect_text": "The generated road leaves town here.",
	})


func _connect_key_places(allow_compiler_recovery: bool = false) -> void:
	var plaza_cell := _get_entrance_cell("plaza")
	for connector_value in _connector_cells.values():
		var connector: Vector2i = connector_value as Vector2i
		if connector != Vector2i(-1, -1):
			_route_and_carve_path(plaza_cell, connector, allow_compiler_recovery, "connector")

	for exit_data in (_generated.get("exits", []) as Array):
		var exit_cell: Vector2i = _cell_from_dict((exit_data as Dictionary).get("grid_position", {}) as Dictionary)
		_route_and_carve_path(plaza_cell, exit_cell, allow_compiler_recovery, "exit")
		_set_tile(exit_cell, "e")


func _apply_planned_decorations(decoration_slots: Array) -> void:
	for slot_value in decoration_slots:
		var slot: Dictionary = slot_value as Dictionary
		var cell := _cell_from_dict(slot.get("grid_position", {}) as Dictionary)
		if not _in_bounds(cell):
			continue
		if _reserved_cells.has(_cell_key(cell)) or _road_blockers.has(_cell_key(cell)):
			continue
		if _tile_at(cell) == "p":
			continue
		_add_floor_decoration(str(slot.get("type", "grass_clump")), cell, {
			"presentation_source": "agent_decoration_slot",
			"blocks_movement": false,
		})


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
	var home_building := _first_building_by_role("home")
	var shop_building := _first_building_by_archetype("shop")
	var tavern_building := _first_building_by_archetype("tavern")
	var villager_schedule: Array[Dictionary] = []
	if not home_building.is_empty():
		villager_schedule.append(_building_schedule_entry("home_morning", "06:00", "07:29", home_building, "primary", "left", "rest", "getting ready at home"))
	if not shop_building.is_empty():
		villager_schedule.append(_building_schedule_entry("shop_morning", "07:30", "11:59", shop_building, "primary", "down", "shopkeep", "tending the shop"))
	if not tavern_building.is_empty():
		villager_schedule.append(_building_schedule_entry("tavern_lunch", "12:00", "12:59", tavern_building, "primary", "right", "eat", "having lunch at the tavern"))
	if not shop_building.is_empty():
		villager_schedule.append(_building_schedule_entry("shop_afternoon", "13:00", "17:59", shop_building, "primary", "down", "shopkeep", "tending the shop"))
	if not tavern_building.is_empty():
		villager_schedule.append(_building_schedule_entry("tavern_evening", "18:00", "20:59", tavern_building, "primary", "right", "social", "eating at the tavern"))
	if not home_building.is_empty():
		villager_schedule.append(_building_schedule_entry("home_night", "21:00", "05:59", home_building, "primary", "left", "sleep", "resting at home"))

	var villager_row := {
		"id": "debug_villager",
		"source": "res://data/characters/debug_villager.json",
		"facing": "down",
		"schedule": villager_schedule,
	}
	_town_character_rows.append(villager_row.duplicate(true))
	(_generated.get("characters", []) as Array).append(villager_row)
	var guard_row := {
		"id": "debug_guard",
		"source": "res://data/characters/debug_guard.json",
		"facing": "left",
		"schedule": [
			_schedule_entry("training_morning", "06:00", "11:59", "training_yard_guard_post", "left", "train", "watching the training yard"),
			_schedule_entry("plaza_midday_patrol", "12:00", "13:59", "plaza_social_spot", "left", "patrol", "checking the plaza"),
			_schedule_entry("training_afternoon", "14:00", "17:59", "training_yard_guard_post", "left", "train", "watching the training yard"),
			_schedule_entry("gate_night", "18:00", "05:59", "wild_gate_guard_post", "right", "patrol", "guarding the wild gate"),
		],
	}
	_town_character_rows.append(guard_row.duplicate(true))
	(_generated.get("characters", []) as Array).append(guard_row)


func _refresh_interior_character_contexts() -> void:
	for index in range(_interior_manifests.size()):
		var manifest: Dictionary = _interior_manifests[index] as Dictionary
		var context: Dictionary = manifest.get("generation_context", {}) as Dictionary
		context["characters"] = _town_character_rows.duplicate(true)
		manifest["generation_context"] = context
		_interior_manifests[index] = manifest

	var interiors: Array = _generated.get("interiors", []) as Array
	for index in range(interiors.size()):
		var manifest: Dictionary = interiors[index] as Dictionary
		var context: Dictionary = manifest.get("generation_context", {}) as Dictionary
		context["characters"] = _town_character_rows.duplicate(true)
		manifest["generation_context"] = context
		interiors[index] = manifest
	_generated["interiors"] = interiors

	var objects: Array = _generated.get("objects", []) as Array
	for index in range(objects.size()):
		var object_data: Dictionary = objects[index] as Dictionary
		var context: Dictionary = object_data.get("transition_context", {}) as Dictionary
		if context.is_empty():
			continue
		context["characters"] = _town_character_rows.duplicate(true)
		object_data["transition_context"] = context
		objects[index] = object_data
	_generated["objects"] = objects


func _first_building_by_role(role: String) -> Dictionary:
	for building_value in _building_instances:
		var building: Dictionary = building_value as Dictionary
		if str(building.get("role", "")) == role:
			return building
	return {}


func _first_building_by_archetype(archetype_id: String) -> Dictionary:
	for building_value in _building_instances:
		var building: Dictionary = building_value as Dictionary
		if str(building.get("archetype_id", "")) == archetype_id:
			return building
	return {}


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
		"location_id": str(_generated.get("id", "")),
		"anchor_id": anchor_id,
		"facing": facing,
		"activity_type": activity_type,
		"activity": activity,
		"movement": "walk",
	}


func _building_schedule_entry(
	entry_id: String,
	start_time: String,
	end_time: String,
	building: Dictionary,
	interior_anchor_id: String,
	facing: String,
	activity_type: String,
	activity: String
) -> Dictionary:
	var entry := _schedule_entry(entry_id, start_time, end_time, interior_anchor_id, facing, activity_type, activity)
	entry["location_id"] = str(building.get("interior_location_id", ""))
	entry["building_instance_id"] = str(building.get("id", ""))
	entry["transition_anchor_by_location"] = _transition_anchors_for_building(building)
	return entry


func _transition_anchors_for_building(target_building: Dictionary) -> Dictionary:
	var anchors := {}
	var exterior_location_id := str(_generated.get("id", ""))
	if not exterior_location_id.is_empty():
		anchors[exterior_location_id] = str(target_building.get("exterior_door_anchor_id", ""))
	for building_value in _building_instances:
		var building: Dictionary = building_value as Dictionary
		var interior_location_id := str(building.get("interior_location_id", ""))
		if not interior_location_id.is_empty():
			anchors[interior_location_id] = "exit"
	return anchors


func _paint_rect(rect: Dictionary, key: String) -> void:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			_set_tile(Vector2i(x, y), key)


func _route_and_carve_path(from_cell: Vector2i, to_cell: Vector2i, allow_compiler_recovery: bool = false, reason: String = "") -> void:
	var path: Array[Vector2i] = _find_road_path(from_cell, to_cell)
	if path.is_empty():
		if not allow_compiler_recovery:
			_compiler_recovery_log.append({
				"from": _dict_cell(from_cell),
				"to": _dict_cell(to_cell),
				"reason": "planner road connection missing: %s" % reason,
			})
			return
		path = _fallback_edge_path(from_cell, to_cell)
		_compiler_recovery_log.append({
			"from": _dict_cell(from_cell),
			"to": _dict_cell(to_cell),
			"reason": "legacy fallback edge path: %s" % reason,
			"path_length": path.size(),
		})
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


func _add_floor_overlay(overlay_type: String, bounds: Dictionary, extra: Dictionary = {}) -> void:
	var entry := {
		"type": overlay_type,
		"bounds": bounds.duplicate(true),
	}
	entry.merge(extra, true)
	(_generated.get("floor_overlays", []) as Array).append(entry)


func _add_roof(roof_id: String, palette: String, bounds: Dictionary, hide_bounds: Dictionary = {}, prefab_id: String = "", archetype_id: String = "") -> void:
	(_generated.get("roofs", []) as Array).append({
		"id": roof_id,
		"palette": palette,
		"bounds": {
			"x": int(bounds.get("x", 0)),
			"y": int(bounds.get("y", 0)),
			"w": int(bounds.get("w", 0)),
			"h": max(1, int(bounds.get("h", 0))),
		},
		"hide_bounds": hide_bounds.duplicate(true) if not hide_bounds.is_empty() else bounds.duplicate(true),
		"prefab_id": prefab_id,
		"archetype_id": archetype_id,
		"presentation_layer": "game",
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


func _residential_cluster_score(center: Vector2, placed_buildings: Array[Dictionary]) -> float:
	var best := 0.0
	for building_value in placed_buildings:
		var building: Dictionary = building_value as Dictionary
		var spec: Dictionary = building.get("spec", {}) as Dictionary
		if str(spec.get("role", "")) != "home":
			continue
		var lot: Dictionary = building.get("lot", {}) as Dictionary
		best = maxf(best, 12.0 - center.distance_to(_rect_center(lot)) * 0.5)
	return best


func _add_placement_log(subject: String, candidate: Dictionary, reason: String) -> void:
	_placement_log.append({
		"subject": subject,
		"candidate": candidate.duplicate(true),
		"reason": reason,
	})


func _record_building_adaptation_failure(request: Dictionary, lot: Dictionary, reason: String) -> void:
	_building_adaptation_failures.append({
		"request_id": str(request.get("id", "")),
		"role": str(request.get("role", "")),
		"required": ["residential", "shop"].has(str(request.get("id", ""))),
		"lot": lot.duplicate(true),
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


func _cell_rect(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y, "w": 1, "h": 1 }


func _cell_in_rect(cell: Vector2i, rect: Dictionary) -> bool:
	if rect.is_empty():
		return false
	var x: int = int(rect.get("x", 0))
	var y: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	return cell.x >= x and cell.y >= y and cell.x < x + w and cell.y < y + h


func _lot_overlaps_any_reserved_rect(lot: Dictionary, reserved_rects: Array) -> bool:
	for rect_value in reserved_rects:
		var rect: Dictionary = rect_value as Dictionary
		if _rects_overlap_with_padding(lot, rect, 0):
			return true
	return false


func _rects_overlap_with_padding(a: Dictionary, b: Dictionary, padding: int = 0) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var ax: int = int(a.get("x", 0))
	var ay: int = int(a.get("y", 0))
	var aw: int = int(a.get("w", 0))
	var ah: int = int(a.get("h", 0))
	var bx: int = int(b.get("x", 0))
	var by: int = int(b.get("y", 0))
	var bw: int = int(b.get("w", 0))
	var bh: int = int(b.get("h", 0))
	return ax - padding < bx + bw \
		and bx - padding < ax + aw \
		and ay - padding < by + bh \
		and by - padding < ay + ah


func _union_rect(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.is_empty():
		return b.duplicate(true)
	if b.is_empty():
		return a.duplicate(true)
	var x0: int = min(int(a.get("x", 0)), int(b.get("x", 0)))
	var y0: int = min(int(a.get("y", 0)), int(b.get("y", 0)))
	var x1: int = max(int(a.get("x", 0)) + int(a.get("w", 0)), int(b.get("x", 0)) + int(b.get("w", 0)))
	var y1: int = max(int(a.get("y", 0)) + int(a.get("h", 0)), int(b.get("y", 0)) + int(b.get("h", 0)))
	return { "x": x0, "y": y0, "w": max(1, x1 - x0), "h": max(1, y1 - y0) }


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_key_set_from_dicts(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		if cell == Vector2i(-1, -1):
			continue
		result[_cell_key(cell)] = true
	return result


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


func _contract_validate_road_network(grid: LocationGrid) -> Array[String]:
	var errors: Array[String] = []
	var network_cells: Array[Vector2i] = []
	var network_keys: Dictionary = {}
	for y in range(grid.height):
		for x in range(grid.width):
			var cell := Vector2i(x, y)
			var terrain_key := grid.terrain_key_at(cell)
			if terrain_key != "p" and terrain_key != "s" and terrain_key != "e":
				continue
			network_cells.append(cell)
			network_keys[_cell_key(cell)] = true
	if network_cells.is_empty():
		errors.append("road network has no road, plaza, or exit cells")
		return errors

	var frontier: Array[Vector2i] = [network_cells[0]]
	var visited: Dictionary = { _cell_key(network_cells[0]): true }
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front() as Vector2i
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next_cell: Vector2i = current + direction
			var key := _cell_key(next_cell)
			if visited.has(key) or not network_keys.has(key):
				continue
			visited[key] = true
			frontier.append(next_cell)

	if visited.size() != network_cells.size():
		errors.append("road network is not connected: %d of %d cells reachable" % [visited.size(), network_cells.size()])
	return errors


func _contract_is_agent_settlement(location_data: Dictionary) -> bool:
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	return str(summary.get("type", "")) == "agent_settlement_blueprint"


func _contract_required_zone_ids(location_data: Dictionary) -> Array[String]:
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	var planner: Dictionary = summary.get("planner", {}) as Dictionary
	var values: Array = planner.get("required_zone_ids", []) as Array
	if values.is_empty():
		if _contract_is_agent_settlement(location_data):
			return []
		return ["plaza", "residential", "market", "farm", "training", "gate"]
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _contract_required_request_ids(location_data: Dictionary) -> Array[String]:
	var summary: Dictionary = location_data.get("generation_summary", {}) as Dictionary
	var planner: Dictionary = summary.get("planner", {}) as Dictionary
	var values: Array = planner.get("required_request_ids", []) as Array
	if values.is_empty():
		if _contract_is_agent_settlement(location_data):
			return []
		return ["residential", "shop"]
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _contract_validate_required_buildings(location_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var role_counts: Dictionary = {}
	var archetype_counts: Dictionary = {}
	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var role := str(building.get("role", ""))
		var archetype_id := str(building.get("archetype_id", ""))
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		archetype_counts[archetype_id] = int(archetype_counts.get(archetype_id, 0)) + 1

	var required_requests := _contract_required_request_ids(location_data)
	if _contract_is_agent_settlement(location_data) and required_requests.is_empty():
		errors.append("agent planner summary missing required_request_ids")
		return errors
	if required_requests.has("residential") and int(role_counts.get("home", 0)) < 1:
		errors.append("required residential building missing")
	if required_requests.has("shop") and int(archetype_counts.get("shop", 0)) < 1:
		errors.append("required merchant shop building missing")

	var request_ids: Dictionary = {}
	for request_value in (location_data.get("building_requests", []) as Array):
		var request: Dictionary = request_value as Dictionary
		var request_id := str(request.get("id", ""))
		if request_id.is_empty():
			errors.append("building request missing id")
			continue
		request_ids[request_id] = true
		if str(request.get("parcel_id", "")).is_empty():
			errors.append("building request missing parcel_id: %s" % request_id)
		if str(request.get("prefab_id", "")).is_empty():
			errors.append("building request missing prefab_id: %s" % request_id)
	for required_request in required_requests:
		if not request_ids.has(required_request):
			errors.append("required building request missing: %s" % required_request)
	return errors


func _contract_validate_interiors_and_transitions(
	location_data: Dictionary,
	grid: LocationGrid,
	blockers: Dictionary,
	plaza_cell: Vector2i
) -> Array[String]:
	var errors: Array[String] = []
	var exterior_location_id := str(location_data.get("id", ""))
	var interior_ids: Dictionary = {}
	for interior_value in (location_data.get("interiors", []) as Array):
		var interior: Dictionary = interior_value as Dictionary
		var interior_id := str(interior.get("location_id", ""))
		if interior_id.is_empty():
			errors.append("interior manifest missing location_id")
			continue
		if interior_ids.has(interior_id):
			errors.append("duplicate interior location id: %s" % interior_id)
		interior_ids[interior_id] = true

	var building_ids: Dictionary = {}
	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var building_id := str(building.get("id", ""))
		var interior_id := str(building.get("interior_location_id", ""))
		if building_id.is_empty():
			errors.append("building missing id")
		else:
			building_ids[building_id] = true
		if interior_id.is_empty() or not interior_ids.has(interior_id):
			errors.append("building references missing interior manifest: %s / %s" % [building_id, interior_id])
		var bounds: Dictionary = building.get("bounds", {}) as Dictionary
		if not _contract_rect_in_bounds(grid, bounds):
			errors.append("building footprint out of bounds: %s" % building_id)
		if _contract_rect_overlaps_road(grid, bounds):
			errors.append("building footprint overlaps road incorrectly: %s" % building_id)
		var doorstep := _cell_from_dict(building.get("doorstep", {}) as Dictionary)
		if not _contract_is_open_cell(grid, doorstep, blockers):
			errors.append("building door frontage is not walkable: %s at %s" % [building_id, doorstep])
		elif not _contract_has_path(grid, plaza_cell, doorstep, blockers):
			errors.append("building door frontage is unreachable: %s at %s" % [building_id, doorstep])

	for transition_value in (location_data.get("transitions", []) as Array):
		var transition: Dictionary = transition_value as Dictionary
		var from_location_id := str(transition.get("from_location_id", ""))
		var to_location_id := str(transition.get("to_location_id", ""))
		var from_anchor_id := str(transition.get("from_anchor_id", ""))
		var to_anchor_id := str(transition.get("to_anchor_id", ""))
		var building_instance_id := str(transition.get("building_instance_id", ""))
		if not building_ids.has(building_instance_id):
			errors.append("transition references missing building instance: %s" % building_instance_id)
		if not _contract_location_id_is_known(from_location_id, exterior_location_id, interior_ids):
			errors.append("transition from_location_id is unknown: %s" % from_location_id)
		if not _contract_location_id_is_known(to_location_id, exterior_location_id, interior_ids):
			errors.append("transition to_location_id is unknown: %s" % to_location_id)
		if from_location_id == exterior_location_id and grid.get_anchor(from_anchor_id).is_empty():
			errors.append("transition references missing exterior from anchor: %s" % from_anchor_id)
		if to_location_id == exterior_location_id and grid.get_entrance(to_anchor_id).is_empty() and grid.get_anchor(to_anchor_id).is_empty():
			errors.append("transition references missing exterior to anchor or entrance: %s" % to_anchor_id)
		if from_location_id != exterior_location_id and from_anchor_id != "exit":
			errors.append("interior transition must leave through exit anchor: %s" % from_anchor_id)
		if to_location_id != exterior_location_id and to_anchor_id != "entry":
			errors.append("interior transition must enter through entry anchor: %s" % to_anchor_id)
	return errors


func _contract_schedule_interior_anchor_is_valid(location_data: Dictionary, scheduled_location_id: String, anchor_id: String) -> bool:
	for building_value in (location_data.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		if str(building.get("interior_location_id", "")) != scheduled_location_id:
			continue
		var slots: Dictionary = building.get("interior_slots", {}) as Dictionary
		if slots.has(anchor_id):
			return true
		for slot_value in slots.values():
			if str(slot_value) == anchor_id:
				return true
		return false
	return false


func _contract_validate_decoration_slots(location_data: Dictionary, required_anchor_ids: Array[String]) -> Array[String]:
	var errors: Array[String] = []
	var anchor_cells: Dictionary = {}
	for anchor_value in (location_data.get("anchors", []) as Array):
		var anchor: Dictionary = anchor_value as Dictionary
		var anchor_id := str(anchor.get("id", ""))
		if not required_anchor_ids.has(anchor_id):
			continue
		var anchor_cell := _cell_from_dict(anchor.get("grid_position", {}) as Dictionary)
		anchor_cells[_cell_key(anchor_cell)] = anchor_id

	for decoration_value in (location_data.get("floor_decorations", []) as Array):
		var decoration: Dictionary = decoration_value as Dictionary
		var cell := _cell_from_dict(decoration.get("grid_position", {}) as Dictionary)
		var key := _cell_key(cell)
		if anchor_cells.has(key):
			errors.append("decoration overlaps critical anchor: %s at %s" % [str(anchor_cells.get(key, "")), cell])
	return errors


func _contract_rect_in_bounds(grid: LocationGrid, rect: Dictionary) -> bool:
	if rect.is_empty():
		return false
	var x: int = int(rect.get("x", 0))
	var y: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	return grid.in_bounds(Vector2i(x, y)) and grid.in_bounds(Vector2i(x + w - 1, y + h - 1))


func _contract_rect_overlaps_road(grid: LocationGrid, rect: Dictionary) -> bool:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			if grid.terrain_key_at(Vector2i(x, y)) == "p":
				return true
	return false


func _contract_location_id_is_known(location_id: String, exterior_location_id: String, interior_ids: Dictionary) -> bool:
	return location_id == exterior_location_id or interior_ids.has(location_id)
