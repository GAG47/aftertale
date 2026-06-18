class_name SettlementBlueprint
extends RefCounted

const COMMIT_TOKEN := "settlement_resolver_commit"

var cores: Array[Dictionary] = []
var districts: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var road_endpoints: Array[Dictionary] = []
var plots: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var production_areas: Array[Dictionary] = []
var defenses: Array[Dictionary] = []
var decorations: Array[Dictionary] = []
var entrances: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var interaction_anchors: Array[Dictionary] = []
var history: Array[Dictionary] = []
var committed_proposal_ids: Array[String] = []


func apply_committed_proposal(proposal: PlanProposal, commit_token: String) -> bool:
	if commit_token != COMMIT_TOKEN:
		return false
	if proposal == null:
		return false

	match proposal.type:
		"add_core_seed":
			cores.append({
				"id": str(proposal.payload.get("id", "core_%d" % cores.size())),
				"cell": _dict_cell(proposal.primary_cell()),
				"tags": proposal.tags.duplicate(),
				"step": proposal.step,
			})
			_upsert_anchor("core_anchor", "core", proposal.primary_cell(), "core_seed", proposal.step)
		"add_road_segment":
			roads.append({
				"id": str(proposal.payload.get("id", "road_%d" % roads.size())),
				"kind": str(proposal.payload.get("kind", "settlement_road")),
				"path": _cells_to_dicts(proposal.path),
				"tags": proposal.tags.duplicate(),
				"step": proposal.step,
			})
			_sync_road_anchors(proposal.step)
		"add_generic_plot":
			var plot_id := str(proposal.payload.get("id", "plot_%d" % plots.size()))
			var road_access_cell := _cell_from_variant(proposal.payload.get("road_access_cell", Vector2i(-9999, -9999)))
			plots.append({
				"id": plot_id,
				"kind": "generic_building_plot",
				"use": "generic",
				"status": "generic",
				"area": _rect_to_dictionary(proposal.area),
				"road_access_cell": _dict_cell(road_access_cell),
				"facing": str(proposal.payload.get("facing", "")),
				"tags": proposal.tags.duplicate(),
				"step": proposal.step,
			})
			_upsert_anchor("plot_access_%s" % plot_id, "plot_access", road_access_cell, plot_id, proposal.step)
		"differentiate_plot":
			if not _differentiate_plot(proposal):
				return false
		"add_building_footprint":
			var building_id := str(proposal.payload.get("id", "building_%d" % buildings.size()))
			var entrance_cell := _cell_from_variant(proposal.payload.get("entrance_cell", proposal.primary_cell()))
			buildings.append({
				"id": building_id,
				"kind": str(proposal.payload.get("kind", proposal.payload.get("building_type", "dwelling"))),
				"building_type": str(proposal.payload.get("building_type", proposal.payload.get("kind", "dwelling"))),
				"use_type": str(proposal.payload.get("use_type", proposal.payload.get("building_type", "dwelling"))),
				"plot_id": str(proposal.payload.get("plot_id", "")),
				"area": _rect_to_dictionary(proposal.area),
				"entrance_cell": _dict_cell(entrance_cell),
				"front_access_cell": _dict_cell(_cell_from_variant(proposal.payload.get("front_access_cell", entrance_cell))),
				"footprint_size": (proposal.payload.get("footprint_size", {}) as Dictionary).duplicate(true),
				"facing": str(proposal.payload.get("facing", "")),
				"asset_family": str(proposal.payload.get("asset_family", "")),
				"enterable": bool(proposal.payload.get("enterable", false)),
				"interior_template_id": str(proposal.payload.get("interior_template_id", "")),
				"home_capacity": int(proposal.payload.get("home_capacity", 0)),
				"work_slots": int(proposal.payload.get("work_slots", 0)),
				"service_slots": int(proposal.payload.get("service_slots", 0)),
				"activity_slots": int(proposal.payload.get("activity_slots", 0)),
				"home_slot_anchor": str(proposal.payload.get("home_slot_anchor", "")),
				"work_slot_anchor": str(proposal.payload.get("work_slot_anchor", "")),
				"service_slot_anchor": str(proposal.payload.get("service_slot_anchor", "")),
				"activity_slot_anchor": str(proposal.payload.get("activity_slot_anchor", "")),
				"entrance_anchor": str(proposal.payload.get("entrance_anchor", "")),
				"interaction_anchor": str(proposal.payload.get("interaction_anchor", "")),
				"quest_anchor": str(proposal.payload.get("quest_anchor", "")),
				"presentation_note": str(proposal.payload.get("presentation_note", "")),
				"tags": proposal.tags.duplicate(),
				"step": proposal.step,
			})
			_upsert_anchor("building_entrance_%s" % building_id, "building_entrance", entrance_cell, building_id, proposal.step)
			_upsert_optional_building_hooks(building_id, proposal.payload, entrance_cell, proposal.step)
		_:
			return false

	committed_proposal_ids.append(proposal.proposal_id)
	history.append({
		"proposal_id": proposal.proposal_id,
		"type": proposal.type,
		"step": proposal.step,
		"stage": proposal.stage,
		"reason": proposal.reason,
	})
	return true


