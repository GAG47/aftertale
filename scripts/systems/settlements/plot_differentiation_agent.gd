class_name PlotDifferentiationAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "plot_differentiation_agent"
	spec = AgentSpecScript.create(4, 1, 7)


func is_active(session) -> bool:
	return _generic_plots(session).size() > 0


func propose(session) -> Array[PlanProposal]:
	var candidates: Array[Dictionary] = []
	for plot in _generic_plots(session):
		for use in ["residential", "commercial", "production", "public"]:
			candidates.append(_bid_candidate(plot, use, session))
	var sampled := _sample_candidates(candidates, session, 12)
	_record_search(session, candidates, sampled)
	var result: Array[PlanProposal] = []
	for candidate in sampled:
		result.append(_make_bid_proposal(candidate, session))
	return result


func _make_bid_proposal(candidate: Dictionary, session) -> PlanProposal:
	var plot: Dictionary = candidate.get("plot", {}) as Dictionary
	var area: Dictionary = plot.get("area", {}) as Dictionary
	var selected_use := str(candidate.get("use", "residential"))
	var proposal := PlanProposal.create(agent_id, "differentiate_plot", session.current_step, "differentiation", "%s bid for %s." % [selected_use.capitalize(), str(plot.get("id", ""))], 55)
	proposal.proposal_id = session.next_proposal_id("%s_bid" % selected_use)
	proposal.area = area
	proposal.affected_cells = _area_cells(area)
	proposal.payload = {
		"plot_id": str(plot.get("id", "")),
		"use": selected_use,
		"bid": (candidate.get("bid", {}) as Dictionary).duplicate(true),
	}
	var conflicts: Array[String] = ["plot:%s" % str(plot.get("id", ""))]
	proposal.conflicts = conflicts
	var tags: Array[String] = ["plot_differentiation_bid", selected_use]
	proposal.tags = tags
	proposal.score = float(candidate.get("score", 0.0))
	return proposal


func _generic_plots(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "generic")) == "generic":
			if _plot_age(plot, session) >= 2:
				result.append(plot)
	return result


func _score_residential(plot: Dictionary, session) -> float:
	var center := _area_center(plot.get("area", {}) as Dictionary)
	var score: float = session.feature_maps.get_value("land_value", center, 0.0) + 1.0 - session.feature_maps.get_value("density_pressure", center, 0.0) * 0.4
	if bool(session.evaluation_feedback.get("need_public_space", false)):
		score -= 1.0
	return score


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
	var score: float = session.feature_maps.get_value("land_value", center, 0.0) + _junction_score(_cell_from_variant(plot.get("road_access_cell", {})), session)
	if bool(session.evaluation_feedback.get("need_public_space", false)) or session.current_step >= 8:
		score += 6.0
	return score


func _bid_candidate(plot: Dictionary, use: String, session) -> Dictionary:
	var center := _area_center(plot.get("area", {}) as Dictionary)
	var access := _cell_from_variant(plot.get("road_access_cell", {}))
	var road_access_score := _junction_score(access, session)
	var core_distance_score := 10.0 / maxf(1.0, session.feature_maps.get_value("center_distance", center, 99.0))
	var public_need_score := float(session.demand_ledger.public_need) * 4.0 if use == "public" else 0.0
	var policy_weight := float(session.demand_ledger.need_for_use(use))
	var nearby_types := _nearby_types(plot, session)
	var score := 0.0
	match use:
		"residential":
			score = _score_residential(plot, session)
		"commercial":
			score = _score_commercial(plot, session)
		"production":
			score = _score_production(plot, session)
		"public":
			score = _score_public(plot, session)
	score += policy_weight
	var reason := "%s demand=%d road=%.2f core=%.2f public=%.2f" % [
		use,
		session.demand_ledger.need_for_use(use),
		road_access_score,
		core_distance_score,
		public_need_score,
	]
	return {
		"plot": plot,
		"use": use,
		"score": score,
		"bid": {
			"plot_id": str(plot.get("id", "")),
			"use_type": use,
			"score": score,
			"reason": reason,
			"nearby_types": nearby_types,
			"road_access_score": road_access_score,
			"core_distance_score": core_distance_score,
			"public_need_score": public_need_score,
			"policy_weight": policy_weight,
		},
	}


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


func _sample_candidates(candidates: Array[Dictionary], session, sample_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "differentiation_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		result.append(candidate)
	return result


func _record_search(session, candidates: Array[Dictionary], sampled: Array[Dictionary]) -> void:
	var top_score := -9999.0
	for candidate in candidates:
		top_score = maxf(top_score, float(candidate.get("score", -9999.0)))
	var chosen_score := 0.0
	var chosen_plot := ""
	for candidate in sampled:
		if chosen_plot.is_empty() or float(candidate.get("score", -9999.0)) > chosen_score:
			chosen_score = float(candidate.get("score", 0.0))
			chosen_plot = str((candidate.get("plot", {}) as Dictionary).get("id", ""))
	session.trace.record_agent_search(session.current_step, agent_id, {
		"valid_candidates_count": candidates.size(),
		"sampled_candidates_count": sampled.size(),
		"top_score": top_score if not candidates.is_empty() else 0.0,
		"chosen_score": chosen_score,
		"chosen_plot": chosen_plot,
		"rejected_reason_distribution": {},
		"bidding": true,
	})


func _nearby_types(plot: Dictionary, session) -> Dictionary:
	var result := {
		"residential": 0,
		"commercial": 0,
		"production": 0,
		"public": 0,
	}
	var center := _area_center(plot.get("area", {}) as Dictionary)
	for other_value in session.blueprint.plots:
		var other: Dictionary = other_value as Dictionary
		var use := str(other.get("use", ""))
		if not result.has(use):
			continue
		var other_center := _area_center(other.get("area", {}) as Dictionary)
		if absi(center.x - other_center.x) + absi(center.y - other_center.y) <= 5:
			result[use] = int(result.get(use, 0)) + 1
	return result


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


func _plot_age(plot: Dictionary, session) -> int:
	return session.current_step - int(plot.get("step", session.current_step))
