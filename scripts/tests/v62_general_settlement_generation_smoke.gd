extends RefCounted

var _root: Node


func run(root: Node) -> bool:
	_root = root
	var first := _run_session()
	var second := _run_session()
	if str(first.get("session_summary", {}).get("result_signature", "")) != str(second.get("session_summary", {}).get("result_signature", "")):
		return _fail("v62 session must be deterministic for a fixed seed")

	var blueprint: Dictionary = first.get("blueprint", {}) as Dictionary
	var feature_maps: Dictionary = first.get("feature_maps", {}) as Dictionary
	var trace: Dictionary = first.get("trace", {}) as Dictionary
	var trace_summary: Dictionary = trace.get("summary", {}) as Dictionary

	if (blueprint.get("cores", []) as Array).size() < 1:
		return _fail("v62 must commit a settlement core")
	if (blueprint.get("roads", []) as Array).size() < 2:
		return _fail("v62 must commit general road proposals")
	if (blueprint.get("plots", []) as Array).size() < 4:
		return _fail("v62 must commit road-accessible plot proposals")
	if (blueprint.get("buildings", []) as Array).size() < 3:
		return _fail("v62 must commit building proposals")
	if (blueprint.get("landmarks", []) as Array).size() < 1:
		return _fail("v62 must commit a landmark proposal")
	if int(trace_summary.get("rejected_count", 0)) < 2:
		return _fail("v62 must reject out-of-bounds and conflicting proposals")
	if int(feature_maps.get("update_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v62 feature maps must update after each commit")
	if int(trace_summary.get("evaluator_report_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v62 evaluator must report after each commit")
	if not _trace_has_proposal_types(trace, ["add_road", "add_plot", "add_building", "add_landmark"]):
		return _fail("v62 trace must record all general proposal types")
	if not _trace_has_rejection_from(trace, "invalid_conflict_agent"):
		return _fail("v62 resolver must reject the intentionally conflicting proposal")
	if not _resolver_is_only_commit_entry():
		return false
	if not _debug_view_renders(first):
		return false

	print("v62 general settlement generation smoke test passed")
	return true


func _run_session() -> Dictionary:
	var policy := SettlementPolicy.from_dictionary({
		"settlement_type": "v62_general_settlement",
		"scale": "village",
		"density": 0.45,
		"seed_override": 6217,
	})
	var context := SettlementContext.from_dictionary({
		"map_size": { "width": 20, "height": 14 },
		"entrances": [{ "x": 0, "y": 7 }],
		"existing_obstacles": [{ "x": 5, "y": 2 }, { "x": 6, "y": 2 }, { "x": 16, "y": 10 }],
		"existing_water": [{ "x": 17, "y": 3 }, { "x": 18, "y": 3 }],
		"important_world_points": [{ "x": 14, "y": 8 }],
		"world_seed": 6217,
	})
	var session := SettlementGenerationSession.new(policy, context)
	return session.run()


func _trace_has_proposal_types(trace: Dictionary, types: Array[String]) -> bool:
	var seen: Dictionary = {}
	for proposal_value in (trace.get("proposals", []) as Array):
		var proposal: Dictionary = proposal_value as Dictionary
		seen[str(proposal.get("type", ""))] = true
	for type in types:
		if not seen.has(type):
			return false
	return true


func _trace_has_rejection_from(trace: Dictionary, proposer_id: String) -> bool:
	for proposal_value in (trace.get("rejected_proposals", []) as Array):
		var proposal: Dictionary = proposal_value as Dictionary
		if str(proposal.get("proposer_id", "")) == proposer_id:
			return true
	return false


func _resolver_is_only_commit_entry() -> bool:
	var blueprint := SettlementBlueprint.new()
	var proposal := PlanProposal.create("test", "add_landmark", "landmark", "Direct write should fail.", 1)
	proposal.proposal_id = "direct_landmark_write"
	proposal.affected_cells = [Vector2i(4, 4)]
	proposal.payload = { "id": "direct_landmark", "kind": "well", "cell": Vector2i(4, 4) }
	if blueprint.apply_committed_proposal(proposal, "wrong_token"):
		return _fail("v62 blueprint must reject direct commits without resolver token")
	if not blueprint.landmarks.is_empty():
		return _fail("v62 failed direct commit must not change blueprint")
	return true


func _debug_view_renders(result: Dictionary) -> bool:
	var view := SettlementDebugView.new()
	_root.add_child(view)
	view.configure(result)
	var summary := view.get_debug_summary()
	if int(summary.get("road_cell_count", 0)) <= 0:
		return _fail("v62 debug view must render roads")
	if int(summary.get("plot_cell_count", 0)) <= 0:
		return _fail("v62 debug view must render plots")
	if int(summary.get("building_cell_count", 0)) <= 0:
		return _fail("v62 debug view must render buildings")
	if int(summary.get("core_marker_count", 0)) <= 0:
		return _fail("v62 debug view must render core markers")
	if int(summary.get("landmark_marker_count", 0)) <= 0:
		return _fail("v62 debug view must render landmark markers")
	if int(summary.get("rejected_cell_count", 0)) <= 0:
		return _fail("v62 debug view must render rejected proposal cells")
	_root.remove_child(view)
	view.free()
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
