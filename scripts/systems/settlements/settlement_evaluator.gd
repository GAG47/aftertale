class_name SettlementEvaluator
extends RefCounted

const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")


func evaluate_step(session, committed_proposals: Array[PlanProposal]) -> Dictionary:
	var issues: Array[String] = []
	var score_penalties: Array[Dictionary] = []
	var feedback := {
		"need_more_roads": false,
		"need_more_generic_plots": false,
		"need_more_differentiation": false,
		"need_more_footprints": false,
		"need_public_space": false,
		"entrance_disconnected": false,
		"core_disconnected_from_entrance": false,
		"road_component_count": 0,
		"entrance_connected": false,
		"core_connected": false,
		"all_plot_access_connected": false,
		"all_building_front_connected": false,
		"road_overdensity_zones": [],
		"road_disconnected_components": 0,
		"isolated_plots": [],
		"disconnected_buildings": [],
		"weak_core_zones": [],
		"road_connectivity": {},
	}
	var road_connectivity := _road_connectivity(session)
	var road_overdensity_zones := _road_overdensity_zones(session)
	var isolated_plots: Array = road_connectivity.get("disconnected_plot_ids", []) as Array
	var disconnected_buildings: Array = road_connectivity.get("disconnected_building_ids", []) as Array
	var weak_core_zones := _weak_core_zones(session, road_connectivity)
	feedback["road_connectivity"] = road_connectivity
	feedback["road_component_count"] = int(road_connectivity.get("road_component_count", 0))
	feedback["entrance_connected"] = bool(road_connectivity.get("entrance_connected", false))
	feedback["core_connected"] = bool(road_connectivity.get("core_connected", false))
	feedback["all_plot_access_connected"] = bool(road_connectivity.get("all_plot_access_connected", false))
	feedback["all_building_front_connected"] = bool(road_connectivity.get("all_building_front_connected", false))
	feedback["road_disconnected_components"] = max(0, int(road_connectivity.get("road_component_count", 0)) - 1)
	feedback["road_overdensity_zones"] = road_overdensity_zones
	feedback["isolated_plots"] = isolated_plots
	feedback["disconnected_buildings"] = disconnected_buildings
	feedback["weak_core_zones"] = weak_core_zones

	if session.blueprint.cores.is_empty():
		_add_penalty(issues, score_penalties, "missing_core_seed", 0.12, "core")
	if session.blueprint.roads.size() < 3 and session.current_step >= 3:
		_add_penalty(issues, score_penalties, "road_network_too_small", 0.12, "roads")
		feedback["need_more_roads"] = true
	if int(road_connectivity.get("road_component_count", 0)) > 1 and session.current_step >= 5:
		_add_penalty(issues, score_penalties, "road_component_count_not_one", 0.12, "components:%d" % int(road_connectivity.get("road_component_count", 0)))
		feedback["need_more_roads"] = true
	if not bool(road_connectivity.get("entrance_connected", false)) and session.current_step >= 4:
		_add_penalty(issues, score_penalties, "entrance_disconnected", 0.12, "entrance")
		feedback["need_more_roads"] = true
		feedback["entrance_disconnected"] = true
	if not bool(road_connectivity.get("core_connected", false)) and session.current_step >= 5:
		_add_penalty(issues, score_penalties, "core_disconnected_from_entrance", 0.12, "core")
		feedback["need_more_roads"] = true
		feedback["entrance_disconnected"] = true
		feedback["core_disconnected_from_entrance"] = true
	if int(road_connectivity.get("disconnected_road_cell_count", 0)) > 0 and session.current_step >= 5:
		_add_penalty(issues, score_penalties, "road_graph_disconnected", 0.12, "road_cells:%d" % int(road_connectivity.get("disconnected_road_cell_count", 0)))
		feedback["need_more_roads"] = true
	if _generic_plot_count(session) < 3 and session.current_step >= 6:
		_add_penalty(issues, score_penalties, "not_enough_generic_plots", 0.12, "generic_plots")
		feedback["need_more_generic_plots"] = true
	if _differentiated_plot_count(session) < 2 and session.current_step >= 9:
		_add_penalty(issues, score_penalties, "not_enough_differentiated_plots", 0.12, "differentiated_plots")
		feedback["need_more_differentiation"] = true
	if _public_plot_count(session) < 1 and session.current_step >= 10:
		_add_penalty(issues, score_penalties, "missing_public_space", 0.12, "public_plot")
		feedback["need_public_space"] = true
		feedback["need_more_differentiation"] = true
	if session.blueprint.buildings.size() < 2 and session.current_step >= 16:
		_add_penalty(issues, score_penalties, "not_enough_building_footprints", 0.12, "building_footprints")
		feedback["need_more_footprints"] = true
	if not session.blueprint.plots.is_empty() and not bool(road_connectivity.get("all_plot_access_connected", true)):
		_add_penalty(issues, score_penalties, "plot_without_road_access", 0.12, "plots")
	if not isolated_plots.is_empty():
		_add_penalty(issues, score_penalties, "isolated_plots", 0.12, "plots:%s" % ",".join(_string_array(isolated_plots)))
	if not disconnected_buildings.is_empty():
		_add_penalty(issues, score_penalties, "building_without_main_road_access", 0.12, "buildings:%s" % ",".join(_string_array(disconnected_buildings)))
	if not road_overdensity_zones.is_empty():
		_add_penalty(issues, score_penalties, "road_overdensity", 0.12, "zones:%d" % road_overdensity_zones.size())
	if not weak_core_zones.is_empty():
		_add_penalty(issues, score_penalties, "weak_core_zones", 0.12, "zones:%s" % ",".join(weak_core_zones))

	var score := 1.0 - _penalty_weight_sum(score_penalties)
	score = clampf(score, 0.0, 1.0)

	return {
		"step": session.current_step,
		"committed_proposal_ids": _proposal_ids(committed_proposals),
		"score": score,
		"issues": issues,
		"score_penalties": score_penalties,
		"feedback": feedback,
		"core_count": session.blueprint.cores.size(),
		"road_count": session.blueprint.roads.size(),
		"generic_plot_count": _generic_plot_count(session),
		"differentiated_plot_count": _differentiated_plot_count(session),
		"public_plot_count": _public_plot_count(session),
		"building_count": session.blueprint.buildings.size(),
		"occupied_count": session.feature_maps.occupied_count(),
		"road_connectivity": road_connectivity,
		"road_component_count": int(road_connectivity.get("road_component_count", 0)),
		"entrance_connected": bool(road_connectivity.get("entrance_connected", false)),
		"core_connected": bool(road_connectivity.get("core_connected", false)),
		"all_plot_access_connected": bool(road_connectivity.get("all_plot_access_connected", false)),
		"all_building_front_connected": bool(road_connectivity.get("all_building_front_connected", false)),
	}


