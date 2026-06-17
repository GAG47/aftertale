extends RefCounted

const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")
const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")

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
	if not _road_graph_is_connected_to_core(first):
		return _fail("v62 road graph must connect the entrance, main roads, and settlement core")
	if not _compiled_road_graph_is_connected(first):
		return _fail("v62 compiled road graph must preserve blueprint connectivity")
	if (blueprint.get("plots", []) as Array).size() < 4:
		return _fail("v62 must grow road-accessible generic plots")
	if (blueprint.get("buildings", []) as Array).size() < 3:
		return _fail("v62 must commit building footprint proposals")
	if not _has_differentiated_plots(blueprint):
		return _fail("v62 must differentiate generic plots")
	if _public_plot_count(blueprint) < 1:
		return _fail("v62 must produce at least one public plot")
	if (blueprint.get("plots", []) as Array).size() <= (blueprint.get("buildings", []) as Array).size():
		return _fail("v62 must leave some plots unbuilt or public instead of binding every plot 1:1 to a building")
	if (blueprint.get("interaction_anchors", []) as Array).size() < 5:
		return _fail("v62 must record semantic anchors")
	if int(trace_summary.get("rejected_count", 0)) < 2:
		return _fail("v62 must reject out-of-bounds and conflicting proposals")
	if int(feature_maps.get("update_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v62 feature maps must update after each commit")
	if int(trace_summary.get("evaluator_report_count", 0)) != int(trace_summary.get("committed_count", 0)):
		return _fail("v62 evaluator must report after each commit")
	if int(trace_summary.get("step_count", 0)) <= 0:
		return _fail("v62 trace must record generation steps")
	if not _trace_has_proposal_types(trace, ["add_road_segment", "add_generic_plot", "differentiate_plot", "add_building_footprint"]):
		return _fail("v62 trace must record road, generic plot, differentiation, and footprint proposals")
	if not _trace_has_rejection_from(trace, "invalid_conflict_agent"):
		return _fail("v62 resolver must reject the intentionally conflicting proposal")
	if not _step_resolutions_allow_parallel_family_growth(trace):
		return _fail("v62 resolver must allow parallel non-conflicting family growth while respecting family capacity")
	if not _trace_has_parallel_commits(trace):
		return _fail("v62 must show at least one generation step with multiple non-conflicting committed proposals")
	if not _plot_growth_is_delayed(blueprint):
		return _fail("v62 generic plots, differentiation, and footprints must be separated by later steps")
	if not _trace_has_agent_search_stats(trace):
		return _fail("v62 trace must expose agent candidate search, sampling, scoring, and rejection statistics")
	if not _trace_has_blueprint_replay_snapshots(trace):
		return _fail("v62 trace must record blueprint snapshots for step replay")
	if not _trace_has_differentiation_bids(trace):
		return _fail("v62 plot differentiation must record bidding details")
	if not _building_footprints_have_debug_details(blueprint):
		return _fail("v62 building footprints must expose plot, use, facing, entrance, front access, and size")
	if not _rejections_have_resolution_details(trace):
		return _fail("v62 rejected proposal rows must include reason, score, and conflict target data")
	if not _evaluator_reports_pressure(trace):
		return _fail("v62 evaluator reports must expose feedback pressure")
	if not _evaluator_reports_score_penalties(trace):
		return _fail("v62 evaluator reports must expose score penalties")
	if not _evaluator_reports_road_connectivity(trace):
		return _fail("v62 evaluator reports must expose road graph connectivity pressure")
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
		"map_size": { "width": 48, "height": 32 },
		"entrances": [{ "x": 0, "y": 16 }],
		"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }, { "x": 38, "y": 24 }],
		"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }, { "x": 43, "y": 8 }],
		"important_world_points": [{ "x": 36, "y": 20 }],
		"world_seed": 6217,
	})
	var session := SettlementGenerationSession.new(policy, context)
	session.max_blueprint_steps = 32
	return session.run()


func _trace_has_proposal_types(trace: Dictionary, types: Array) -> bool:
	var seen: Dictionary = {}
	for proposal_value in (trace.get("proposals", []) as Array):
		var proposal: Dictionary = proposal_value as Dictionary
		seen[str(proposal.get("type", ""))] = true
	for type in types:
		if not seen.has(type):
			return false
	return true


func _has_differentiated_plots(blueprint: Dictionary) -> bool:
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "differentiated":
			return true
	return false


func _public_plot_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) == "public":
			count += 1
	return count


func _step_resolutions_allow_parallel_family_growth(trace: Dictionary) -> bool:
	for resolution_value in (trace.get("step_resolutions", []) as Array):
		var resolution: Dictionary = resolution_value as Dictionary
		var families: Dictionary = {}
		var cells: Dictionary = {}
		for winner_value in (resolution.get("winners", []) as Array):
			var winner: Dictionary = winner_value as Dictionary
			var family := _family_group(winner)
			families[family] = int(families.get(family, 0)) + 1
			if int(families.get(family, 0)) > 1:
				return false
			for cell_value in (winner.get("affected_cells", []) as Array):
				var cell: Dictionary = cell_value as Dictionary
				var key := "%d,%d" % [int(cell.get("x", -9999)), int(cell.get("y", -9999))]
				if cells.has(key):
					return false
				cells[key] = true
	return true


