class_name BuildingAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "building_agent"


func is_active(session) -> bool:
	return session.current_phase == "building" and not session.blueprint.plots.is_empty() and session.blueprint.buildings.is_empty()


func propose(session) -> Array[PlanProposal]:
	var proposals: Array[PlanProposal] = []
	var building_index := 0
	for plot_value in session.blueprint.plots:
		if proposals.size() >= 4:
			return proposals
		var plot: Dictionary = plot_value as Dictionary
		var plot_area: Dictionary = plot.get("area", {}) as Dictionary
		var building_area := _building_area_inside(plot_area)
		if building_area.is_empty():
			continue
		var entrance_cell := _first_cell(building_area)
		var proposal := PlanProposal.create(agent_id, "add_building", session.current_phase, "Place a building footprint inside an accepted plot.", 50 - building_index)
		proposal.proposal_id = session.next_proposal_id(agent_id)
		proposal.area = building_area
		proposal.affected_cells = _area_cells(building_area)
		proposal.payload = {
			"id": "building_%02d" % building_index,
			"kind": "dwelling" if building_index > 0 else "common_house",
			"plot_id": str(plot.get("id", "")),
			"entrance_cell": entrance_cell,
		}
		proposal.tags = ["building", "footprint", "v62"]
		proposals.append(proposal)
		building_index += 1
	return proposals


func score(proposal: PlanProposal, _session) -> float:
	return float(proposal.priority) + float(proposal.affected_cells.size()) * 0.1


func _building_area_inside(plot_area: Dictionary) -> Dictionary:
	var width := int(plot_area.get("width", 0))
	var height := int(plot_area.get("height", 0))
	if width <= 1 or height <= 1:
		return {}
	return {
		"x": int(plot_area.get("x", 0)),
		"y": int(plot_area.get("y", 0)),
		"width": min(2, width),
		"height": min(2, height),
	}


func _first_cell(area: Dictionary) -> Vector2i:
	return Vector2i(int(area.get("x", 0)), int(area.get("y", 0)))


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
