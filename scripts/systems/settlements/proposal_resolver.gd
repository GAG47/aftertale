class_name ProposalResolver
extends RefCounted

const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")


func resolve_step(candidates: Array[PlanProposal], session) -> Array[PlanProposal]:
	var valid: Array[PlanProposal] = []
	var losers: Array[Dictionary] = []
	for proposal in candidates:
		session.trace.record_proposal(proposal)
		var errors := validate(proposal, session)
		if not errors.is_empty():
			proposal.status = PlanProposal.STATUS_REJECTED
			proposal.validation_notes = errors
			session.trace.record_rejected(proposal, errors)
			losers.append(_loser_row(proposal, "validation_failed", errors, "", _conflict_keys(proposal)))
			continue
		valid.append(proposal)

	valid.sort_custom(func(a: PlanProposal, b: PlanProposal) -> bool:
		if a.score == b.score:
			return a.priority > b.priority
		return a.score > b.score
	)

	var winners: Array[PlanProposal] = []
	var claimed: Dictionary = {}
	var family_counts: Dictionary = {}
	var family_winners: Dictionary = {}
	for proposal in valid:
		var conflict_keys := _conflict_keys(proposal)
		var conflict_with := _first_claimed(conflict_keys, claimed)
		if not conflict_with.is_empty():
			proposal.status = PlanProposal.STATUS_SUPERSEDED
			var notes: Array[String] = ["lost_step_conflict:%s" % conflict_with]
			proposal.validation_notes = notes
			session.trace.record_rejected(proposal, notes)
			losers.append(_loser_row(proposal, "lost_conflict", notes, conflict_with, conflict_keys))
			continue
		var family_group := _family_group(proposal)
		var family_count := int(family_counts.get(family_group, 0))
		if family_count >= _family_capacity(family_group):
			proposal.status = PlanProposal.STATUS_SUPERSEDED
			var winner_id := str(family_winners.get(family_group, family_group))
			var notes: Array[String] = ["lost_family_capacity:%s" % family_group]
			proposal.validation_notes = notes
			session.trace.record_rejected(proposal, notes)
			losers.append(_loser_row(proposal, "family_capacity", notes, winner_id, conflict_keys))
			continue
		winners.append(proposal)
		family_counts[family_group] = family_count + 1
		family_winners[family_group] = proposal.proposal_id
		for key in conflict_keys:
			claimed[key] = proposal.proposal_id

	var committed: Array[PlanProposal] = []
	for proposal in winners:
		if validate(proposal, session).is_empty():
			proposal.status = PlanProposal.STATUS_ACCEPTED
			session.trace.record_accepted(proposal)
			if commit(proposal, session):
				committed.append(proposal)
				var committed_single: Array[PlanProposal] = []
				committed_single.append(proposal)
				var report: Dictionary = session.evaluator.evaluate_step(session, committed_single)
				session.trace.record_evaluator_report(report)
				session.evaluation_feedback = (report.get("feedback", {}) as Dictionary).duplicate(true)
				session.demand_ledger.update_from_session(session, session.evaluation_feedback)
		else:
			proposal.status = PlanProposal.STATUS_REJECTED
			var notes: Array[String] = ["failed_still_valid_check"]
			proposal.validation_notes = notes
			session.trace.record_rejected(proposal, notes)
			losers.append(_loser_row(proposal, "failed_still_valid_check", notes, "", _conflict_keys(proposal)))

	session.trace.record_step_resolution(session.current_step, committed, losers)
	return committed


func process_proposal(proposal: PlanProposal, session, _agent: SettlementAgent) -> bool:
	var proposals: Array[PlanProposal] = []
	proposals.append(proposal)
	return not resolve_step(proposals, session).is_empty()