func _trace_has_parallel_commits(trace: Dictionary) -> bool:
	for resolution_value in (trace.get("step_resolutions", []) as Array):
		var resolution: Dictionary = resolution_value as Dictionary
		if int(resolution.get("winner_count", 0)) > 1:
			return true
	return false


func _family_group(proposal: Dictionary) -> String:
	match str(proposal.get("type", "")):
		"add_core_seed":
			return "core_group"
		"add_road_segment":
			return "road_group"
		"add_generic_plot":
			return "plot_group"
		"differentiate_plot":
			var payload: Dictionary = proposal.get("payload", {}) as Dictionary
			if str(payload.get("use", "")) == "public":
				return "public_group"
			return "differentiation_group"
		"add_building_footprint":
			return "footprint_group"
		_:
			return "unknown_group"


func _plot_growth_is_delayed(blueprint: Dictionary) -> bool:
	var plots_by_id: Dictionary = {}
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		plots_by_id[str(plot.get("id", ""))] = plot
		if str(plot.get("status", "")) == "differentiated":
			if int(plot.get("differentiated_step", 0)) - int(plot.get("step", 0)) < 2:
				return false
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var plot: Dictionary = plots_by_id.get(str(building.get("plot_id", "")), {}) as Dictionary
		if plot.is_empty():
			return false
		if int(building.get("step", 0)) - int(plot.get("differentiated_step", 0)) < 2:
			return false
	return true


func _trace_has_agent_search_stats(trace: Dictionary) -> bool:
	var required := {
		"road_endpoint_agent": false,
		"generic_plot_agent_core_bias": false,
		"generic_plot_agent_road_bias": false,
		"generic_plot_agent_edge_bias": false,
		"plot_differentiation_agent": false,
		"building_footprint_agent": false,
	}
	for stat_value in (trace.get("agent_search_stats", []) as Array):
		var stat: Dictionary = stat_value as Dictionary
		var agent_id := str(stat.get("agent_id", ""))
		if required.has(agent_id):
			for key in ["valid_candidates_count", "sampled_candidates_count", "top_score", "chosen_score", "rejected_reason_distribution"]:
				if not stat.has(key):
					return false
			required[agent_id] = true
	for key in required.keys():
		if not bool(required.get(key, false)):
			return false
	return true


func _trace_has_blueprint_replay_snapshots(trace: Dictionary) -> bool:
	var snapshots: Array = trace.get("blueprint_snapshots", []) as Array
	if snapshots.size() < 8:
		return false
	var required_steps := [0, 5, 10, 15, 20, 25]
	var seen: Dictionary = {}
	for snapshot_value in snapshots:
		var snapshot: Dictionary = snapshot_value as Dictionary
		seen[int(snapshot.get("step", -1))] = true
	for step in required_steps:
		if not seen.has(step):
			return false
	return true


func _trace_has_differentiation_bids(trace: Dictionary) -> bool:
	for proposal_value in (trace.get("proposals", []) as Array):
		var proposal: Dictionary = proposal_value as Dictionary
		if str(proposal.get("type", "")) != "differentiate_plot":
			continue
		var payload: Dictionary = proposal.get("payload", {}) as Dictionary
		var bid: Dictionary = payload.get("bid", {}) as Dictionary
		for key in ["plot_id", "use_type", "score", "reason", "nearby_types", "road_access_score", "core_distance_score", "public_need_score", "policy_weight"]:
			if not bid.has(key):
				return false
		return true
	return false


func _building_footprints_have_debug_details(blueprint: Dictionary) -> bool:
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		for key in ["plot_id", "use_type", "facing", "entrance_cell", "front_access_cell", "footprint_size", "presentation_note"]:
			if not building.has(key):
				return false
	return not (blueprint.get("buildings", []) as Array).is_empty()


func _rejections_have_resolution_details(trace: Dictionary) -> bool:
	for resolution_value in (trace.get("step_resolutions", []) as Array):
		var resolution: Dictionary = resolution_value as Dictionary
		for loser_value in (resolution.get("losers", []) as Array):
			var loser: Dictionary = loser_value as Dictionary
			if not loser.has("reason"):
				return false
			if not loser.has("score"):
				return false
			if not loser.has("winner_key"):
				return false
			if not loser.has("conflict_keys"):
				return false
	return true


func _evaluator_reports_pressure(trace: Dictionary) -> bool:
	for report_value in (trace.get("evaluator_reports", []) as Array):
		var report: Dictionary = report_value as Dictionary
		var feedback: Dictionary = report.get("feedback", {}) as Dictionary
		for key in ["need_more_roads", "need_public_space", "road_overdensity_zones", "isolated_plots", "weak_core_zones"]:
			if not feedback.has(key):
				return false
	return true