func evaluate(session, committed_proposal: PlanProposal) -> Dictionary:
	var rows: Array[PlanProposal] = []
	if committed_proposal != null:
		rows.append(committed_proposal)
	return evaluate_step(session, rows)


func _proposal_ids(proposals: Array[PlanProposal]) -> Array[String]:
	var result: Array[String] = []
	for proposal in proposals:
		result.append(proposal.proposal_id)
	return result


func _add_penalty(issues: Array[String], penalties: Array[Dictionary], reason: String, weight: float, affected_object: String) -> void:
	issues.append(reason)
	penalties.append({
		"reason": reason,
		"weight": weight,
		"affected_object": affected_object,
	})


func _penalty_weight_sum(penalties: Array[Dictionary]) -> float:
	var result := 0.0
	for penalty in penalties:
		result += float(penalty.get("weight", 0.0))
	return result


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _generic_plot_count(session) -> int:
	var count := 0
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "generic":
			count += 1
	return count


func _differentiated_plot_count(session) -> int:
	var count := 0
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "differentiated":
			count += 1
	return count


func _public_plot_count(session) -> int:
	var count := 0
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) == "public":
			count += 1
	return count


func _road_connectivity(session) -> Dictionary:
	return RoadGraphScript.analyze_blueprint(
		session.blueprint.to_dictionary(),
		session.context.entrances,
		session.context.map_size
	)


func _road_overdensity_zones(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			var nearby := 0
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if session.feature_maps.is_road(cell + direction):
					nearby += 1
			if nearby >= 4:
				result.append({ "x": cell.x, "y": cell.y })
	return result


func _weak_core_zones(session, road_connectivity: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if session.blueprint.cores.is_empty():
		return result
	if _public_plot_count(session) <= 0 and session.current_step >= 10:
		result.append("core_missing_public_space")
	if not bool(road_connectivity.get("core_connected", false)) and session.current_step >= 5:
		result.append("core_not_on_main_road")
	elif _nearest_road_distance_to_core(session) > 2 and session.current_step >= 5:
		result.append("core_road_pressure_weak")
	return result


func _entrance_road_distance(session) -> int:
	var road_cells := _road_cells(session)
	if road_cells.is_empty() or session.context.entrances.is_empty():
		return 999
	var best := 999
	for entrance in session.context.entrances:
		for road_cell in road_cells:
			best = min(best, absi(entrance.x - road_cell.x) + absi(entrance.y - road_cell.y))
	return best


func _nearest_road_distance_to_core(session) -> int:
	var road_cells := _road_cells(session)
	if road_cells.is_empty() or session.blueprint.cores.is_empty():
		return 999
	var best := 999
	for core_value in session.blueprint.cores:
		var core: Dictionary = core_value as Dictionary
		var core_cell := _cell_from_variant(core.get("cell", {}))
		for road_cell in road_cells:
			best = min(best, absi(core_cell.x - road_cell.x) + absi(core_cell.y - road_cell.y))
	return best


func _road_cells(session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			if not result.has(cell):
				result.append(cell)
	return result


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := int(area.get("x", 0))
	var y0 := int(area.get("y", 0))
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			result.append(Vector2i(x, y))
	return result


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
