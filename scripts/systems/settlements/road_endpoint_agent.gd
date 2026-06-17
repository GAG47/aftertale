class_name RoadEndpointAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "road_endpoint_agent"
	spec = AgentSpecScript.create(1, 1, 10)


func is_active(session) -> bool:
	return not session.blueprint.roads.is_empty() or not session.blueprint.cores.is_empty()


func propose(session) -> Array[PlanProposal]:
	var rejected := {}
	var endpoints := _endpoint_rows(session)
	var candidates := _road_segment_candidates(session, endpoints, rejected)
	var sample_count: int = session.candidate_sample_count(candidates.size(), 8)
	var best := _best_sample(candidates, session, sample_count)
	_record_search(session, endpoints.size(), candidates, best, rejected)
	if best.is_empty():
		return []
	var result: Array[PlanProposal] = []
	result.append(_make_road_proposal(best, session))
	return result


func _endpoint_rows(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for endpoint_value in session.blueprint.road_endpoints:
		result.append((endpoint_value as Dictionary).duplicate(true))
	if result.is_empty():
		for core_value in session.blueprint.cores:
			var core: Dictionary = core_value as Dictionary
			result.append({
				"endpoint_id": "core_seed_endpoint",
				"origin_road_id": "core_seed",
				"cell": core.get("cell", {}),
				"direction_bias": { "x": -1, "y": 0 },
				"last_extended_step": -1,
				"failed_attempts": 0,
				"growth_intent": "seed",
			})
	if bool(session.evaluation_feedback.get("entrance_disconnected", false)):
		for index in range(session.context.entrances.size()):
			var entrance: Vector2i = session.context.entrances[index]
			result.append({
				"endpoint_id": "entrance_endpoint_%d" % index,
				"origin_road_id": "entrance",
				"cell": { "x": entrance.x, "y": entrance.y },
				"direction_bias": _dict_cell(_direction_toward_nearest_core(entrance, session)),
				"last_extended_step": -1,
				"failed_attempts": 0,
				"growth_intent": "connect_entrance",
			})
	return result


func _road_segment_candidates(session, endpoints: Array[Dictionary], rejected: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for endpoint in endpoints:
		var start := _cell_from_variant(endpoint.get("cell", {}))
		var directions := _candidate_directions(_cell_from_variant(endpoint.get("direction_bias", {})), start, session)
		for direction in directions:
			var length: int = session.randi_range(2, 3, "road_endpoint_length")
			var segment := _segment_from(start, direction, length, session)
			if not bool(segment.get("valid", false)):
				_count_reject(rejected, str(segment.get("reason", "invalid")))
				continue
			var path: Array[Vector2i] = segment.get("path", []) as Array[Vector2i]
			var end_cell: Vector2i = path[path.size() - 1]
			var score: float = session.feature_maps.get_value("edge_distance", end_cell, 0.0)
			score += session.feature_maps.get_value("land_value", end_cell, 0.0)
			score -= _nearby_road_count(path, session) * 0.7
			score -= int(endpoint.get("failed_attempts", 0)) * 0.2
			score -= max(0, session.current_step - int(endpoint.get("last_extended_step", session.current_step))) * 0.02
			score += _road_style_score(start, end_cell, direction, session)
			if session.demand_ledger.road_need > 0:
				score += float(session.demand_ledger.road_need) * 1.5
			if bool(session.evaluation_feedback.get("entrance_disconnected", false)):
				score += 14.0 / maxf(1.0, session.feature_maps.get_value("entrance_distance", end_cell, 99.0))
			if str(endpoint.get("growth_intent", "")) == "connect_entrance":
				score += 12.0 / maxf(1.0, float(_nearest_core_distance(end_cell, session)))
			score *= session.agent_weight(agent_id, "road")
			result.append({
				"endpoint": endpoint,
				"path": path,
				"score": score,
				"end_cell": end_cell,
			})
	return result


func _make_road_proposal(candidate: Dictionary, session) -> PlanProposal:
	var path: Array[Vector2i] = candidate.get("path", []) as Array[Vector2i]
	var endpoint: Dictionary = candidate.get("endpoint", {}) as Dictionary
	var proposal := PlanProposal.create(agent_id, "add_road_segment", session.current_step, "blueprint_growth", "Grow one road endpoint by sampled spatial utility.", 70)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.path = path
	proposal.affected_cells = path.duplicate()
	proposal.payload = {
		"id": "endpoint_%02d" % session.current_step,
		"kind": "endpoint_extend",
		"endpoint_id": str(endpoint.get("endpoint_id", "")),
		"origin_road_id": str(endpoint.get("origin_road_id", "")),
		"growth_intent": str(endpoint.get("growth_intent", "")),
	}
	var tags: Array[String] = ["road", "endpoint", "step_growth"]
	proposal.tags = tags
	proposal.score = float(candidate.get("score", 0.0))
	return proposal


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


func _candidate_directions(direction_bias: Vector2i, start: Vector2i, session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	_append_direction(result, direction_bias)
	_append_direction(result, Vector2i(-direction_bias.y, direction_bias.x))
	_append_direction(result, Vector2i(direction_bias.y, -direction_bias.x))
	if bool(session.evaluation_feedback.get("entrance_disconnected", false)):
		_append_direction(result, _direction_toward_nearest_core(start, session))
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		_append_direction(result, direction)
	return result


func _append_direction(result: Array[Vector2i], direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	if not result.has(direction):
		result.append(direction)


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
		var index: int = session.randi_range(0, pool.size() - 1, "road_endpoint_candidate_sample")
		var candidate: Dictionary = pool.pop_at(index) as Dictionary
		if best.is_empty() or float(candidate.get("score", -9999.0)) > float(best.get("score", -9999.0)):
			best = candidate
	return best


func _record_search(session, endpoint_count: int, candidates: Array[Dictionary], chosen: Dictionary, rejected: Dictionary) -> void:
	var top_score := -9999.0
	for candidate in candidates:
		top_score = maxf(top_score, float(candidate.get("score", -9999.0)))
	var chosen_cell := {}
	if not chosen.is_empty():
		var end_cell: Vector2i = chosen.get("end_cell", Vector2i(-9999, -9999)) as Vector2i
		chosen_cell = { "x": end_cell.x, "y": end_cell.y }
	session.trace.record_agent_search(session.current_step, agent_id, {
		"endpoints_count": endpoint_count,
		"valid_candidates_count": candidates.size(),
		"sampled_candidates_count": session.candidate_sample_count(candidates.size(), 8),
		"top_score": top_score if not candidates.is_empty() else 0.0,
		"chosen_score": float(chosen.get("score", 0.0)) if not chosen.is_empty() else 0.0,
		"chosen_cell": chosen_cell,
		"rejected_reason_distribution": rejected.duplicate(true),
		"road_style": session.policy.road_style,
		"policy_weight": session.agent_weight(agent_id, "road"),
	})


func _count_reject(rejected: Dictionary, reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


func _direction_toward_nearest_core(from_cell: Vector2i, session) -> Vector2i:
	var best_cell := from_cell + Vector2i.LEFT
	var best_distance := 999
	for core_value in session.blueprint.cores:
		var core: Dictionary = core_value as Dictionary
		var core_cell := _cell_from_variant(core.get("cell", {}))
		var distance := absi(from_cell.x - core_cell.x) + absi(from_cell.y - core_cell.y)
		if distance < best_distance:
			best_distance = distance
			best_cell = core_cell
	var delta := best_cell - from_cell
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(1 if delta.x >= 0 else -1, 0)
	return Vector2i(0, 1 if delta.y >= 0 else -1)


func _road_style_score(start: Vector2i, end_cell: Vector2i, direction: Vector2i, session) -> float:
	match session.policy.road_style:
		"linear", "roadside":
			var entrance_y: int = int(session.context.entrances[0].y) if not session.context.entrances.is_empty() else start.y
			var alignment: float = 6.0 / maxf(1.0, float(absi(end_cell.y - entrance_y) + 1))
			return alignment + (1.2 if direction.x != 0 else -0.4)
		"forest", "natural":
			return 0.8 if direction.y != 0 else 0.2
		"resource":
			return _resource_direction_score(end_cell, session)
		_:
			return 0.0


func _resource_direction_score(end_cell: Vector2i, session) -> float:
	var best := 99
	for point_value in session.context.important_world_points:
		var point: Vector2i = point_value as Vector2i
		best = min(best, absi(end_cell.x - point.x) + absi(end_cell.y - point.y))
	return 8.0 / maxf(1.0, float(best))


func _nearest_core_distance(cell: Vector2i, session) -> int:
	var best := 999
	for core_value in session.blueprint.cores:
		var core: Dictionary = core_value as Dictionary
		var core_cell := _cell_from_variant(core.get("cell", {}))
		best = min(best, absi(cell.x - core_cell.x) + absi(cell.y - core_cell.y))
	return best


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