func validate(proposal: PlanProposal, session) -> Array[String]:
	var errors: Array[String] = []
	if proposal.reason.strip_edges().is_empty():
		errors.append("missing_reason")
	if proposal.step != session.current_step:
		errors.append("step_mismatch:%d!=%d" % [proposal.step, session.current_step])
	if proposal.stage not in ["blueprint_growth", "differentiation", "footprint"]:
		errors.append("unsupported_stage")
	if proposal.type not in ["add_core_seed", "add_road_segment", "add_generic_plot", "differentiate_plot", "add_building_footprint"]:
		errors.append("unsupported_type")

	match proposal.type:
		"add_core_seed":
			_validate_cell(proposal.primary_cell(), session, errors)
		"add_road_segment":
			if proposal.path.is_empty():
				errors.append("empty_road_segment")
			for cell in proposal.path:
				_validate_cell(cell, session, errors)
				if session.feature_maps.is_road(cell):
					errors.append("road_segment_overlaps_road:%s" % str(cell))
				if session.feature_maps.get_value("plot", cell, 0.0) > 0.0:
					errors.append("road_segment_overlaps_plot:%s" % str(cell))
		"add_generic_plot":
			_validate_area(proposal.area, session, errors, true)
			if not _area_has_road_access(proposal.area, session):
				errors.append("generic_plot_missing_road_access")
			var road_access_cell := _cell_from_variant(proposal.payload.get("road_access_cell", Vector2i(-9999, -9999)))
			if not _cell_on_main_road(road_access_cell, session):
				errors.append("generic_plot_access_not_on_main_road:%s" % str(road_access_cell))
		"differentiate_plot":
			var plot_id := str(proposal.payload.get("plot_id", ""))
			var use := str(proposal.payload.get("use", ""))
			if plot_id.is_empty():
				errors.append("missing_plot_id")
			if use not in ["residential", "commercial", "production", "public"]:
				errors.append("unsupported_plot_use:%s" % use)
			if not _plot_has_status(plot_id, "generic", session):
				errors.append("plot_not_generic:%s" % plot_id)
			if not _plot_is_old_enough(plot_id, session, 2):
				errors.append("plot_not_mature_enough:%s" % plot_id)
			if not _plot_access_on_main_road(plot_id, session):
				errors.append("plot_access_not_on_main_road:%s" % plot_id)
		"add_building_footprint":
			_validate_area(proposal.area, session, errors, false)
			var plot_id := str(proposal.payload.get("plot_id", ""))
			if plot_id.is_empty():
				errors.append("building_missing_plot_id")
			elif not _plot_has_status(plot_id, "differentiated", session):
				errors.append("building_plot_not_differentiated:%s" % plot_id)
			elif not _plot_differentiation_is_old_enough(plot_id, session, 2):
				errors.append("building_plot_not_mature_enough:%s" % plot_id)
			elif _plot_use(plot_id, session) == "public":
				errors.append("building_not_allowed_on_public_plot:%s" % plot_id)
			elif not _area_inside_plot(proposal.area, plot_id, session):
				errors.append("building_area_outside_plot:%s" % plot_id)
			var entrance_cell := _cell_from_variant(proposal.payload.get("entrance_cell", Vector2i(-9999, -9999)))
			if not _plot_contains_cell(plot_id, entrance_cell, session):
				errors.append("building_entrance_outside_plot:%s" % str(entrance_cell))
			var front_access_cell := _cell_from_variant(proposal.payload.get("front_access_cell", Vector2i(-9999, -9999)))
			if not _cell_on_main_road(front_access_cell, session):
				errors.append("building_front_access_not_on_main_road:%s" % str(front_access_cell))
			if _area_fills_plot(proposal.area, plot_id, session):
				errors.append("building_fills_entire_plot:%s" % plot_id)
	return errors


func commit(proposal: PlanProposal, session) -> bool:
	var committed: bool = session.blueprint.apply_committed_proposal(proposal, SettlementBlueprint.COMMIT_TOKEN)
	if not committed:
		proposal.status = PlanProposal.STATUS_REJECTED
		var notes: Array[String] = ["blueprint_rejected_commit_token_or_type"]
		proposal.validation_notes = notes
		session.trace.record_rejected(proposal, proposal.validation_notes)
		return false
	proposal.status = PlanProposal.STATUS_COMMITTED
	session.committed_step += 1
	session.record_agent_commit(proposal.proposer_id)
	session.feature_maps.mark_committed(proposal)
	session.feature_maps.rebuild_from_blueprint(session.context, session.blueprint)
	session.trace.record_committed(proposal)
	return true


func _validate_cell(cell: Vector2i, session, errors: Array[String]) -> void:
	if not session.context.in_bounds(cell):
		errors.append("cell_out_of_bounds:%s" % str(cell))
		return
	if session.context.is_obstacle(cell):
		errors.append("cell_blocked_by_context:%s" % str(cell))
	if not session.feature_maps.is_buildable(cell):
		errors.append("cell_not_buildable:%s" % str(cell))


func _validate_area(area: Dictionary, session, errors: Array[String], reject_existing_plot: bool) -> void:
	if int(area.get("width", 0)) <= 0 or int(area.get("height", 0)) <= 0:
		errors.append("invalid_area_size")
		return
	for cell in _area_cells(area):
		_validate_cell(cell, session, errors)
		if session.feature_maps.is_road(cell):
			errors.append("area_overlaps_road:%s" % str(cell))
		if reject_existing_plot and session.feature_maps.get_value("plot", cell, 0.0) > 0.0:
			errors.append("area_overlaps_plot:%s" % str(cell))


