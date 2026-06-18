class_name BuildingFootprintAgent
extends SettlementAgent


func _init() -> void:
	agent_id = "building_footprint_agent"
	spec = AgentSpecScript.create(8, 1, 5)


func is_active(session) -> bool:
	if session.blueprint.buildings.size() >= max(3, int(floor(float(session.blueprint.plots.size()) * session.building_fill_ratio()))):
		return false
	return _plots_without_buildings(session).size() > 0


func propose(session) -> Array[PlanProposal]:
	var candidates: Array[Dictionary] = []
	var rejected := {}
	for plot in _plots_without_buildings(session):
		candidates.append_array(_footprint_candidates(plot, session, rejected))
	var sample_count: int = session.candidate_sample_count(candidates.size(), 8)
	var best := _best_sample(candidates, session, sample_count)
	_record_search(session, candidates, best, rejected)
	if best.is_empty():
		return []
	var area: Dictionary = best.get("area", {}) as Dictionary
	var plot: Dictionary = best.get("plot", {}) as Dictionary
	var use := str(plot.get("use", "residential"))
	var building_type: String = session.building_type_for_use(use)
	var gameplay_hooks: Dictionary = _gameplay_hooks(building_type, use, best, session)
	var proposal := PlanProposal.create(agent_id, "add_building_footprint", session.current_step, "footprint", "Choose a footprint inside a differentiated plot with road-facing entrance space.", 50)
	proposal.proposal_id = session.next_proposal_id(agent_id)
	proposal.area = area
	proposal.affected_cells = _area_cells(area)
	proposal.payload = {
		"id": "building_%02d" % session.blueprint.buildings.size(),
		"plot_id": str(plot.get("id", "")),
		"building_type": building_type,
		"use_type": use,
		"enterable": true,
		"entrance_cell": best.get("entrance_cell", Vector2i.ZERO),
		"front_access_cell": best.get("front_access_cell", Vector2i.ZERO),
		"footprint_size": { "width": int(area.get("width", 0)), "height": int(area.get("height", 0)) },
		"facing": str(best.get("facing", "")),
		"presentation_note": _presentation_note(use, area),
		"asset_family": session.asset_family_for_use(use),
		"interior_template_id": session.interior_template_for_building(building_type, use),
		"home_capacity": int(gameplay_hooks.get("home_capacity", 0)),
		"work_slots": int(gameplay_hooks.get("work_slots", 0)),
		"service_slots": int(gameplay_hooks.get("service_slots", 0)),
		"activity_slots": int(gameplay_hooks.get("activity_slots", 0)),
		"home_slot_anchor": str(gameplay_hooks.get("home_slot_anchor", "")),
		"work_slot_anchor": str(gameplay_hooks.get("work_slot_anchor", "")),
		"service_slot_anchor": str(gameplay_hooks.get("service_slot_anchor", "")),
		"activity_slot_anchor": str(gameplay_hooks.get("activity_slot_anchor", "")),
		"entrance_anchor": str(gameplay_hooks.get("entrance_anchor", "")),
		"interaction_anchor": str(gameplay_hooks.get("interaction_anchor", "")),
		"quest_anchor": str(gameplay_hooks.get("quest_anchor", "")),
	}
	var tags: Array[String] = ["building_footprint", use]
	proposal.tags = tags
	proposal.score = float(best.get("score", 0.0))
	var result: Array[PlanProposal] = []
	result.append(proposal)
	return result


func _plots_without_buildings(session) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var occupied_plot_ids: Dictionary = {}
	for building_value in session.blueprint.buildings:
		var building: Dictionary = building_value as Dictionary
		occupied_plot_ids[str(building.get("plot_id", ""))] = true
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) != "differentiated":
			continue
		if str(plot.get("use", "")) == "public":
			continue
		if session.current_step - int(plot.get("differentiated_step", session.current_step)) < 2:
			continue
		if occupied_plot_ids.has(str(plot.get("id", ""))):
			continue
		result.append(plot)
	return result


