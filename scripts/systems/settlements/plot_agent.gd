class_name PlotAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "plot_agent"


func is_active(session) -> bool:
	return session.current_phase == "plot" and not session.blueprint.roads.is_empty() and session.blueprint.plots.is_empty()


func propose(session) -> Array[PlanProposal]:
	var proposals: Array[PlanProposal] = []
	var reserved: Dictionary = {}
	var road_cells := _road_cells(session)
	var road_lookup := _cell_lookup(road_cells)
	var plot_index := 0
	for road_cell in road_cells:
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT]:
			if proposals.size() >= 6:
				return proposals
			var area := _candidate_area(road_cell, direction)
			if _area_is_usable(area, session, reserved, road_lookup):
				_mark_reserved(area, reserved)
				var access_cell: Vector2i = road_cell
				var proposal := PlanProposal.create(agent_id, "add_plot", session.current_phase, "Reserve a buildable plot with road access.", 60 - plot_index)
				proposal.proposal_id = session.next_proposal_id(agent_id)
				proposal.area = area
				proposal.affected_cells = _area_cells(area)
				proposal.payload = {
					"id": "plot_%02d" % plot_index,
					"kind": "mixed_use",
					"road_access_cell": access_cell,
				}
				proposal.tags = ["plot", "road_access", "v62"]
				proposals.append(proposal)
				plot_index += 1
	return proposals


func score(proposal: PlanProposal, session) -> float:
	var access_cell := _cell_from_variant(proposal.payload.get("road_access_cell", Vector2i.ZERO))
	var entrance_distance: float = session.feature_maps.get_value("entrance_distance", access_cell, 99.0)
	return float(proposal.priority) - entrance_distance * 0.05


func _candidate_area(road_cell: Vector2i, direction: Vector2i) -> Dictionary:
	if direction == Vector2i.UP:
		return { "x": road_cell.x - 1, "y": road_cell.y - 2, "width": 3, "height": 2 }
	if direction == Vector2i.DOWN:
		return { "x": road_cell.x - 1, "y": road_cell.y + 1, "width": 3, "height": 2 }
	if direction == Vector2i.LEFT:
		return { "x": road_cell.x - 2, "y": road_cell.y - 1, "width": 2, "height": 3 }
	return { "x": road_cell.x + 1, "y": road_cell.y - 1, "width": 2, "height": 3 }


func _area_is_usable(area: Dictionary, session, reserved: Dictionary, road_lookup: Dictionary) -> bool:
	for cell in _area_cells(area):
		if not session.context.in_bounds(cell):
			return false
		if not session.feature_maps.is_buildable(cell):
			return false
		var key := FeatureMapStore.cell_key(cell)
		if reserved.has(key) or road_lookup.has(key):
			return false
	return true


func _mark_reserved(area: Dictionary, reserved: Dictionary) -> void:
	for cell in _area_cells(area):
		reserved[FeatureMapStore.cell_key(cell)] = true


func _road_cells(session) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			var key := FeatureMapStore.cell_key(cell)
			if not seen.has(key):
				seen[key] = true
				result.append(cell)
	return result


func _cell_lookup(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell in cells:
		result[FeatureMapStore.cell_key(cell)] = true
	return result


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


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
