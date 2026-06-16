class_name GenericPlotAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "generic_plot_agent"
	spec = AgentSpecScript.create(2, 1, 8)


func is_active(session) -> bool:
	return not session.blueprint.roads.is_empty()


func propose(session) -> Array[PlanProposal]:
	var candidates := _plot_candidates(session)
	var best := _best_sample(candidates, session, 10)
	if best.is_empty():
		return []
	var area: Dictionary = best.get("area", {}) as Dictionary
	var proposal := PlanProposal.create(agent_id, "add_generic_plot", session.current_step, "blueprint_growth", "Grow one road-connected generic building plot.", 60)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.area = area
	proposal.affected_cells = _area_cells(area)
	proposal.payload = {
		"id": "generic_plot_%02d" % session.blueprint.plots.size(),
		"road_access_cell": best.get("road_access_cell", Vector2i.ZERO),
		"facing": str(best.get("facing", "")),
	}
	var tags: Array[String] = ["generic_plot", "step_growth"]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = [proposal]
	return result


func _plot_candidates(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var road_cells: Array[Vector2i] = session.feature_maps.cells_for_map_value("road", 0.0)
	for road_cell in road_cells:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			for size in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
				var area := _area_from_road(road_cell, direction, size)
				if not _area_is_valid(area, session):
					continue
				var score: float = session.feature_maps.get_value("land_value", _area_center(area), 0.0)
				score -= session.feature_maps.get_value("density_pressure", _area_center(area), 0.0) * 0.7
				score -= _same_row_penalty(area, session)
				result.append({
					"area": area,
					"score": score,
					"road_access_cell": road_cell,
					"facing": _facing_from_direction(-direction),
				})
	return result


func _area_from_road(road_cell: Vector2i, direction: Vector2i, size: Vector2i) -> Dictionary:
	if direction == Vector2i.UP:
		return { "x": road_cell.x - int(size.x / 2), "y": road_cell.y - size.y, "width": size.x, "height": size.y }
	if direction == Vector2i.DOWN:
		return { "x": road_cell.x - int(size.x / 2), "y": road_cell.y + 1, "width": size.x, "height": size.y }
	if direction == Vector2i.LEFT:
		return { "x": road_cell.x - size.x, "y": road_cell.y - int(size.y / 2), "width": size.x, "height": size.y }
	return { "x": road_cell.x + 1, "y": road_cell.y - int(size.y / 2), "width": size.x, "height": size.y }


func _area_is_valid(area: Dictionary, session) -> bool:
	for cell in _area_cells(area):
		if not session.context.in_bounds(cell):
			return false
		if not session.feature_maps.is_buildable(cell):
			return false
		if session.feature_maps.is_reserved(cell):
			return false
	return true


func _same_row_penalty(area: Dictionary, session) -> float:
	var penalty := 0.0
	var y := int(area.get("y", 0))
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		var plot_area: Dictionary = plot.get("area", {}) as Dictionary
		if int(plot_area.get("y", -9999)) == y:
			penalty += 0.4
	return penalty


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "plot_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		if best.is_empty() or float(candidate.get("score", -9999.0)) > float(best.get("score", -9999.0)):
			best = candidate
	return best


func _area_center(area: Dictionary) -> Vector2i:
	return Vector2i(int(area.get("x", 0)) + int(area.get("width", 1)) / 2, int(area.get("y", 0)) + int(area.get("height", 1)) / 2)


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(int(area.get("y", 0)), int(area.get("y", 0)) + int(area.get("height", 0))):
		for x in range(int(area.get("x", 0)), int(area.get("x", 0)) + int(area.get("width", 0))):
			result.append(Vector2i(x, y))
	return result


func _facing_from_direction(direction: Vector2i) -> String:
	if direction == Vector2i.UP:
		return "up"
	if direction == Vector2i.DOWN:
		return "down"
	if direction == Vector2i.LEFT:
		return "left"
	return "right"
