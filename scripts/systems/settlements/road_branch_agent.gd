class_name RoadBranchAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "road_branch_agent"
	spec = AgentSpecScript.create(3, 3, 4)


func is_active(session) -> bool:
	return not session.blueprint.roads.is_empty()


func propose(session) -> Array[PlanProposal]:
	var candidates := _branch_candidates(session)
	var best := _best_sample(candidates, session, 8)
	if best.is_empty():
		return []
	var path: Array[Vector2i] = best.get("path", []) as Array[Vector2i]
	var proposal := PlanProposal.create(agent_id, "add_road_segment", session.current_step, "blueprint_growth", "Grow a short branch from the existing road network.", 65)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.path = path
	proposal.affected_cells = path.duplicate()
	proposal.payload = { "id": "branch_%02d" % session.current_step, "kind": "branch" }
	var tags: Array[String] = ["road", "branch", "step_growth"]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = [proposal]
	return result


func _branch_candidates(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var road_cells: Array[Vector2i] = session.feature_maps.cells_for_map_value("road", 0.0)
	for start in road_cells:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var path := _segment_from(start, direction, session.randi_range(2, 3, "road_branch_length"), session)
			if path.is_empty():
				continue
			var end_cell: Vector2i = path[path.size() - 1]
			var score: float = session.feature_maps.get_value("road_distance", end_cell, 0.0) * 0.15
			score += session.feature_maps.get_value("land_value", end_cell, 0.0)
			score -= _nearby_road_count(path, session) * 0.6
			result.append({ "path": path, "score": score })
	return result


func _segment_from(start: Vector2i, direction: Vector2i, length: int, session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cursor := start
	for _i in range(length):
		cursor += direction
		if not session.context.in_bounds(cursor):
			return []
		if not session.feature_maps.is_buildable(cursor):
			return []
		if session.feature_maps.is_reserved(cursor):
			return []
		result.append(cursor)
	return result


func _nearby_road_count(path: Array[Vector2i], session) -> float:
	var count := 0
	for cell in path:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if session.feature_maps.is_road(cell + direction):
				count += 1
	return float(count)


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "road_branch_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		if best.is_empty() or float(candidate.get("score", -9999.0)) > float(best.get("score", -9999.0)):
			best = candidate
	return best
