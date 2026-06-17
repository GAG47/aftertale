class_name RoadReconnectAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "road_reconnect_agent"
	spec = AgentSpecScript.create(4, 2, 6)


func is_active(session) -> bool:
	return bool(session.evaluation_feedback.get("entrance_disconnected", false)) or session.demand_ledger.road_need > 1


func propose(session) -> Array[PlanProposal]:
	var rejected := {}
	var candidates := _candidates(session, rejected)
	var best := _best_sample(candidates, session, 6)
	_record_search(session, candidates, best, rejected)
	if best.is_empty():
		return []
	var path: Array[Vector2i] = best.get("path", []) as Array[Vector2i]
	var proposal := PlanProposal.create(agent_id, "add_road_segment", session.current_step, "blueprint_growth", "Reconnect an isolated entrance or weak road approach.", 74)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.path = path
	proposal.affected_cells = path.duplicate()
	proposal.payload = { "id": "reconnect_%02d" % session.current_step, "kind": "reconnect" }
	var tags: Array[String] = ["road", "reconnect", "step_growth"]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = []
	result.append(proposal)
	return result


func _candidates(session, rejected: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var starts := _start_cells(session)
	var targets := _target_cells(session)
	if starts.is_empty() or targets.is_empty():
		return result
	for start in starts:
		var target := _nearest_from_list(start, targets)
		var direction := _direction_toward_target(start, target)
		for candidate_direction in [direction, Vector2i(-direction.y, direction.x), Vector2i(direction.y, -direction.x)]:
			var segment := _segment_from(start, candidate_direction, session.randi_range(2, 4, "road_reconnect_length"), session)
			if not bool(segment.get("valid", false)):
				_count_reject(rejected, str(segment.get("reason", "invalid")))
				continue
			var path: Array[Vector2i] = segment.get("path", []) as Array[Vector2i]
			var end_cell: Vector2i = path[path.size() - 1]
			var target_distance := _nearest_distance(end_cell, targets)
			var score := 30.0 / maxf(1.0, float(target_distance))
			score += float(session.demand_ledger.road_need)
			if _touches_any(end_cell, targets):
				score += 8.0
			score *= session.agent_weight(agent_id, "road")
			result.append({ "path": path, "score": score, "end_cell": end_cell, "target": target })
	return result


func _segment_from(start: Vector2i, direction: Vector2i, length: int, session) -> Dictionary:
	if direction == Vector2i.ZERO:
		return { "valid": false, "reason": "zero_direction" }
	var path: Array[Vector2i] = []
	var cursor := start
	for _i in range(length):
		cursor += direction
		if not session.context.in_bounds(cursor):
			return { "valid": false, "reason": "out_of_bounds" }
		if not session.feature_maps.is_buildable(cursor):
			return { "valid": false, "reason": "not_buildable" }
		if session.feature_maps.is_reserved(cursor):
			return { "valid": false, "reason": "reserved" }
		path.append(cursor)
	return { "valid": true, "path": path }


func _start_cells(session) -> Array[Vector2i]:
	var connectivity: Dictionary = session.evaluation_feedback.get("road_connectivity", {}) as Dictionary
	var main_cells := _cells_from_rows(connectivity.get("main_road_cells", []) as Array)
	if main_cells.is_empty():
		return session.context.entrances.duplicate()
	var result: Array[Vector2i] = []
	for cell in main_cells:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next_cell: Vector2i = cell + direction
			if session.context.in_bounds(next_cell) and session.feature_maps.is_buildable(next_cell) and not session.feature_maps.is_reserved(next_cell):
				result.append(cell)
				break
	return result if not result.is_empty() else main_cells


func _target_cells(session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var connectivity: Dictionary = session.evaluation_feedback.get("road_connectivity", {}) as Dictionary
	for cell_value in (connectivity.get("disconnected_core_cells", []) as Array):
		_append_unique_cell(result, _cell_from_variant(cell_value))
	for cell_value in (connectivity.get("disconnected_road_cells", []) as Array):
		_append_unique_cell(result, _cell_from_variant(cell_value))
	if result.is_empty():
		for core_value in session.blueprint.cores:
			var core: Dictionary = core_value as Dictionary
			_append_unique_cell(result, _cell_from_variant(core.get("cell", {})))
	if result.is_empty():
		for point in session.context.important_world_points:
			_append_unique_cell(result, point)
	return result


func _nearest_from_list(from_cell: Vector2i, targets: Array[Vector2i]) -> Vector2i:
	var best_cell := from_cell + Vector2i.RIGHT
	var best_distance := 999
	for target in targets:
		var distance := absi(from_cell.x - target.x) + absi(from_cell.y - target.y)
		if distance < best_distance:
			best_distance = distance
			best_cell = target
	return best_cell


func _direction_toward_target(from_cell: Vector2i, target: Vector2i) -> Vector2i:
	var delta := target - from_cell
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(1 if delta.x >= 0 else -1, 0)
	return Vector2i(0, 1 if delta.y >= 0 else -1)


func _nearest_distance(cell: Vector2i, targets: Array[Vector2i]) -> int:
	var best := 999
	for target in targets:
		best = min(best, absi(cell.x - target.x) + absi(cell.y - target.y))
	return best


func _touches_any(cell: Vector2i, targets: Array[Vector2i]) -> bool:
	for target in targets:
		if absi(cell.x - target.x) + absi(cell.y - target.y) <= 1:
			return true
	return false


func _cells_from_rows(rows: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in rows:
		_append_unique_cell(result, _cell_from_variant(row))
	return result


func _append_unique_cell(cells: Array[Vector2i], cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0:
		return
	if not cells.has(cell):
		cells.append(cell)


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "road_reconnect_candidate_sample")
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
		var end_cell: Vector2i = chosen.get("end_cell", Vector2i(-9999, -9999)) as Vector2i
		chosen_cell = { "x": end_cell.x, "y": end_cell.y }
	session.trace.record_agent_search(session.current_step, agent_id, {
		"valid_candidates_count": candidates.size(),
		"sampled_candidates_count": min(6, candidates.size()),
		"top_score": top_score if not candidates.is_empty() else 0.0,
		"chosen_score": float(chosen.get("score", 0.0)) if not chosen.is_empty() else 0.0,
		"chosen_cell": chosen_cell,
		"rejected_reason_distribution": rejected.duplicate(true),
		"policy_weight": session.agent_weight(agent_id, "road"),
	})


func _count_reject(rejected: Dictionary, reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
