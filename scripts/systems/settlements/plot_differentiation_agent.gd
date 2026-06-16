class_name PlotDifferentiationAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "plot_differentiation_agent"
	spec = AgentSpecScript.create(4, 1, 8)


func is_active(session) -> bool:
	return _generic_plots(session).size() > 0


func propose(session) -> Array[PlanProposal]:
	var candidates: Array[Dictionary] = []
	for plot in _generic_plots(session):
		var use_scores := {
			"residential": _score_residential(plot, session),
			"commercial": _score_commercial(plot, session),
			"production": _score_production(plot, session),
			"public": _score_public(plot, session),
		}
		var best_use := ""
		var best_score := -9999.0
		for use in ["residential", "commercial", "production", "public"]:
			var score := float(use_scores[use])
			if score > best_score:
				best_score = score
				best_use = str(use)
		candidates.append({ "plot": plot, "use": best_use, "score": best_score })
	var best := _best_sample(candidates, session, 8)
	if best.is_empty():
		return []
	var plot: Dictionary = best.get("plot", {}) as Dictionary
	var area: Dictionary = plot.get("area", {}) as Dictionary
	var selected_use := str(best.get("use", "residential"))
	var proposal := PlanProposal.create(agent_id, "differentiate_plot", session.current_step, "differentiation", "Differentiate one generic plot by local utility scoring.", 55)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.area = area
	proposal.affected_cells = _area_cells(area)
	proposal.payload = { "plot_id": str(plot.get("id", "")), "use": selected_use }
	var conflicts: Array[String] = ["plot:%s" % str(plot.get("id", ""))]
	proposal.conflicts = conflicts
	var tags: Array[String] = ["plot_differentiation", selected_use]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = [proposal]
	return result


func _generic_plots(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "generic")) == "generic":
			result.append(plot)
	return result


func _score_residential(plot: Dictionary, session) -> float:
	var center := _area_center(plot.get("area", {}) as Dictionary)
	return session.feature_maps.get_value("land_value", center, 0.0) + 1.0 - session.feature_maps.get_value("density_pressure", center, 0.0) * 0.4


func _score_commercial(plot: Dictionary, session) -> float:
	var access := _cell_from_variant(plot.get("road_access_cell", {}))
	return _junction_score(access, session) * 2.0 + session.feature_maps.get_value("land_value", access, 0.0)


func _score_production(plot: Dictionary, session) -> float:
	var center := _area_center(plot.get("area", {}) as Dictionary)
	var edge: float = 8.0 - session.feature_maps.get_value("edge_distance", center, 0.0)
	var entrance: float = 10.0 / maxf(1.0, session.feature_maps.get_value("entrance_distance", center, 99.0))
	return edge + entrance


func _score_public(plot: Dictionary, session) -> float:
	if _count_use(session, "public") > 0:
		return -10.0
	var center := _area_center(plot.get("area", {}) as Dictionary)
	return session.feature_maps.get_value("land_value", center, 0.0) + _junction_score(_cell_from_variant(plot.get("road_access_cell", {})), session)


func _junction_score(cell: Vector2i, session) -> float:
	var count := 0
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if session.feature_maps.is_road(cell + direction):
			count += 1
	return float(count)


func _count_use(session, use: String) -> int:
	var count := 0
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) == use:
			count += 1
	return count


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "differentiation_candidate_sample")
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


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
