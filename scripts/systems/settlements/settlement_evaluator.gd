class_name SettlementEvaluator
extends RefCounted


func evaluate_step(session, committed_proposals: Array[PlanProposal]) -> Dictionary:
	var issues: Array[String] = []
	var feedback := {
		"need_more_roads": false,
		"need_more_generic_plots": false,
		"need_more_differentiation": false,
		"need_more_footprints": false,
	}

	if session.blueprint.cores.is_empty():
		issues.append("missing_core_seed")
	if session.blueprint.roads.size() < 3 and session.current_step >= 3:
		issues.append("road_network_too_small")
		feedback["need_more_roads"] = true
	if _generic_plot_count(session) < 3 and session.current_step >= 6:
		issues.append("not_enough_generic_plots")
		feedback["need_more_generic_plots"] = true
	if _differentiated_plot_count(session) < 2 and session.current_step >= 9:
		issues.append("not_enough_differentiated_plots")
		feedback["need_more_differentiation"] = true
	if session.blueprint.buildings.size() < 2 and session.current_step >= 12:
		issues.append("not_enough_building_footprints")
		feedback["need_more_footprints"] = true
	if not session.blueprint.plots.is_empty() and not _plots_are_road_accessible(session):
		issues.append("plot_without_road_access")

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
