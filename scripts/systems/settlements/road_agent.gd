class_name RoadAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "road_agent"


func is_active(session) -> bool:
	return session.current_phase == "road" and not session.blueprint.cores.is_empty() and session.blueprint.roads.is_empty()


func propose(session) -> Array[PlanProposal]:
	var proposals: Array[PlanProposal] = []
	var core_cell: Vector2i = _cell_from_dict((session.blueprint.cores[0] as Dictionary).get("cell", {}) as Dictionary)
	var entrance: Vector2i = session.context.entrances[0] if not session.context.entrances.is_empty() else Vector2i(0, core_cell.y)
	var main_path: Array[Vector2i] = _build_manhattan_path(entrance, core_cell)
	proposals.append(_road_proposal(session, "main_approach_road", "approach", main_path, 90))

	var branch_direction: Vector2i = Vector2i.RIGHT if session.randi_range(0, 1, "road_branch_axis") == 0 else Vector2i.DOWN
	var branch_length: int = session.randi_range(4, 6, "road_branch_length")
	var branch_path: Array[Vector2i] = _build_branch(core_cell, branch_direction, branch_length, session.context.map_size)
	if branch_path.size() >= 3:
		proposals.append(_road_proposal(session, "secondary_branch_road", "branch", branch_path, 70))
	return proposals


func score(proposal: PlanProposal, _session) -> float:
	return float(proposal.priority) - float(proposal.path.size()) * 0.05


func _road_proposal(session, road_id: String, kind: String, path: Array[Vector2i], priority: int) -> PlanProposal:
	var proposal: PlanProposal = PlanProposal.create(agent_id, "add_road", session.current_phase, "Add a %s road that improves settlement access." % kind, priority)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.path = path
	proposal.affected_cells = path.duplicate()
	proposal.payload = { "id": road_id, "kind": kind }
	proposal.tags = ["road", kind, "v62"]
	return proposal


func _build_manhattan_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cursor: Vector2i = from_cell
	result.append(cursor)
	var x_step: int = 1 if to_cell.x >= cursor.x else -1
	while cursor.x != to_cell.x:
		cursor.x += x_step
		result.append(cursor)
	var y_step: int = 1 if to_cell.y >= cursor.y else -1
	while cursor.y != to_cell.y:
		cursor.y += y_step
		result.append(cursor)
	return result


func _build_branch(from_cell: Vector2i, direction: Vector2i, length: int, map_size: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cursor: Vector2i = from_cell
	result.append(cursor)
	for _step in range(length):
		cursor += direction
		if cursor.x < 1 or cursor.y < 1 or cursor.x >= map_size.x - 1 or cursor.y >= map_size.y - 1:
			break
		result.append(cursor)
	return result


func _cell_from_dict(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