func _footprint_candidates(plot: Dictionary, session, rejected: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var plot_area: Dictionary = plot.get("area", {}) as Dictionary
	var road_cell := _cell_from_variant(plot.get("road_access_cell", {}))
	var facing := str(plot.get("facing", "down"))
	var sizes := _formal_building_sizes(str(plot.get("use", "residential")))
	for size in sizes:
		var area := _setback_area(plot_area, facing, size)
		if area.is_empty():
			_count_reject(rejected, "footprint_too_small")
			continue
		var entrance := _entrance_for(area, facing)
		if not _plot_contains(plot_area, entrance):
			_count_reject(rejected, "entrance_outside_plot")
			continue
		var score: float = float(size.x * size.y)
		score += session.feature_maps.get_value("land_value", entrance, 0.0)
		score -= entrance.distance_to(road_cell) * 0.2
		if bool(session.evaluation_feedback.get("need_more_footprints", false)):
			score += 2.0
		score *= session.agent_weight(agent_id, "footprint")
		result.append({
			"plot": plot,
			"area": area,
			"entrance_cell": entrance,
			"front_access_cell": road_cell,
			"facing": facing,
			"score": score,
		})
	return result


func _setback_area(plot_area: Dictionary, facing: String, size: Vector2i) -> Dictionary:
	var x := int(plot_area.get("x", 0))
	var y := int(plot_area.get("y", 0))
	var width := int(plot_area.get("width", 0))
	var height := int(plot_area.get("height", 0))
	if width <= 0 or height <= 0:
		return {}
	if size.x > width or size.y > height:
		return {}
	if facing in ["up", "down"] and size.y >= height:
		return {}
	if facing in ["left", "right"] and size.x >= width:
		return {}
	match facing:
		"up":
			return { "x": x + max(0, int((width - size.x) / 2)), "y": y + 1, "width": size.x, "height": size.y }
		"down":
			return { "x": x + max(0, int((width - size.x) / 2)), "y": y + height - 1 - size.y, "width": size.x, "height": size.y }
		"left":
			return { "x": x + 1, "y": y + max(0, int((height - size.y) / 2)), "width": size.x, "height": size.y }
		_:
			return { "x": x + width - 1 - size.x, "y": y + max(0, int((height - size.y) / 2)), "width": size.x, "height": size.y }


func _entrance_for(area: Dictionary, facing: String) -> Vector2i:
	var x := int(area.get("x", 0))
	var y := int(area.get("y", 0))
	var width := int(area.get("width", 1))
	var height := int(area.get("height", 1))
	match facing:
		"up":
			return Vector2i(x + int(width / 2), y - 1)
		"down":
			return Vector2i(x + int(width / 2), y + height)
		"left":
			return Vector2i(x - 1, y + int(height / 2))
		_:
			return Vector2i(x + width, y + int(height / 2))


func _best_sample(candidates: Array[Dictionary], session, sample_count: int) -> Dictionary:
	var best: Dictionary = {}
	var pool := candidates.duplicate()
	var pulls: int = min(sample_count, pool.size())
	for _i in range(pulls):
		var index: int = session.randi_range(0, pool.size() - 1, "footprint_candidate_sample")
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
		var entrance: Vector2i = chosen.get("entrance_cell", Vector2i(-9999, -9999)) as Vector2i
		chosen_cell = { "x": entrance.x, "y": entrance.y }
	session.trace.record_agent_search(session.current_step, agent_id, {
		"valid_candidates_count": candidates.size(),
		"sampled_candidates_count": session.candidate_sample_count(candidates.size(), 8),
		"top_score": top_score if not candidates.is_empty() else 0.0,
		"chosen_score": float(chosen.get("score", 0.0)) if not chosen.is_empty() else 0.0,
		"chosen_cell": chosen_cell,
		"rejected_reason_distribution": rejected.duplicate(true),
		"policy_weight": session.agent_weight(agent_id, "footprint"),
	})


func _count_reject(rejected: Dictionary, reason: String) -> void:
	rejected[reason] = int(rejected.get(reason, 0)) + 1


func _presentation_note(use: String, area: Dictionary) -> String:
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	if use in ["residential", "commercial", "production"] and not _is_formal_building_size(Vector2i(width, height)):
		return "rejected_enterable_reason:footprint_too_small"
	return ""


func _gameplay_hooks(building_type: String, use: String, candidate: Dictionary, session) -> Dictionary:
	var index: int = session.blueprint.buildings.size()
	var prefix: String = "building_%02d" % index
	var result := {
		"interaction_anchor": "interaction_%s" % prefix,
		"entrance_anchor": "entrance_%s" % prefix,
		"quest_anchor": "",
		"home_slot_anchor": "",
		"work_slot_anchor": "",
		"service_slot_anchor": "",
		"activity_slot_anchor": "",
		"home_capacity": 0,
		"work_slots": 0,
		"service_slots": 0,
		"activity_slots": 1,
	}
	match use:
		"residential":
			result["home_slot_anchor"] = "home_slot_%s" % prefix
			result["home_capacity"] = 2
		"commercial":
			result["work_slot_anchor"] = "work_slot_%s" % prefix
			result["service_slot_anchor"] = "service_slot_%s" % prefix
			result["quest_anchor"] = "quest_%s" % prefix
			result["work_slots"] = 1
			result["service_slots"] = 1
		"production":
			result["work_slot_anchor"] = "work_slot_%s" % prefix
			result["work_slots"] = 2
		_:
			pass
	var required_shop := bool(session.hook_rule("require_shop_for_commercial", true))
	if use == "commercial" and not required_shop:
		result["service_slot_anchor"] = ""
		result["service_slots"] = 0
	return result


func _formal_building_sizes(use: String) -> Array[Vector2i]:
	match use:
		"commercial":
			return [Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 3)]
		"production":
			return [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]
		_:
			return [Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3), Vector2i(2, 4), Vector2i(4, 2)]


func _is_formal_building_size(size: Vector2i) -> bool:
	return (size.x >= 2 and size.y >= 3) or (size.x >= 3 and size.y >= 2)


func _plot_contains(area: Dictionary, cell: Vector2i) -> bool:
	var x := int(area.get("x", 0))
	var y := int(area.get("y", 0))
	var width := int(area.get("width", 0))
	var height := int(area.get("height", 0))
	return cell.x >= x and cell.y >= y and cell.x < x + width and cell.y < y + height


func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(int(area.get("y", 0)), int(area.get("y", 0)) + int(area.get("height", 0))):
		for x in range(int(area.get("x", 0)), int(area.get("x", 0)) + int(area.get("width", 0))):
			result.append(Vector2i(x, y))
	return result


func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
