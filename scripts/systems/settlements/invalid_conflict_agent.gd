class_name InvalidConflictAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "invalid_conflict_agent"


func is_active(session) -> bool:
	return session.current_phase == "validation" and not session.blueprint.buildings.is_empty()


func propose(session) -> Array[PlanProposal]:
	var existing: Dictionary = session.blueprint.buildings[0] as Dictionary
	var area: Dictionary = (existing.get("area", {}) as Dictionary).duplicate(true)
	var proposal := PlanProposal.create(agent_id, "add_building", session.current_phase, "Submit an intentionally conflicting building footprint.", 999)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.area = area
	proposal.affected_cells = _area_cells(area)
	proposal.payload = {
		"id": "invalid_overlapping_building",
		"kind": "invalid_overlap",
		"plot_id": str(existing.get("plot_id", "")),
		"entrance_cell": proposal.affected_cells[0] if not proposal.affected_cells.is_empty() else Vector2i.ZERO,
	}
	proposal.tags = ["invalid", "conflict", "v62"]
	return [proposal]


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := int(area.get("x", 0))
	var y0 := int(area.get("y", 0))
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			result.append(Vector2i(x, y))
	return result