func committed_count() -> int:
	return committed_proposal_ids.size()


func set_context_entrances(cells: Array[Vector2i]) -> void:
	entrances.clear()
	for index in range(cells.size()):
		var cell := cells[index]
		entrances.append({
			"id": "context_entrance_%d" % index,
			"cell": _dict_cell(cell),
			"player_spawn_anchor": "player_spawn_%d" % index,
			"settlement_entrance_anchor": "settlement_entrance_%d" % index,
		})
		_upsert_anchor("entrance_%d" % index, "entrance", cell, "context", -1)
		_upsert_anchor("player_spawn_%d" % index, "player_spawn", cell, "context", -1)
		_upsert_anchor("settlement_entrance_%d" % index, "settlement_entrance", cell, "context", -1)


func to_dictionary() -> Dictionary:
	return {
		"cores": cores.duplicate(true),
		"districts": districts.duplicate(true),
		"roads": roads.duplicate(true),
		"road_endpoints": road_endpoints.duplicate(true),
		"plots": plots.duplicate(true),
		"buildings": buildings.duplicate(true),
		"landmarks": landmarks.duplicate(true),
		"production_areas": production_areas.duplicate(true),
		"defenses": defenses.duplicate(true),
		"decorations": decorations.duplicate(true),
		"entrances": entrances.duplicate(true),
		"exits": exits.duplicate(true),
		"interaction_anchors": interaction_anchors.duplicate(true),
		"history": history.duplicate(true),
		"committed_proposal_ids": committed_proposal_ids.duplicate(),
	}


static func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


