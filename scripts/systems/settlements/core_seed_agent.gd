class_name CoreSeedAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "core_seed_agent"
	spec = AgentSpecScript.create(0, 1, 2)


func is_active(session) -> bool:
	return session.current_step == 0 and session.blueprint.cores.is_empty()


func propose(session) -> Array[PlanProposal]:
	var candidate: Dictionary = _pick_core_candidate(session)
	if candidate.is_empty():
		return []
	var core_cell: Vector2i = candidate.get("cell", Vector2i.ZERO) as Vector2i
	var proposals: Array[PlanProposal] = []

	var core := PlanProposal.create(agent_id, "add_core_seed", session.current_step, "blueprint_growth", "Choose the initial core seed by feature-map fitness.", 100)
	core.proposal_id = session.next_proposal_id(agent_id)
	var core_cells: Array[Vector2i] = [core_cell]
	core.affected_cells = core_cells
	core.payload = { "id": "core_seed", "cell": core_cell }
	var core_tags: Array[String] = ["core_seed", "v62_step_growth"]
	core.tags = core_tags
	core.score = float(candidate.get("score", 0.0))
	proposals.append(core)

	var entrance: Vector2i = session.context.entrances[0] if not session.context.entrances.is_empty() else Vector2i(0, core_cell.y)
	var direction := _direction_toward(core_cell, entrance)
	var road_path: Array[Vector2i] = []
	var first: Vector2i = core_cell + direction
	var second: Vector2i = core_cell + direction * 2
	if session.context.in_bounds(first):
		road_path.append(first)
	if session.context.in_bounds(second):
		road_path.append(second)
	if not road_path.is_empty():
		var road := PlanProposal.create(agent_id, "add_road_segment", session.current_step, "blueprint_growth", "Create a short road seed next to the chosen core.", 95)
		road.proposal_id = session.next_proposal_id(agent_id)
		road.path = road_path
		road.affected_cells = road_path.duplicate()
		road.payload = { "id": "road_seed", "kind": "seed" }
		var road_tags: Array[String] = ["road_seed", "v62_step_growth"]
		road.tags = road_tags
		road.score = float(candidate.get("score", 0.0)) - 1.0
		proposals.append(road)
	return proposals


func _pick_core_candidate(session) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for y in range(1, session.context.map_size.y - 1):
		for x in range(1, session.context.map_size.x - 1):
			var cell := Vector2i(x, y)
			if not session.feature_maps.is_buildable(cell):
				continue
			var edge_distance: float = session.feature_maps.get_value("edge_distance", cell, 0.0)
			var entrance_distance: float = session.feature_maps.get_value("entrance_distance", cell, 99.0)
			var open_space := _open_space_score(cell, session)
			var score := open_space * 2.0 + edge_distance - entrance_distance * 0.15
			candidates.append({ "cell": cell, "score": score })
	return _best_sample(candidates, session, 10)


func _open_space_score(center: Vector2i, session) -> float:
	var score := 0.0
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var cell := Vector2i(x, y)
			if session.context.in_bounds(cell) and session.feature_maps.is_buildable(cell):
				score += 1.0
	return score


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "core_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		if best.is_empty() or float(candidate.get("score", -9999.0)) > float(best.get("score", -9999.0)):
			best = candidate
	return best


func _direction_toward(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var delta := to_cell - from_cell
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(1 if delta.x >= 0 else -1, 0)
	return Vector2i(0, 1 if delta.y >= 0 else -1)