func _evaluator_reports_score_penalties(trace: Dictionary) -> bool:
	for report_value in (trace.get("evaluator_reports", []) as Array):
		var report: Dictionary = report_value as Dictionary
		if not report.has("score_penalties"):
			return false
		if float(report.get("score", 1.0)) < 1.0 and (report.get("score_penalties", []) as Array).is_empty():
			return false
		for penalty_value in (report.get("score_penalties", []) as Array):
			var penalty: Dictionary = penalty_value as Dictionary
			for key in ["reason", "weight", "affected_object"]:
				if not penalty.has(key):
					return false
	return true


func _evaluator_reports_road_connectivity(trace: Dictionary) -> bool:
	for report_value in (trace.get("evaluator_reports", []) as Array):
		var report: Dictionary = report_value as Dictionary
		var feedback: Dictionary = report.get("feedback", {}) as Dictionary
		if not feedback.has("road_connectivity"):
			return false
		var connectivity: Dictionary = feedback.get("road_connectivity", {}) as Dictionary
		for key in ["road_component_count", "entrance_connected", "core_connected", "all_plot_access_connected", "all_building_front_connected"]:
			if not connectivity.has(key):
				return false
	return true


func _road_graph_is_connected_to_core(result: Dictionary) -> bool:
	var blueprint: Dictionary = result.get("blueprint", {}) as Dictionary
	var context: Dictionary = result.get("context", {}) as Dictionary
	var map_size: Dictionary = context.get("map_size", {}) as Dictionary
	var connectivity := RoadGraphScript.analyze_blueprint(
		blueprint,
		context.get("entrances", []) as Array,
		Vector2i(int(map_size.get("width", 0)), int(map_size.get("height", 0)))
	)
	var road_component_count := int(connectivity.get("road_component_count", 0))
	var entrance_connected := bool(connectivity.get("entrance_connected", false))
	var core_connected := bool(connectivity.get("core_connected", false))
	var plots_connected := bool(connectivity.get("all_plot_access_connected", false))
	var buildings_connected := bool(connectivity.get("all_building_front_connected", false))
	var roads_connected := bool(connectivity.get("all_roads_connected_to_entrance", false))
	return road_component_count == 1 and entrance_connected and roads_connected and core_connected and plots_connected and buildings_connected


func _compiled_road_graph_is_connected(result: Dictionary) -> bool:
	var compiler: RefCounted = TileSceneCompilerScript.new()
	var compiled: Dictionary = compiler.compile_session_result({
		"id": "v62_smoke_compiled",
		"display_name": "V62 Smoke Compiled",
		"tile_size": 32,
	}, result)
	var errors: Array[String] = compiler.validate_compiled_location(compiled)
	if not errors.is_empty():
		return false
	var connectivity := RoadGraphScript.analyze_compiled_location(compiled)
	var road_connected := bool(connectivity.get("compiled_road_connected", false))
	var entrance_connected := bool(connectivity.get("compiled_entrance_connected", false))
	var core_connected := bool(connectivity.get("compiled_core_connected", false))
	var plots_connected := bool(connectivity.get("compiled_plot_access_connected", false))
	var buildings_connected := bool(connectivity.get("compiled_building_front_connected", false))
	return road_connected and entrance_connected and core_connected and plots_connected and buildings_connected


func _trace_has_rejection_from(trace: Dictionary, proposer_id: String) -> bool:
	for proposal_value in (trace.get("rejected_proposals", []) as Array):
		var proposal: Dictionary = proposal_value as Dictionary
		if str(proposal.get("proposer_id", "")) == proposer_id:
			return true
	return false


func _resolver_is_only_commit_entry() -> bool:
	var blueprint := SettlementBlueprint.new()
	var proposal := PlanProposal.create("test", "add_core_seed", 0, "blueprint_growth", "Direct write should fail.", 1)
	proposal.proposal_id = "direct_core_write"
	var affected_cells: Array[Vector2i] = [Vector2i(4, 4)]
	proposal.affected_cells = affected_cells
	proposal.payload = { "id": "direct_core", "cell": Vector2i(4, 4) }
	if blueprint.apply_committed_proposal(proposal, "wrong_token"):
		return _fail("v62 blueprint must reject direct commits without resolver token")
	if not blueprint.cores.is_empty():
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
	if int(summary.get("rejected_cell_count", 0)) <= 0:
		return _fail("v62 debug view must render rejected proposal cells")
	if int(summary.get("process_log_line_count", 0)) <= 0:
		return _fail("v62 debug view must render step process logs")
	if int(summary.get("agent_search_line_count", 0)) <= 0:
		return _fail("v62 debug view must render agent search statistics")
	if int(summary.get("replay_slice_count", 0)) <= 0:
		return _fail("v62 debug view must render a selected blueprint replay slice")
	if int(summary.get("connectivity_line_count", 0)) <= 0:
		return _fail("v62 debug view must render road connectivity diagnostics")
	_root.remove_child(view)
	view.free()
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
