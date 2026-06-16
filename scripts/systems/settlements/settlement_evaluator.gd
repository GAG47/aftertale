class_name SettlementEvaluator
extends RefCounted


func evaluate_step(session, committed_proposals: Array[PlanProposal]) -> Dictionary:
	var issues: Array[String] = []
	var feedback := {
		"need_more_roads": false,
		"need_more_generic_plots": false,
		"need_more_differentiation": false,
		"need_more_footprints": false,
		"need_public_space": false,
		"entrance_disconnected": false,
		"road_overdensity_zones": [],
		"isolated_plots": [],
		"weak_core_zones": [],
	}
	var road_overdensity_zones := _road_overdensity_zones(session)
	var isolated_plots := _isolated_plot_ids(session)
	var weak_core_zones := _weak_core_zones(session)
	feedback["road_overdensity_zones"] = road_overdensity_zones
	feedback["isolated_plots"] = isolated_plots
	feedback["weak_core_zones"] = weak_core_zones

	if session.blueprint.cores.is_empty():
		issues.append("missing_core_seed")
	if session.blueprint.roads.size() < 3 and session.current_step >= 3:
		issues.append("road_network_too_small")
		feedback["need_more_roads"] = true
	if _entrance_road_distance(session) > 1 and session.current_step >= 4:
		issues.append("entrance_disconnected")
		feedback["need_more_roads"] = true
		feedback["entrance_disconnected"] = true
	if _generic_plot_count(session) < 3 and session.current_step >= 6:
		issues.append("not_enough_generic_plots")
		feedback["need_more_generic_plots"] = true
	if _differentiated_plot_count(session) < 2 and session.current_step >= 9:
		issues.append("not_enough_differentiated_plots")
		feedback["need_more_differentiation"] = true
	if _public_plot_count(session) < 1 and session.current_step >= 10:
		issues.append("missing_public_space")
		feedback["need_public_space"] = true
		feedback["need_more_differentiation"] = true
	if session.blueprint.buildings.size() < 2 and session.current_step >= 16:
		issues.append("not_enough_building_footprints")
		feedback["need_more_footprints"] = true
	if not session.blueprint.plots.is_empty() and not _plots_are_road_accessible(session):
		issues.append("plot_without_road_access")
	if not isolated_plots.is_empty():
		issues.append("isolated_plots:%d" % isolated_plots.size())
	if not road_overdensity_zones.is_empty():
		issues.append("road_overdensity:%d" % road_overdensity_zones.size())
	if not weak_core_zones.is_empty():
		issues.append("weak_core_zones:%d" % weak_core_zones.size())

	var score := 1.0 - float(issues.size()) * 0.12
	score = clampf(score, 0.0, 1.0)

	return {
		"step": session.current_step,
		"committed_proposal_ids": _proposal_ids(committed_proposals),
		"score": score,
		"issues": issues,
		"feedback": feedback,
		"core_count": session.blueprint.cores.size(),
		"road_count": session.blueprint.roads.size(),
		"generic_plot_count": _generic_plot_count(session),
		"differentiated_plot_count": _differentiated_plot_count(session),
		"public_plot_count": _public_plot_count(session),
		"building_count": session.blueprint.buildings.size(),
		"occupied_count": session.feature_maps.occupied_count(),
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


func _plots_are_road_accessible(session) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		var area: Dictionary = plot.get("area", {}) as Dictionary
		var has_access := false
		for cell in _area_cells(area):
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if session.feature_maps.is_road(cell + direction):
					has_access = true
					break
			if has_access:
				break
		if not has_access:
			return false
	return true


func _isolated_plot_ids(session) -> Array[String]:
	var result: Array[String] = []
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if not _plot_has_road_access(plot, session):
			result.append(str(plot.get("id", "")))
	return result


func _plot_has_road_access(plot: Dictionary, session) -> bool:
	var area: Dictionary = plot.get("area", {}) as Dictionary
	for cell in _area_cells(area):
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if session.feature_maps.is_road(cell + direction):
				return true
	return false


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


func _weak_core_zones(session) -> Array[String]:
	var result: Array[String] = []
	if session.blueprint.cores.is_empty():
		return result
	if _public_plot_count(session) <= 0 and session.current_step >= 10:
		result.append("core_missing_public_space")
	if _nearest_road_distance_to_core(session) > 2 and session.current_step >= 5:
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
