class_name GenericPlotAgent
extends SettlementAgent

var plot_bias: String = "road_bias"


func _init(p_plot_bias: String = "road_bias") -> void:
	plot_bias = p_plot_bias
	agent_id = "generic_plot_agent_%s" % plot_bias
	spec = AgentSpecScript.create(2, 1, 8)


func is_active(session) -> bool:
	if _plot_count(session) >= session.desired_plot_count() and not bool(session.evaluation_feedback.get("need_more_generic_plots", false)):
		return false
	return not session.blueprint.roads.is_empty()


func propose(session) -> Array[PlanProposal]:
	var rejected := {}
	var candidates := _plot_candidates(session, rejected)
	var sample_count: int = session.candidate_sample_count(candidates.size(), 10)
	var best := _best_sample(candidates, session, sample_count)
	_record_search(session, candidates, best, rejected)
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
	var tags: Array[String] = ["generic_plot", plot_bias, "step_growth"]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = []
	result.append(proposal)
	return result


func _plot_candidates(session, rejected: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var road_cells: Array[Vector2i] = session.feature_maps.cells_for_map_value("road", 0.0)
	for road_cell in road_cells:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			for size in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
				var area := _area_from_road(road_cell, direction, size)
				var check := _area_check(area, session)
				if not bool(check.get("valid", false)):
					_count_reject(rejected, str(check.get("reason", "invalid")))
					continue
				var center := _area_center(area)
				var score: float = session.feature_maps.get_value("land_value", center, 0.0)
				score -= session.feature_maps.get_value("density_pressure", _area_center(area), 0.0) * 0.7
				score -= _same_row_penalty(area, session)
				score += _bias_score(center, road_cell, session)
				if bool(session.evaluation_feedback.get("need_more_generic_plots", false)):
					score += 2.5
				score *= session.agent_weight(agent_id, "plot")
				result.append({
					"area": area,
					"score": score,
					"road_access_cell": road_cell,
					"facing": _facing_from_direction(-direction),
					"center": center,
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


func _area_check(area: Dictionary, session) -> Dictionary:
	for cell in _area_cells(area):
		if not session.context.in_bounds(cell):
			return { "valid": false, "reason": "out_of_bounds" }
		if not session.feature_maps.is_buildable(cell):
			return { "valid": false, "reason": "not_buildable" }
		if session.feature_maps.is_reserved(cell):
			return { "valid": false, "reason": "reserved" }
	return { "valid": true }


func _bias_score(center: Vector2i, road_cell: Vector2i, session) -> float:
	match plot_bias:
		"core_bias":
			return 10.0 / maxf(1.0, session.feature_maps.get_value("center_distance", center, 99.0)) + session.feature_maps.get_value("land_value", center, 0.0)
		"edge_bias":
			return maxf(0.0, 8.0 - session.feature_maps.get_value("edge_distance", center, 0.0)) + 8.0 / maxf(1.0, session.feature_maps.get_value("entrance_distance", center, 99.0))
		_:
			return 3.0 / maxf(1.0, float(absi(center.x - road_cell.x) + absi(center.y - road_cell.y))) - session.feature_maps.get_value("district_pressure", center, 0.0) * 0.2


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


func _record_search(session, candidates: Array[Dictionary], chosen: Dictionary, rejected: Dictionary) -> void:
	var top_score := -9999.0
	for candidate in candidates:
		top_score = maxf(top_score, float(candidate.get("score", -9999.0)))
	var chosen_cell := {}
	if not chosen.is_empty():
		var center: Vector2i = chosen.get("center", Vector2i(-9999, -9999)) as Vector2i
		chosen_cell = { "x": center.x, "y": center.y }
	session.trace.record_agent_search(session.current_step, agent_id, {
		"valid_candidates_count": candidates.size(),
		"sampled_candidates_count": session.candidate_sample_count(candidates.size(), 10),
		"top_score": top_score if not candidates.is_empty() else 0.0,
		"chosen_score": float(chosen.get("score", 0.0)) if not chosen.is_empty() else 0.0,
		"chosen_cell": chosen_cell,
		"rejected_reason_distribution": rejected.duplicate(true),
		"bias": plot_bias,
		"policy_weight": session.agent_weight(agent_id, "plot"),
	})


func _count_reject(rejected: Dictionary, reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


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


func _generic_plot_count(session) -> int:
	var count := 0
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "generic":
			count += 1
	return count


func _plot_count(session) -> int:
	return session.blueprint.plots.size()
