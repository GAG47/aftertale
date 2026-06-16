extends RefCounted

var _root: Node


func run(root: Node) -> bool:
	_root = root
	var first := _run_session()
	var second := _run_session()
	if str(first.get("session_summary", {}).get("result_signature", "")) != str(second.get("session_summary", {}).get("result_signature", "")):
		return _fail("v61 session must be deterministic for a fixed seed")

	var blueprint: Dictionary = first.get("blueprint", {}) as Dictionary
	var feature_maps: Dictionary = first.get("feature_maps", {}) as Dictionary
	var trace: Dictionary = first.get("trace", {}) as Dictionary
	var trace_summary: Dictionary = trace.get("summary", {}) as Dictionary

	if (blueprint.get("cores", []) as Array).is_empty():
		return _fail("v61 session must commit a core proposal")
	if (blueprint.get("roads", []) as Array).is_empty():
		return _fail("v61 session must commit a normal approach proposal")
	if int(trace_summary.get("rejected_count", 0)) < 1:
		return _fail("v61 session must reject the invalid proposal agent")
	if int(feature_maps.get("update_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v61 feature maps must update after each commit")
	if int(trace_summary.get("evaluator_report_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v61 evaluator must report after each commit")
	if int(trace_summary.get("random_decision_count", 0)) <= 0:
		return _fail("v61 trace must record random decisions")

	if not _agents_are_proposal_only():
		return false
	if not _resolver_is_only_commit_entry():
		return false
	if not _debug_view_renders(first):
		return false

	print("v61 settlement planning smoke test passed")
	return true


func _run_session() -> Dictionary:
	var policy := SettlementPolicy.from_dictionary({
		"settlement_type": "v61_debug_settlement",
		"scale": "village",
		"seed_override": 6117,
	})
	var context := SettlementContext.from_dictionary({
		"map_size": { "width": 16, "height": 12 },
		"entrances": [{ "x": 0, "y": 6 }],
		"existing_obstacles": [{ "x": 3, "y": 2 }, { "x": 4, "y": 2 }],
		"existing_water": [{ "x": 14, "y": 2 }],
		"important_world_points": [{ "x": 12, "y": 7 }],
		"world_seed": 6117,
	})
	var session := SettlementGenerationSession.new(policy, context)
	return session.run()


func _agents_are_proposal_only() -> bool:
	var policy := SettlementPolicy.from_dictionary({ "seed_override": 6117 })
	var context := SettlementContext.from_dictionary({
		"map_size": { "width": 16, "height": 12 },
		"entrances": [{ "x": 0, "y": 6 }],
	})
	var session := SettlementGenerationSession.new(policy, context)
	session.feature_maps.initialize(context)
	session.current_phase = "core"
	var agent := CoreSeedAgent.new()
	var before := session.blueprint.to_dictionary()
	var proposals := agent.propose(session)
	var after := session.blueprint.to_dictionary()
	if JSON.stringify(before) != JSON.stringify(after):
		return _fail("v61 agents must not directly mutate blueprint")
	if proposals.is_empty():
		return _fail("v61 normal agent must submit proposals")
	return true


func _resolver_is_only_commit_entry() -> bool:
	var blueprint := SettlementBlueprint.new()
	var proposal := PlanProposal.create("test", "add_core", "core", "Direct write should fail.", 1)
	proposal.proposal_id = "direct_write"
	proposal.affected_cells = [Vector2i(4, 4)]
	proposal.payload = { "id": "direct_core", "cell": Vector2i(4, 4) }
	if blueprint.apply_committed_proposal(proposal, "wrong_token"):
		return _fail("v61 blueprint must reject direct commits without resolver token")
	if not blueprint.cores.is_empty():
		return _fail("v61 failed direct commit must not change blueprint")
	return true


func _debug_view_renders(result: Dictionary) -> bool:
	var view := SettlementDebugView.new()
	_root.add_child(view)
	view.configure(result)
	var summary := view.get_debug_summary()
	if not bool(summary.get("has_blueprint_panel", false)):
		return _fail("v61 debug view must show blueprint panel")
	if not bool(summary.get("has_proposal_panel", false)):
		return _fail("v61 debug view must show proposal panel")
	if not bool(summary.get("has_feature_map_panel", false)):
		return _fail("v61 debug view must show feature map panel")
	if not bool(summary.get("has_evaluator_panel", false)):
		return _fail("v61 debug view must show evaluator panel")
	if not bool(summary.get("has_trace_panel", false)):
		return _fail("v61 debug view must show trace panel")
	if int(summary.get("feature_cell_count", 0)) <= 0:
		return _fail("v61 debug view must render feature cells")
	_root.remove_child(view)
	view.free()
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
