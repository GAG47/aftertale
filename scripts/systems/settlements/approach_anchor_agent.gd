class_name ApproachAnchorAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "approach_anchor_agent"


func is_active(session) -> bool:
	return session.current_phase == "approach" and not session.blueprint.cores.is_empty()


func propose(session) -> Array[PlanProposal]:
	var core_cell := _cell_from_dict((session.blueprint.cores[0] as Dictionary).get("cell", {}) as Dictionary)
	var entrance: Vector2i = session.context.entrances[0] if not session.context.entrances.is_empty() else Vector2i(0, core_cell.y)
	var path: Array[Vector2i] = _build_manhattan_path(entrance, core_cell)

	var path_proposal := PlanProposal.create(agent_id, "add_path", session.current_phase, "Connect the entrance to the first core.", 80)
	path_proposal.proposal_id = session.next_proposal_id(agent_id)
	path_proposal.path = path
	path_proposal.affected_cells = path.duplicate()
	path_proposal.payload = { "id": "approach_path", "kind": "debug_approach" }
	path_proposal.tags = ["road", "approach", "v61_debug"]

	var anchor_cell := path[min(path.size() - 1, max(0, path.size() / 2))]
	var anchor_proposal := PlanProposal.create(agent_id, "add_anchor", session.current_phase, "Add a debug approach anchor along the committed path.", 70)
	anchor_proposal.proposal_id = session.next_proposal_id(agent_id)
	anchor_proposal.affected_cells = [anchor_cell]
	anchor_proposal.payload = { "id": "approach_anchor", "kind": "debug_anchor", "cell": anchor_cell }
	anchor_proposal.tags = ["anchor", "approach", "v61_debug"]
	return [path_proposal, anchor_proposal]


func score(proposal: PlanProposal, _session: SettlementGenerationSession) -> float:
	return float(proposal.priority) - float(proposal.path.size()) * 0.1


func _build_manhattan_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cursor := from_cell
	result.append(cursor)
	var x_step := 1 if to_cell.x >= cursor.x else -1
	while cursor.x != to_cell.x:
		cursor.x += x_step
		result.append(cursor)
	var y_step := 1 if to_cell.y >= cursor.y else -1
	while cursor.y != to_cell.y:
		cursor.y += y_step
		result.append(cursor)
	return result


func _cell_from_dict(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