func _area_has_road_access(area: Dictionary, session) -> bool:
	for cell in _area_cells(area):
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if session.feature_maps.is_road(cell + direction):
				return true
	return false


func _cell_on_main_road(cell: Vector2i, session) -> bool:
	var connectivity := RoadGraphScript.analyze_blueprint(session.blueprint.to_dictionary(), session.context.entrances, session.context.map_size)
	for cell_value in (connectivity.get("main_road_cells", []) as Array):
		var main_cell := _cell_from_variant(cell_value)
		if main_cell == cell:
			return true
	return false


func _plot_access_on_main_road(plot_id: String, session) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) != plot_id:
			continue
		return _cell_on_main_road(_cell_from_variant(plot.get("road_access_cell", {})), session)
	return false


func _plot_has_status(plot_id: String, status: String, session) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			return str(plot.get("status", "")) == status
	return false


func _plot_use(plot_id: String, session) -> String:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			return str(plot.get("use", ""))
	return ""


func _plot_is_old_enough(plot_id: String, session, minimum_age: int) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			return session.current_step - int(plot.get("step", session.current_step)) >= minimum_age
	return false


func _plot_differentiation_is_old_enough(plot_id: String, session, minimum_age: int) -> bool:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			return session.current_step - int(plot.get("differentiated_step", session.current_step)) >= minimum_age
	return false


func _area_inside_plot(area: Dictionary, plot_id: String, session) -> bool:
	var plot_area := _plot_area(plot_id, session)
	if plot_area.is_empty():
		return false
	for cell in _area_cells(area):
		if not _area_contains_cell(plot_area, cell):
			return false
	return true


func _plot_contains_cell(plot_id: String, cell: Vector2i, session) -> bool:
	var plot_area := _plot_area(plot_id, session)
	return not plot_area.is_empty() and _area_contains_cell(plot_area, cell)


func _area_fills_plot(area: Dictionary, plot_id: String, session) -> bool:
	var plot_area := _plot_area(plot_id, session)
	return int(area.get("width", 0)) * int(area.get("height", 0)) >= int(plot_area.get("width", 0)) * int(plot_area.get("height", 0))


func _plot_area(plot_id: String, session) -> Dictionary:
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("id", "")) == plot_id:
			return plot.get("area", {}) as Dictionary
	return {}


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(int(area.get("y", 0)), int(area.get("y", 0)) + int(area.get("height", 0))):
		for x in range(int(area.get("x", 0)), int(area.get("x", 0)) + int(area.get("width", 0))):
			result.append(Vector2i(x, y))
	return result


func _area_contains_cell(area: Dictionary, cell: Vector2i) -> bool:
	var x := int(area.get("x", 0))
	var y := int(area.get("y", 0))
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	return cell.x >= x and cell.y >= y and cell.x < x + width and cell.y < y + height


func _conflict_keys(proposal: PlanProposal) -> Array[String]:
	var keys: Array[String] = []
	for conflict in proposal.conflicts:
		keys.append("conflict:%s" % conflict)
	for cell in proposal.affected_cells:
		keys.append("cell:%s" % FeatureMapStore.cell_key(cell))
	return keys


func _first_claimed(keys: Array[String], claimed: Dictionary) -> String:
	for key in keys:
		if claimed.has(key):
			return str(claimed[key])
	return ""


func _loser_row(proposal: PlanProposal, reason: String, notes: Array[String], winner_key: String, conflict_keys: Array[String]) -> Dictionary:
	return {
		"proposal": proposal.duplicate_for_trace(),
		"reason": reason,
		"winner_key": winner_key,
		"notes": notes.duplicate(),
		"score": proposal.score,
		"priority": proposal.priority,
		"conflict_keys": conflict_keys.duplicate(),
		"family_group": _family_group(proposal),
	}


func _family_group(proposal: PlanProposal) -> String:
	match proposal.type:
		"add_core_seed":
			return "core_group"
		"add_road_segment":
			return "road_group"
		"add_generic_plot":
			return "plot_group"
		"differentiate_plot":
			if str(proposal.payload.get("use", "")) == "public":
				return "public_group"
			return "differentiation_group"
		"add_building_footprint":
			return "footprint_group"
		_:
			return "unknown_group"


func _family_capacity(family_group: String) -> int:
	match family_group:
		"road_group":
			return 1
		"plot_group":
			return 1
		"differentiation_group":
			return 1
		"footprint_group":
			return 1
		"public_group":
			return 1
		"core_group":
			return 1
		_:
			return 1


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
