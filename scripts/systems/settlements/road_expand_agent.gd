class_name RoadExpandAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "road_expand_agent"
	spec = AgentSpecScript.create(1, 1, 8)


func is_active(session) -> bool:
	return not session.blueprint.roads.is_empty()


func propose(session) -> Array[PlanProposal]:
	var candidates := _road_segment_candidates(session, false)
	var best := _best_sample(candidates, session, 8)
	if best.is_empty():
		return []
	var result: Array[PlanProposal] = []
	result.append(_make_road_proposal(best, session, "expand"))
	return result


func _road_segment_candidates(session, branch: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var starts: Array[Vector2i] = _road_cells(session) if branch else _road_endpoints(session)
	for start in starts:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var path := _segment_from(start, direction, session.randi_range(2, 3, "road_segment_length"), session)
			if path.is_empty():
				continue
			var end_cell: Vector2i = path[path.size() - 1]
			var score: float = session.feature_maps.get_value("edge_distance", end_cell, 0.0)
			score += session.feature_maps.get_value("land_value", end_cell, 0.0)
			score -= _nearby_road_count(path, session) * 0.7
			if branch:
				score += session.feature_maps.get_value("road_distance", end_cell, 0.0) * 0.15
			result.append({ "path": path, "score": score })
	return result


func _make_road_proposal(candidate: Dictionary, session, kind: String) -> PlanProposal:
	var path: Array[Vector2i] = candidate.get("path", []) as Array[Vector2i]
	var proposal := PlanProposal.create(agent_id, "add_road_segment", session.current_step, "blueprint_growth", "Grow the road network by one short segment.", 70)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.path = path
	proposal.affected_cells = path.duplicate()
	proposal.payload = { "id": "%s_%02d" % [kind, session.current_step], "kind": kind }
	var tags: Array[String] = ["road", kind, "step_growth"]
	proposal.tags = tags
	proposal.score = float(candidate.get("score", 0.0))
	return proposal


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


func _road_endpoints(session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		var path: Array = road.get("path", []) as Array
		if path.is_empty():
			continue
		for cell_value in [path[0], path[path.size() - 1]]:
			var cell := _cell_from_variant(cell_value)
			if not result.has(cell):
				result.append(cell)
	return result


func _road_cells(session) -> Array[Vector2i]:
	return session.feature_maps.cells_for_map_value("road", 0.0)


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
		var index: int = session.randi_range(0, pool.size() - 1, "road_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		if best.is_empty() or float(candidate.get("score", -9999.0)) > float(best.get("score", -9999.0)):
			best = candidate
	return best


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