static func _cells_to_dicts(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in cells:
		result.append(_dict_cell(cell))
	return result


static func _rect_to_dictionary(rect: Dictionary) -> Dictionary:
	return {
		"x": int(rect.get("x", 0)),
		"y": int(rect.get("y", 0)),
		"width": int(rect.get("width", 0)),
		"height": int(rect.get("height", 0)),
	}


func _differentiate_plot(proposal: PlanProposal) -> bool:
	var plot_id := str(proposal.payload.get("plot_id", ""))
	var selected_use := str(proposal.payload.get("use", ""))
	if plot_id.is_empty() or selected_use.is_empty():
		return false
	for index in range(plots.size()):
		var plot: Dictionary = plots[index] as Dictionary
		if str(plot.get("id", "")) != plot_id:
			continue
		plot["use"] = selected_use
		plot["status"] = "differentiated"
		plot["differentiated_step"] = proposal.step
		plot["differentiation_reason"] = proposal.reason
		plot["tags"] = proposal.tags.duplicate()
		plots[index] = plot
		if selected_use == "public":
			var center := _area_center(plot.get("area", {}) as Dictionary)
			plot["public_anchor"] = "public_anchor_%s" % plot_id
			plot["public_activity_anchor"] = "public_activity_%s" % plot_id
			plot["notice_anchor"] = "notice_%s" % plot_id
			plot["quest_anchor"] = "quest_%s" % plot_id
			plot["interaction_anchor"] = "public_interaction_%s" % plot_id
			plots[index] = plot
			_upsert_anchor(str(plot.get("public_anchor", "")), "public", center, plot_id, proposal.step)
			_upsert_anchor(str(plot.get("public_activity_anchor", "")), "public_activity", center, plot_id, proposal.step)
			_upsert_anchor(str(plot.get("notice_anchor", "")), "notice", center, plot_id, proposal.step)
			_upsert_anchor(str(plot.get("quest_anchor", "")), "quest", center, plot_id, proposal.step)
			_upsert_anchor(str(plot.get("interaction_anchor", "")), "public_interaction", center, plot_id, proposal.step)
		return true
	return false


func _upsert_anchor(anchor_id: String, kind: String, cell: Vector2i, source_id: String, step: int) -> void:
	if cell.x < 0 or cell.y < 0:
		return
	var anchor := {
		"id": anchor_id,
		"kind": kind,
		"cell": _dict_cell(cell),
		"source_id": source_id,
		"step": step,
	}
	for index in range(interaction_anchors.size()):
		var existing: Dictionary = interaction_anchors[index] as Dictionary
		if str(existing.get("id", "")) == anchor_id:
			interaction_anchors[index] = anchor
			return
	interaction_anchors.append(anchor)


func _sync_road_anchors(step: int) -> void:
	var previous_endpoints := _road_endpoint_by_id()
	_remove_anchors_by_kinds(["road_endpoint", "road_junction"])
	road_endpoints.clear()
	var road_cells := _all_road_cells()
	for road_value in roads:
		var road: Dictionary = road_value as Dictionary
		var path: Array = road.get("path", []) as Array
		if path.is_empty():
			continue
		_register_road_endpoint(road, path, 0, step, previous_endpoints)
		if path.size() > 1:
			_register_road_endpoint(road, path, path.size() - 1, step, previous_endpoints)
	for cell in road_cells:
		var neighbor_count := _road_neighbor_count(cell, road_cells)
		if neighbor_count == 1:
			_upsert_anchor("road_endpoint_%s" % _cell_key(cell), "road_endpoint", cell, "road_network", step)
		elif neighbor_count >= 3:
			_upsert_anchor("road_junction_%s" % _cell_key(cell), "road_junction", cell, "road_network", step)
	if not road_cells.is_empty():
		_upsert_anchor("road_network_anchor", "road_network", road_cells[0], "road_network", step)


func _upsert_optional_building_hooks(building_id: String, payload: Dictionary, entrance_cell: Vector2i, step: int) -> void:
	for key in ["home_slot_anchor", "work_slot_anchor", "service_slot_anchor", "activity_slot_anchor", "entrance_anchor", "interaction_anchor", "quest_anchor"]:
		var anchor_id := str(payload.get(key, ""))
		if anchor_id.is_empty():
			continue
		var kind: String = key.replace("_anchor", "")
		_upsert_anchor(anchor_id, kind, entrance_cell, building_id, step)


func _register_road_endpoint(road: Dictionary, path: Array, index: int, step: int, previous_endpoints: Dictionary) -> void:
	var cell := _cell_from_variant(path[index])
	var neighbor_index: int = min(path.size() - 1, 1) if index == 0 else max(0, path.size() - 2)
	var neighbor := _cell_from_variant(path[neighbor_index])
	var direction := cell - neighbor
	var endpoint_id := "endpoint_%s_%d" % [str(road.get("id", "")), index]
	var previous: Dictionary = previous_endpoints.get(endpoint_id, {}) as Dictionary
	road_endpoints.append({
		"endpoint_id": endpoint_id,
		"origin_road_id": str(road.get("id", "")),
		"cell": _dict_cell(cell),
		"direction_bias": _dict_cell(direction),
		"last_extended_step": int(previous.get("last_extended_step", step)),
		"failed_attempts": int(previous.get("failed_attempts", 0)),
		"growth_intent": str(previous.get("growth_intent", "extend")),
	})


func _road_endpoint_by_id() -> Dictionary:
	var result: Dictionary = {}
	for endpoint_value in road_endpoints:
		var endpoint: Dictionary = endpoint_value as Dictionary
		result[str(endpoint.get("endpoint_id", ""))] = endpoint.duplicate(true)
	return result


func _remove_anchors_by_kinds(kinds: Array[String]) -> void:
	var kept: Array[Dictionary] = []
	for anchor_value in interaction_anchors:
		var anchor: Dictionary = anchor_value as Dictionary
		if str(anchor.get("kind", "")) not in kinds:
			kept.append(anchor)
	interaction_anchors = kept


func _all_road_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for road_value in roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			if not result.has(cell):
				result.append(cell)
	return result


func _road_neighbor_count(cell: Vector2i, road_cells: Array[Vector2i]) -> int:
	var count := 0
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if road_cells.has(cell + direction):
			count += 1
	return count


func _area_center(area: Dictionary) -> Vector2i:
	return Vector2i(
		int(area.get("x", 0)) + int(area.get("width", 1)) / 2,
		int(area.get("y", 0)) + int(area.get("height", 1)) / 2
	)


func _cell_key(cell: Vector2i) -> String:
	return "%d_%d" % [cell.x, cell.y]


static func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
