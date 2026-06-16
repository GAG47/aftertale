class_name ProposalResolver
extends RefCounted


func process_proposal(proposal: PlanProposal, session, agent: SettlementAgent) -> bool:
	session.trace.record_proposal(proposal)
	proposal.score = agent.score(proposal, session)
	var errors := validate(proposal, session)
	if not errors.is_empty():
		proposal.status = PlanProposal.STATUS_REJECTED
		proposal.validation_notes = errors
		session.trace.record_rejected(proposal, errors)
		return false

	proposal.status = PlanProposal.STATUS_ACCEPTED
	session.trace.record_accepted(proposal)
	var committed := commit(proposal, session)
	if not committed:
		proposal.status = PlanProposal.STATUS_REJECTED
		proposal.validation_notes = ["blueprint_rejected_commit_token_or_type"]
		session.trace.record_rejected(proposal, proposal.validation_notes)
		return false
	return true


func validate(proposal: PlanProposal, session) -> Array[String]:
	var errors: Array[String] = []
	if proposal.reason.strip_edges().is_empty():
		errors.append("missing_reason")
	if proposal.type not in ["add_core", "add_anchor", "add_path", "add_road", "add_plot", "add_building", "add_landmark"]:
		errors.append("unsupported_type")

	match proposal.type:
		"add_core", "add_anchor":
			_validate_cell(proposal.primary_cell(), session, errors)
		"add_path", "add_road":
			if proposal.path.is_empty():
				errors.append("empty_path")
			for cell in proposal.path:
				_validate_cell(cell, session, errors, false)
		"add_plot":
			_validate_area(proposal.area, session, errors)
			if not _area_has_road_access(proposal.area, session):
				errors.append("plot_missing_road_access")
			if _area_overlaps_existing_plot(proposal.area, session):
				errors.append("plot_area_overlap")
		"add_building":
			_validate_area(proposal.area, session, errors)
			var plot_id := str(proposal.payload.get("plot_id", ""))
			if plot_id.is_empty():
				errors.append("building_missing_plot_id")
			elif not _area_inside_plot(proposal.area, plot_id, session):
				errors.append("building_area_outside_plot:%s" % plot_id)
			var entrance_cell := _cell_from_variant(proposal.payload.get("entrance_cell", proposal.primary_cell()))
			if not _area_contains_cell(proposal.area, entrance_cell):
				errors.append("building_entrance_outside_area:%s" % str(entrance_cell))
		"add_landmark":
			_validate_cell(proposal.primary_cell(), session, errors)
			if not _cell_near_road_or_core(proposal.primary_cell(), session):
				errors.append("landmark_not_near_road_or_core:%s" % str(proposal.primary_cell()))
	return errors


func commit(proposal: PlanProposal, session) -> bool:
	var committed: bool = session.blueprint.apply_committed_proposal(proposal, SettlementBlueprint.COMMIT_TOKEN)
	if not committed:
		return false
	session.feature_maps.apply_committed_proposal(proposal)
	proposal.status = PlanProposal.STATUS_COMMITTED
	session.committed_step += 1
	session.trace.record_committed(proposal)
	var report: Dictionary = session.evaluator.evaluate(session, proposal)
	session.trace.record_evaluator_report(report)
	return true


func _validate_cell(cell: Vector2i, session, errors: Array[String], require_unoccupied: bool = true) -> void:
	if not session.context.in_bounds(cell):
		errors.append("cell_out_of_bounds:%s" % str(cell))
		return
	if session.context.is_obstacle(cell):
		errors.append("cell_blocked_by_context:%s" % str(cell))
	if not session.feature_maps.is_buildable(cell) and require_unoccupied:
		errors.append("cell_not_buildable:%s" % str(cell))


func _validate_area(area: Dictionary, session, errors: Array[String]) -> void:
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	if width <= 0 or height <= 0:
		errors.append("invalid_area_size")
		return
	for cell in _area_cells(area):
		_validate_cell(cell, session, errors)
		if _cell_on_existing_road(cell, session):
			errors.append("area_overlaps_road:%s" % str(cell))


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


func _area_has_road_access(area: Dictionary, session) -> bool:
	for cell in _area_cells(area):
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if _cell_on_existing_road(cell + direction, session):
				return true
	return false


func _area_inside_plot(area: Dictionary, plot_id: String, session) -> bool:
	var plot_area: Dictionary = {}
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			plot_area = plot.get("area", {}) as Dictionary
			break
	if plot_area.is_empty():
		return false
	for cell in _area_cells(area):
		if not _area_contains_cell(plot_area, cell):
			return false
	return true


func _area_overlaps_existing_plot(area: Dictionary, session) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		var plot_area: Dictionary = plot.get("area", {}) as Dictionary
		for cell in _area_cells(area):
			if _area_contains_cell(plot_area, cell):
				return true
	return false


func _area_contains_cell(area: Dictionary, cell: Vector2i) -> bool:
	var x0 := int(area.get("x", 0))
	var y0 := int(area.get("y", 0))
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	return cell.x >= x0 and cell.y >= y0 and cell.x < x0 + width and cell.y < y0 + height


func _cell_on_existing_road(cell: Vector2i, session) -> bool:
	for road_value in session.blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var road_cell := _cell_from_variant(cell_value)
			if road_cell == cell:
				return true
	return false


func _cell_near_road_or_core(cell: Vector2i, session) -> bool:
	if _cell_on_existing_road(cell, session):
		return true
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if _cell_on_existing_road(cell + direction, session):
			return true
	for core_value in session.blueprint.cores:
		var core: Dictionary = core_value as Dictionary
		var core_cell := _cell_from_variant(core.get("cell", {}))
		if absi(core_cell.x - cell.x) + absi(core_cell.y - cell.y) <= 4:
			return true
	return false


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
