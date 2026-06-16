class_name SettlementEvaluator
extends RefCounted


func evaluate(session, committed_proposal: PlanProposal) -> Dictionary:
	var issues: Array[String] = []
	if session.blueprint.cores.is_empty():
		issues.append("missing_core")
	if session.blueprint.roads.is_empty() and not session.blueprint.cores.is_empty():
		issues.append("missing_road")
	if session.current_phase in ["building", "landmark", "validation"] and session.blueprint.plots.is_empty():
		issues.append("missing_plots")
	if session.current_phase in ["landmark", "validation"] and session.blueprint.buildings.is_empty():
		issues.append("missing_buildings")
	if session.current_phase == "validation" and session.blueprint.landmarks.is_empty():
		issues.append("missing_landmark")
	if not session.blueprint.plots.is_empty() and not _plots_are_road_accessible(session):
		issues.append("plot_without_road_access")

	var score := 1.0
	score -= float(issues.size()) * 0.2
	score = clampf(score, 0.0, 1.0)

	return {
		"step": session.committed_step,
		"phase": session.current_phase,
		"committed_proposal_id": committed_proposal.proposal_id if committed_proposal != null else "",
		"score": score,
		"issues": issues,
		"core_count": session.blueprint.cores.size(),
		"road_count": session.blueprint.roads.size(),
		"plot_count": session.blueprint.plots.size(),
		"building_count": session.blueprint.buildings.size(),
		"landmark_count": session.blueprint.landmarks.size(),
		"anchor_count": session.blueprint.interaction_anchors.size(),
		"occupied_count": session.feature_maps.occupied_count(),
	}


func _plots_are_road_accessible(session) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		var area: Dictionary = plot.get("area", {}) as Dictionary
		var has_access := false
		for cell in _area_cells(area):
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if _cell_on_road(cell + direction, session):
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


func _cell_on_road(cell: Vector2i, session) -> bool:
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var road_cell: Dictionary = cell_value as Dictionary
			if Vector2i(int(road_cell.get("x", -9999)), int(road_cell.get("y", -9999))) == cell:
				return true
	return false
