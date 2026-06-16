class_name LandmarkAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "landmark_agent"


func is_active(session) -> bool:
	return session.current_phase == "landmark" and not session.blueprint.cores.is_empty() and session.blueprint.landmarks.is_empty()


func propose(session) -> Array[PlanProposal]:
	var core_cell := _cell_from_dict((session.blueprint.cores[0] as Dictionary).get("cell", {}) as Dictionary)
	var candidate := _find_candidate(core_cell, session)
	var proposal := PlanProposal.create(agent_id, "add_landmark", session.current_phase, "Add a central landmark near the core and road network.", 75)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.affected_cells = [candidate]
	proposal.payload = { "id": "central_well", "kind": "well", "cell": candidate }
	proposal.tags = ["landmark", "core_area", "v62"]
	return [proposal]


func score(proposal: PlanProposal, session) -> float:
	var cell := proposal.primary_cell()
	var center_distance: float = session.feature_maps.get_value("center_distance", cell, 99.0)
	return float(proposal.priority) - center_distance * 0.05


func _find_candidate(core_cell: Vector2i, session) -> Vector2i:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i(1, 1), Vector2i(-1, 1)]:
		var cell: Vector2i = core_cell + direction
		if session.context.in_bounds(cell) and session.feature_maps.is_buildable(cell):
			return cell
	return core_cell


func _cell_from_dict(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
