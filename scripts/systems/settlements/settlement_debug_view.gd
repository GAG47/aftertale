class_name SettlementDebugView
extends Control

const CELL_SIZE := 6
const REPLAY_CELL_SIZE := 4
const REPLAY_SLICE_STEPS := [0, 5, 10, 15, 20, 25, 28]
const DEFAULT_DEBUG_LOCATION_PATH := "res://data/locations/generated_settlement.json"
const POLICY_IDS := ["farming_village", "forest_village", "roadside_trade_village", "mining_camp"]
const RoadGraphScript := preload("res://scripts/systems/settlements/settlement_road_graph.gd")
const TileSceneCompilerScript := preload("res://scripts/systems/settlements/tile_scene_compiler.gd")

@export_file("*.json") var debug_location_path: String = DEFAULT_DEBUG_LOCATION_PATH

var session_result: Dictionary = {}
var _rendered_summary: Dictionary = {}
var selected_replay_step: int = -1
var selected_policy_id: String = ""


func _ready() -> void:
	if session_result.is_empty():
		session_result = _default_debug_result()
	_render()


func configure(result: Dictionary) -> void:
	session_result = result.duplicate(true)
	if is_inside_tree():
		_render()


func get_debug_summary() -> Dictionary:
	return _rendered_summary.duplicate(true)


func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	custom_minimum_size = Vector2.ZERO
	var blueprint := session_result.get("blueprint", {}) as Dictionary
	var feature_maps := session_result.get("feature_maps", {}) as Dictionary
	var trace := session_result.get("trace", {}) as Dictionary
	var trace_summary := trace.get("summary", {}) as Dictionary
	if selected_policy_id.is_empty():
		selected_policy_id = _policy_id_from_result(session_result)

	var scroll := ScrollContainer.new()
	scroll.name = "DebugScroll"
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.name = "DebugMargin"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "DebugContent"
	content.custom_minimum_size = Vector2.ZERO
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	_add_policy_selector(content)
	_add_text_panel(content, "PolicySummaryPanel", _policy_summary_text(), Vector2(0, 92))

	var summary_row := HBoxContainer.new()
	summary_row.name = "SummaryRow"
	summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_theme_constant_override("separation", 10)
	content.add_child(summary_row)

	_add_text_panel(summary_row, "BlueprintPanel", "Blueprint\ncores: %d\nroads: %d\nanchors: %d" % [
		(blueprint.get("cores", []) as Array).size(),
		(blueprint.get("roads", []) as Array).size(),
		(blueprint.get("interaction_anchors", []) as Array).size(),
	], Vector2(170, 108))
	_add_text_panel(summary_row, "LayerPanel", "Layers\nplots: %d\nbuildings: %d\npublic: %d" % [
		(blueprint.get("plots", []) as Array).size(),
		(blueprint.get("buildings", []) as Array).size(),
		_public_plot_count(blueprint),
	], Vector2(170, 108))
	_add_text_panel(summary_row, "ProposalPanel", "Proposals\naccepted: %d\nrejected: %d\ncommitted: %d" % [
		int(trace_summary.get("accepted_count", 0)),
		int(trace_summary.get("rejected_count", 0)),
		int(trace_summary.get("committed_count", 0)),
	], Vector2(190, 108))
	_add_text_panel(summary_row, "EvaluatorPanel", "Evaluator\nreports: %d\nscore: %.2f\n%s" % [
		int(trace_summary.get("evaluator_report_count", 0)),
		_last_evaluator_score(trace),
		_last_feedback_text(trace),
	], Vector2(230, 128))
	_add_text_panel(summary_row, "TracePanel", "Trace\nrandom: %d\nsteps: %d\nproposals: %d" % [
		int(trace_summary.get("random_decision_count", 0)),
		int(trace_summary.get("step_count", 0)),
		int(trace_summary.get("proposal_count", 0)),
	], Vector2(170, 108))

	_add_text_panel(content, "LegendPanel", "Legend: core=blue  road=tan  generic=green  differentiated=olive  public=gold  building=brown  rejected=red", Vector2(0, 34))

	var map_size: Dictionary = feature_maps.get("map_size", {}) as Dictionary
	var width := int(map_size.get("width", 0))
	var height := int(map_size.get("height", 0))
	var map_pixels := Vector2(width * CELL_SIZE, height * CELL_SIZE)

	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 12)
	content.add_child(main_row)

	var map_column := VBoxContainer.new()
	map_column.name = "MapColumn"
	map_column.custom_minimum_size = Vector2(map_pixels.x, map_pixels.y + 30)
	main_row.add_child(map_column)
	_add_text_panel(map_column, "MapTitlePanel", "Blueprint Map", Vector2(map_pixels.x, 28))

	var grid_panel := Control.new()
	grid_panel.name = "FeatureMapPanel"
	grid_panel.custom_minimum_size = map_pixels
	map_column.add_child(grid_panel)

	var occupied_cells := _sample_cells(feature_maps.get("occupied_sample", []) as Array)
	var cell_count := 0
	for y in range(height):
		for x in range(width):
			var cell_rect := ColorRect.new()
			cell_rect.name = "FeatureCell_%d_%d" % [x, y]
			cell_rect.position = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			cell_rect.size = Vector2(CELL_SIZE - 1, CELL_SIZE - 1)
			cell_rect.color = Color(0.18, 0.22, 0.18, 0.75)
			if occupied_cells.has("%d,%d" % [x, y]):
				cell_rect.color = Color(0.24, 0.27, 0.22, 0.90)
			grid_panel.add_child(cell_rect)
			cell_count += 1
	var plot_cell_count := _draw_plots(grid_panel, blueprint)
	var road_cell_count := _draw_roads(grid_panel, blueprint)
	var building_cell_count := _draw_buildings(grid_panel, blueprint)
	var core_count := _draw_points(grid_panel, blueprint.get("cores", []) as Array, "CoreMarker", Color(0.25, 0.54, 1.0, 0.98), "cell")
	var rejected_cell_count := _draw_rejected(grid_panel, trace, width, height)

	var detail_column := VBoxContainer.new()
	detail_column.name = "DetailColumn"
	detail_column.custom_minimum_size = Vector2(650, 0)
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 10)
	main_row.add_child(detail_column)
	_add_text_panel(detail_column, "StepLogPanel", _step_log_text(trace), Vector2(640, 230))
	_add_text_panel(detail_column, "AgentSearchPanel", _agent_search_text(trace), Vector2(640, 230))
	_add_text_panel(detail_column, "ScorePenaltyPanel", _score_penalty_text(trace), Vector2(640, 130))
	_add_text_panel(detail_column, "ConnectivityPanel", _connectivity_text(trace), Vector2(640, 210))

	var bottom_row := HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_theme_constant_override("separation", 12)
	content.add_child(bottom_row)

	var replay_column := VBoxContainer.new()
	replay_column.name = "ReplayColumn"
	replay_column.custom_minimum_size = Vector2(max(260.0, float(width * REPLAY_CELL_SIZE)), 0)
	replay_column.add_theme_constant_override("separation", 6)
	bottom_row.add_child(replay_column)
	_add_replay_selector(replay_column, trace)
	var replay_slice_count := _draw_replay_snapshot(replay_column, trace, feature_maps)

	_add_text_panel(bottom_row, "FootprintPanel", _footprint_detail_text(blueprint), Vector2(640, 150))

	_rendered_summary = {
		"has_blueprint_panel": find_child("BlueprintPanel", true, false) != null,
		"has_proposal_panel": find_child("ProposalPanel", true, false) != null,
		"has_feature_map_panel": find_child("FeatureMapPanel", true, false) != null,
		"has_evaluator_panel": find_child("EvaluatorPanel", true, false) != null,
		"has_trace_panel": find_child("TracePanel", true, false) != null,
		"has_policy_selector": find_child("PolicySelector", true, false) != null,
		"active_policy": selected_policy_id,
		"feature_cell_count": cell_count,
		"road_cell_count": road_cell_count,
		"plot_cell_count": plot_cell_count,
		"building_cell_count": building_cell_count,
		"core_marker_count": core_count,
		"rejected_cell_count": rejected_cell_count,
		"replay_slice_count": replay_slice_count,
		"accepted_count": int(trace_summary.get("accepted_count", 0)),
		"rejected_count": int(trace_summary.get("rejected_count", 0)),
		"step_count": int(trace_summary.get("step_count", 0)),
		"process_log_line_count": _step_log_rows(trace).size(),
		"agent_search_line_count": _agent_search_rows(trace).size(),
		"score_penalty_line_count": _score_penalty_rows(trace).size(),
		"connectivity_line_count": _connectivity_text(trace).split("\n").size(),
		"policy_summary_line_count": _policy_summary_text().split("\n").size(),
	}


func _default_debug_result() -> Dictionary:
	var generated_result := _debug_result_from_generated_location(debug_location_path)
	if not generated_result.is_empty():
		return generated_result

	var policy := SettlementPolicy.from_dictionary({
		"policy_id": "v62_debug_settlement",
		"settlement_type": "v62_debug_settlement",
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
	session.max_blueprint_steps = session.recommended_step_budget()
	return session.run()


func _debug_result_from_generated_location(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var source_data: Dictionary = parsed as Dictionary
	var generator_data: Dictionary = source_data.get("generator", {}) as Dictionary
	if generator_data.is_empty():
		return {}
	var policy := SettlementPolicy.from_generator_data(generator_data)
	var context_data: Dictionary = generator_data.get("context", {}) as Dictionary
	if context_data.is_empty():
		context_data = _debug_context_from_generator(generator_data)
	var context := SettlementContext.from_dictionary(context_data)
	var session := SettlementGenerationSession.new(policy, context)
	return session.run()


func _debug_result_for_policy(policy_id: String) -> Dictionary:
	var policy := SettlementPolicy.from_profile_id(policy_id)
	var context := SettlementContext.from_dictionary({
		"map_size": { "width": 48, "height": 32 },
		"entrances": [{ "x": 0, "y": 16 }],
		"existing_obstacles": [{ "x": 11, "y": 5 }, { "x": 12, "y": 5 }, { "x": 38, "y": 24 }],
		"existing_water": [{ "x": 42, "y": 7 }, { "x": 43, "y": 7 }, { "x": 43, "y": 8 }],
		"important_world_points": [{ "x": 36, "y": 20 }],
		"world_seed": policy.seed_override if policy.seed_override >= 0 else policy.random_seed,
	})
	var session := SettlementGenerationSession.new(policy, context)
	session.max_blueprint_steps = session.recommended_step_budget()
	return session.run()


func _debug_context_from_generator(generator_data: Dictionary) -> Dictionary:
	var size: Dictionary = generator_data.get("size", {}) as Dictionary
	var width := int(size.get("width", 20))
	var height := int(size.get("height", 14))
	return {
		"map_size": { "width": width, "height": height },
		"entrances": [{ "x": 0, "y": int(height / 2) }],
		"existing_obstacles": generator_data.get("existing_obstacles", []),
		"existing_water": generator_data.get("existing_water", []),
		"important_world_points": generator_data.get("important_world_points", [{ "x": width - 5, "y": int(height / 2) }]),
		"world_seed": int(generator_data.get("seed", 6301)),
	}


func _add_text_panel(parent: Control, node_name: String, text: String, min_size: Vector2) -> Label:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.custom_minimum_size = min_size
	if min_size.x <= 0.0:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.name = "%sLabel" % node_name
	label.text = text
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)
	parent.add_child(panel)
	return label


func _add_policy_selector(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "PolicyControlRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	_add_text_panel(row, "PolicyLabelPanel", "Policy", Vector2(80, 34))
	var selector := OptionButton.new()
	selector.name = "PolicySelector"
	selector.custom_minimum_size = Vector2(250, 34)
	for index in range(POLICY_IDS.size()):
		var policy_id := str(POLICY_IDS[index])
		selector.add_item(policy_id)
		selector.set_item_metadata(index, policy_id)
		if policy_id == selected_policy_id:
			selector.select(index)
	selector.item_selected.connect(_on_policy_selected)
	row.add_child(selector)
	var button := Button.new()
	button.name = "RegeneratePolicyButton"
	button.text = "Regenerate"
	button.custom_minimum_size = Vector2(130, 34)
	button.pressed.connect(_on_regenerate_policy_pressed)
	row.add_child(button)


func _on_policy_selected(index: int) -> void:
	var selector := find_child("PolicySelector", true, false) as OptionButton
	if selector == null:
		return
	selected_policy_id = str(selector.get_item_metadata(index))
	selected_replay_step = -1
	session_result = _debug_result_for_policy(selected_policy_id)
	call_deferred("_render")


func _on_regenerate_policy_pressed() -> void:
	if selected_policy_id.is_empty():
		selected_policy_id = _policy_id_from_result(session_result)
	selected_replay_step = -1
	session_result = _debug_result_for_policy(selected_policy_id)
	call_deferred("_render")


func _add_replay_selector(parent: Control, trace: Dictionary) -> void:
	var steps := _replay_steps(trace)
	if steps.is_empty():
		_add_text_panel(parent, "ReplayPanel", "Replay: no snapshots", Vector2(260, 32))
		return
	if selected_replay_step < 0:
		selected_replay_step = int(steps[steps.size() - 1])
	var row := HBoxContainer.new()
	row.name = "ReplayControlRow"
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	_add_text_panel(row, "ReplayLabelPanel", "Replay", Vector2(80, 34))
	var selector := OptionButton.new()
	selector.name = "ReplayStepSelector"
	selector.custom_minimum_size = Vector2(140, 34)
	for index in range(steps.size()):
		var step := int(steps[index])
		selector.add_item("step %02d" % step)
		selector.set_item_metadata(index, step)
		if step == selected_replay_step:
			selector.select(index)
	selector.item_selected.connect(_on_replay_step_selected)
	row.add_child(selector)


func _on_replay_step_selected(index: int) -> void:
	var selector := find_child("ReplayStepSelector", true, false) as OptionButton
	if selector == null:
		return
	selected_replay_step = int(selector.get_item_metadata(index))
	call_deferred("_render")


func _policy_summary_text() -> String:
	var policy: Dictionary = session_result.get("policy", {}) as Dictionary
	var summary: Dictionary = session_result.get("session_summary", {}) as Dictionary
	var demand: Dictionary = summary.get("demand_ledger", {}) as Dictionary
	var blueprint: Dictionary = session_result.get("blueprint", {}) as Dictionary
	var text := "Active Policy: %s  type=%s  road=%s  density=%.2f  asset=%s" % [
		str(policy.get("policy_id", selected_policy_id)),
		str(policy.get("settlement_type", "")),
		str(policy.get("road_style", "")),
		float(policy.get("density", 0.0)),
		_asset_family_text(policy),
	]
	text += "\nagent weights: %s" % _agent_weight_summary_text(summary.get("agent_weight_summary", {}) as Dictionary)
	text += "\ndemand: %s" % _demand_ledger_text(demand)
	text += "\nplot uses: %s" % _counts_text(_plot_use_counts(blueprint))
	text += "\nbuilding types: %s" % _counts_text(_building_type_counts(blueprint))
	text += "\nrequired landmarks: %s" % _required_landmarks_text(policy, blueprint)
	return text


func _policy_id_from_result(result: Dictionary) -> String:
	var policy: Dictionary = result.get("policy", {}) as Dictionary
	var policy_id := str(policy.get("policy_id", ""))
	if not policy_id.is_empty():
		return policy_id
	return "roadside_trade_village"


func _agent_weight_summary_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in summary.keys():
		var row: Dictionary = summary.get(key, {}) as Dictionary
		var short_key := _short_agent_id(str(key))
		parts.append("%s=%.1f/%d" % [short_key, float(row.get("weight", 1.0)), int(row.get("max_commits", 0))])
		if parts.size() >= 5:
			break
	return " ".join(parts)


func _demand_ledger_text(demand: Dictionary) -> String:
	if demand.is_empty():
		return "-"
	return "home=%d trade=%d prod=%d public=%d road=%d" % [
		int(demand.get("housing_need", 0)),
		int(demand.get("commerce_need", 0)),
		int(demand.get("production_need", 0)),
		int(demand.get("public_need", 0)),
		int(demand.get("road_need", 0)),
	]


func _counts_text(counts: Dictionary) -> String:
	if counts.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in counts.keys():
		parts.append("%s=%d" % [_short_token(str(key)), int(counts.get(key, 0))])
	return " ".join(parts)


func _plot_use_counts(blueprint: Dictionary) -> Dictionary:
	var result := {
		"generic": 0,
		"residential": 0,
		"commercial": 0,
		"production": 0,
		"public": 0,
	}
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var use := str(plot.get("use", "generic"))
		result[use] = int(result.get(use, 0)) + 1
	return result


func _building_type_counts(blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		var type := str(building.get("building_type", building.get("kind", "")))
		result[type] = int(result.get(type, 0)) + 1
	return result


func _required_landmarks_text(policy: Dictionary, blueprint: Dictionary) -> String:
	var required: Array = policy.get("required_landmarks", []) as Array
	if required.is_empty():
		return "none"
	var anchors: Array = (blueprint.get("interaction_anchors", []) as Array)
	var parts: Array[String] = []
	for item in required:
		var required_id := str(item)
		parts.append("%s=%s" % [required_id, _flag_text(_anchor_kind_exists(anchors, required_id))])
	return " ".join(parts)


func _anchor_kind_exists(anchors: Array, kind_or_id: String) -> bool:
	for anchor_value in anchors:
		var anchor: Dictionary = anchor_value as Dictionary
		if str(anchor.get("kind", "")) == kind_or_id or str(anchor.get("id", "")).find(kind_or_id) >= 0:
			return true
	return false


func _asset_family_text(policy: Dictionary) -> String:
	var families: Array = policy.get("asset_family_preferences", []) as Array
	if families.is_empty():
		return "common"
	return str(families[0])


func _last_evaluator_score(trace: Dictionary) -> float:
	var reports: Array = trace.get("evaluator_reports", []) as Array
	if reports.is_empty():
		return 0.0
	var report: Dictionary = reports[reports.size() - 1] as Dictionary
	return float(report.get("score", 0.0))


func _last_feedback_text(trace: Dictionary) -> String:
	var reports: Array = trace.get("evaluator_reports", []) as Array
	if reports.is_empty():
		return "feedback: none"
	var report: Dictionary = reports[reports.size() - 1] as Dictionary
	var feedback: Dictionary = report.get("feedback", {}) as Dictionary
	return "need roads: %s\nneed plots: %s\nneed public: %s\nisolated: %d\ndense roads: %d" % [
		_flag_text(feedback.get("need_more_roads", false)),
		_flag_text(feedback.get("need_more_generic_plots", false)),
		_flag_text(feedback.get("need_public_space", false)),
		(feedback.get("isolated_plots", []) as Array).size(),
		(feedback.get("road_overdensity_zones", []) as Array).size(),
	]


func _score_penalty_text(trace: Dictionary) -> String:
	var rows := _score_penalty_rows(trace)
	var text := "Score Penalties"
	if rows.is_empty():
		return text + "\nnone"
	var start_index: int = max(0, rows.size() - 6)
	for row in rows.slice(start_index):
		text += "\n%s" % row
	return text


func _score_penalty_rows(trace: Dictionary) -> Array[String]:
	var reports: Array = trace.get("evaluator_reports", []) as Array
	if reports.is_empty():
		return []
	var report: Dictionary = reports[reports.size() - 1] as Dictionary
	var penalties: Array = report.get("score_penalties", []) as Array
	var result: Array[String] = []
	for penalty_value in penalties:
		var penalty: Dictionary = penalty_value as Dictionary
		result.append("- %s w=%.2f obj=%s" % [
			_short_reason(str(penalty.get("reason", ""))),
			float(penalty.get("weight", 0.0)),
			_short_token(str(penalty.get("affected_object", ""))),
		])
	return result


func _connectivity_text(trace: Dictionary) -> String:
	var blueprint_connectivity := _last_connectivity(trace)
	var compiled_connectivity := _compiled_connectivity()
	var text := "Connectivity"
	text += "\nroad components: %d" % int(blueprint_connectivity.get("road_component_count", 0))
	text += "\nentrance connected: %s" % _flag_text(blueprint_connectivity.get("entrance_connected", false))
	text += "\ncore connected: %s" % _flag_text(blueprint_connectivity.get("core_connected", false))
	text += "\nplot access connected: %s" % _flag_text(blueprint_connectivity.get("all_plot_access_connected", false))
	text += "\nbuilding front connected: %s" % _flag_text(blueprint_connectivity.get("all_building_front_connected", false))
	text += "\ncompiled road connected: %s" % _flag_text(compiled_connectivity.get("compiled_road_connected", false))
	text += "\ncompiled entrance connected: %s" % _flag_text(compiled_connectivity.get("compiled_entrance_connected", false))
	text += "\ncompiled core connected: %s" % _flag_text(compiled_connectivity.get("compiled_core_connected", false))
	text += "\ncompiled plot access connected: %s" % _flag_text(compiled_connectivity.get("compiled_plot_access_connected", false))
	text += "\ncompiled building front connected: %s" % _flag_text(compiled_connectivity.get("compiled_building_front_connected", false))
	var failures := _connectivity_failure_text(blueprint_connectivity, compiled_connectivity)
	if not failures.is_empty():
		text += "\nfailures: %s" % failures
	return text


func _last_connectivity(trace: Dictionary) -> Dictionary:
	var reports: Array = trace.get("evaluator_reports", []) as Array
	if reports.is_empty():
		return {}
	var report: Dictionary = reports[reports.size() - 1] as Dictionary
	return report.get("road_connectivity", {}) as Dictionary


func _compiled_connectivity() -> Dictionary:
	if session_result.is_empty():
		return {}
	var compiler: RefCounted = TileSceneCompilerScript.new()
	var compiled: Dictionary = compiler.compile_session_result({
		"id": "settlement_debug_compiled",
		"display_name": "Settlement Debug Compiled",
		"tile_size": 32,
	}, session_result)
	return RoadGraphScript.analyze_compiled_location(compiled)


func _connectivity_failure_text(blueprint_connectivity: Dictionary, compiled_connectivity: Dictionary) -> String:
	var parts: Array[String] = []
	_append_failure_part(parts, "roads", blueprint_connectivity.get("disconnected_road_segment_ids", []) as Array)
	_append_failure_part(parts, "plots", blueprint_connectivity.get("disconnected_plot_ids", []) as Array)
	_append_failure_part(parts, "buildings", blueprint_connectivity.get("disconnected_building_ids", []) as Array)
	_append_failure_part(parts, "entrances", _failure_ids(blueprint_connectivity.get("failed_entrances", []) as Array))
	_append_failure_part(parts, "front", _failure_cells(blueprint_connectivity.get("disconnected_building_front_access", []) as Array, "front_access_cell"))
	_append_failure_part(parts, "compiled_roads", compiled_connectivity.get("disconnected_road_segment_ids", []) as Array)
	_append_failure_part(parts, "compiled_plots", compiled_connectivity.get("disconnected_plot_ids", []) as Array)
	_append_failure_part(parts, "compiled_buildings", compiled_connectivity.get("disconnected_building_ids", []) as Array)
	return " | ".join(parts)


func _append_failure_part(parts: Array[String], label: String, values: Array) -> void:
	if values.is_empty():
		return
	parts.append("%s=%s" % [label, ",".join(_string_array(values))])


func _failure_ids(rows: Array) -> Array[String]:
	var result: Array[String] = []
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		result.append(str(row.get("id", "")))
	return result


func _failure_cells(rows: Array, cell_key: String) -> Array[String]:
	var result: Array[String] = []
	for row_value in rows:
		var row: Dictionary = row_value as Dictionary
		result.append("%s@%s" % [str(row.get("id", "")), _cell_text(row.get(cell_key, {}))])
	return result


func _flag_text(value: Variant) -> String:
	return "yes" if bool(value) else "no"


func _public_plot_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) == "public":
			count += 1
	return count


func _step_log_text(trace: Dictionary) -> String:
	var rows := _step_log_rows(trace)
	var start_index: int = max(0, rows.size() - 10)
	var visible_rows := rows.slice(start_index)
	var text := "Step Log"
	for row in visible_rows:
		text += "\n%s" % row
	return text


func _step_log_rows(trace: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for resolution_value in (trace.get("step_resolutions", []) as Array):
		var resolution: Dictionary = resolution_value as Dictionary
		var step := int(resolution.get("step", -1))
		for winner_value in (resolution.get("winners", []) as Array):
			var winner: Dictionary = winner_value as Dictionary
			rows.append("%02d accept %-16s score=%.1f" % [step, _proposal_label(winner), float(winner.get("score", 0.0))])
		for loser_value in (resolution.get("losers", []) as Array):
			var loser: Dictionary = loser_value as Dictionary
			var proposal: Dictionary = loser.get("proposal", {}) as Dictionary
			rows.append("%02d reject %-16s %s" % [step, _proposal_label(proposal), _loser_label(loser)])
	return rows


func _agent_search_text(trace: Dictionary) -> String:
	var rows := _agent_search_rows(trace)
	var start_index: int = max(0, rows.size() - 8)
	var visible_rows := rows.slice(start_index)
	var text := "Agent Search"
	for row in visible_rows:
		text += "\n%s" % row
	return text


func _agent_search_rows(trace: Dictionary) -> Array[String]:
	var rows: Array[String] = []
	for stat_value in (trace.get("agent_search_stats", []) as Array):
		var stat: Dictionary = stat_value as Dictionary
		var step := int(stat.get("step", -1))
		var agent := _short_agent_id(str(stat.get("agent_id", "")))
		var suffix := ""
		if bool(stat.get("bidding", false)):
			suffix = " bids"
		if stat.has("bias"):
			suffix = " %s" % str(stat.get("bias", ""))
		rows.append("%02d %-13s v=%d s=%d top=%.1f pick=%.1f rej=%s%s" % [
			step,
			agent,
			int(stat.get("valid_candidates_count", 0)),
			int(stat.get("sampled_candidates_count", 0)),
			float(stat.get("top_score", 0.0)),
			float(stat.get("chosen_score", 0.0)),
			_reject_distribution_text(stat.get("rejected_reason_distribution", {}) as Dictionary),
			suffix,
		])
	return rows


func _short_agent_id(agent_id: String) -> String:
	var value := agent_id
	value = value.replace("generic_plot_agent_", "plot_")
	value = value.replace("_agent", "")
	value = value.replace("plot_differentiation", "diff")
	value = value.replace("building_footprint", "footprint")
	value = value.replace("road_endpoint", "road_end")
	value = value.replace("road_reconnect", "road_reconn")
	return value


func _reject_distribution_text(distribution: Dictionary) -> String:
	if distribution.is_empty():
		return "-"
	var parts: Array[String] = []
	for key in distribution.keys():
		parts.append("%s:%d" % [str(key), int(distribution.get(key, 0))])
		if parts.size() >= 2:
			break
	return ",".join(parts)


func _footprint_detail_text(blueprint: Dictionary) -> String:
	var buildings: Array = blueprint.get("buildings", []) as Array
	var text := "Footprints"
	if buildings.is_empty():
		return text + "\nnone"
	var start_index: int = max(0, buildings.size() - 5)
	for index in range(start_index, buildings.size()):
		var building: Dictionary = buildings[index] as Dictionary
		var footprint_size: Dictionary = building.get("footprint_size", {}) as Dictionary
		var note := _footprint_note(building)
		text += "\n%s plot=%s use=%s face=%s in=%s front=%s %dx%d%s" % [
			_short_token(str(building.get("id", ""))),
			_short_token(str(building.get("plot_id", ""))),
			str(building.get("use_type", building.get("kind", ""))),
			str(building.get("facing", "")),
			_cell_text(building.get("entrance_cell", {})),
			_cell_text(building.get("front_access_cell", {})),
			int(footprint_size.get("width", 0)),
			int(footprint_size.get("height", 0)),
			note,
		]
	return text


func _footprint_note(building: Dictionary) -> String:
	var note := str(building.get("presentation_note", ""))
	if note.is_empty():
		return ""
	return " note=%s" % _short_token(note)


func _proposal_label(proposal: Dictionary) -> String:
	var type := str(proposal.get("type", "proposal"))
	match type:
		"add_road_segment":
			return "road"
		"add_generic_plot":
			return "generic_plot"
		"differentiate_plot":
			return "diff:%s" % str((proposal.get("payload", {}) as Dictionary).get("use", "use"))
		"add_building_footprint":
			return "footprint"
		"add_core_seed":
			return "core"
		_:
			return type


func _loser_label(loser: Dictionary) -> String:
	var notes: Array = loser.get("notes", []) as Array
	var conflict_keys: Array = loser.get("conflict_keys", []) as Array
	var note := str(notes[0]) if not notes.is_empty() else str(loser.get("reason", ""))
	var target := str(loser.get("winner_key", ""))
	if target.is_empty():
		target = "-"
	return "reason=%s score=%.1f tgt=%s grp=%s" % [
		_short_reason(note),
		float(loser.get("score", 0.0)),
		_short_token(target),
		_compact_conflict_group(conflict_keys),
	]


func _short_reason(value: String) -> String:
	if value.find(":") >= 0:
		return value.get_slice(":", 0)
	if value.length() > 26:
		return value.substr(0, 26)
	return value


func _short_token(value: String) -> String:
	var result := value
	result = result.replace("generic_plot_", "plot_")
	result = result.replace("building_", "b_")
	result = result.replace("generic_plot_agent_", "plot_")
	result = result.replace("_agent", "")
	if result.length() > 18:
		return result.substr(0, 18)
	return result


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result


func _compact_conflict_group(conflict_keys: Array) -> String:
	if conflict_keys.is_empty():
		return "-"
	if conflict_keys.size() == 1:
		return str(conflict_keys[0])
	return "%s+%d" % [str(conflict_keys[0]), conflict_keys.size() - 1]


func _sample_cells(samples: Array) -> Dictionary:
	var result: Dictionary = {}
	for sample_value in samples:
		var sample: Dictionary = sample_value as Dictionary
		if float(sample.get("value", 0.0)) <= 0.0:
			continue
		var cell: Dictionary = sample.get("cell", {}) as Dictionary
		result["%d,%d" % [int(cell.get("x", 0)), int(cell.get("y", 0))]] = true
	return result


func _replay_steps(trace: Dictionary) -> Array[int]:
	var snapshots: Array = trace.get("blueprint_snapshots", []) as Array
	var result: Array[int] = []
	if snapshots.is_empty():
		return result
	var last_snapshot: Dictionary = snapshots[snapshots.size() - 1] as Dictionary
	var max_step := int(last_snapshot.get("step", 0))
	for value in REPLAY_SLICE_STEPS:
		var step := int(value)
		if step <= max_step and not result.has(step):
			result.append(step)
	if not result.has(max_step):
		result.append(max_step)
	return result


func _draw_replay_snapshot(parent: Control, trace: Dictionary, feature_maps: Dictionary) -> int:
	var snapshots: Array = trace.get("blueprint_snapshots", []) as Array
	if snapshots.is_empty():
		return 0
	var step := selected_replay_step
	if step < 0:
		var steps := _replay_steps(trace)
		if steps.is_empty():
			return 0
		step = int(steps[steps.size() - 1])
		selected_replay_step = step
	var snapshot := _snapshot_for_step(trace, step)
	if snapshot.is_empty():
		return 0
	var blueprint: Dictionary = snapshot.get("blueprint", {}) as Dictionary
	var map_size: Dictionary = feature_maps.get("map_size", {}) as Dictionary
	var width := int(map_size.get("width", 0))
	var height := int(map_size.get("height", 0))
	_add_text_panel(parent, "ReplaySummaryPanel", _replay_summary_text(step, blueprint, trace), Vector2(max(260.0, float(width * REPLAY_CELL_SIZE)), 34))
	var panel := Control.new()
	panel.name = "ReplayMapPanel"
	panel.custom_minimum_size = Vector2(width * REPLAY_CELL_SIZE, height * REPLAY_CELL_SIZE)
	parent.add_child(panel)
	for y in range(height):
		for x in range(width):
			_add_scaled_cell(panel, "ReplayBase_%d_%d" % [x, y], Vector2i(x, y), Color(0.15, 0.18, 0.16, 0.82), Vector2.ZERO, REPLAY_CELL_SIZE)
	var count := 0
	count += _draw_replay_plots(panel, blueprint)
	count += _draw_replay_roads(panel, blueprint)
	count += _draw_replay_buildings(panel, blueprint)
	count += _draw_replay_points(panel, blueprint.get("cores", []) as Array, "ReplayCore", Color(0.25, 0.54, 1.0, 0.98), "cell")
	count += _draw_replay_rejected(panel, trace, step, width, height)
	return count


func _snapshot_for_step(trace: Dictionary, step: int) -> Dictionary:
	var best: Dictionary = {}
	for snapshot_value in (trace.get("blueprint_snapshots", []) as Array):
		var snapshot: Dictionary = snapshot_value as Dictionary
		if int(snapshot.get("step", -1)) <= step:
			best = snapshot
		else:
			break
	return best


func _replay_summary_text(step: int, blueprint: Dictionary, trace: Dictionary) -> String:
	return "Replay step %02d  roads=%d generic=%d diff=%d public=%d buildings=%d rejected=%d" % [
		step,
		(blueprint.get("roads", []) as Array).size(),
		_generic_plot_count(blueprint),
		_differentiated_plot_count(blueprint),
		_public_plot_count(blueprint),
		(blueprint.get("buildings", []) as Array).size(),
		_rejected_count_at_step(trace, step),
	]


func _draw_replay_roads(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for road_value in (blueprint.get("roads", []) as Array):
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			_add_scaled_cell(parent, "ReplayRoad_%d" % count, _cell_from_variant(cell_value), Color(0.70, 0.55, 0.32, 0.96), Vector2.ZERO, REPLAY_CELL_SIZE)
			count += 1
	return count


func _draw_replay_plots(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var color := _plot_color(plot)
		for cell in _area_cells(plot.get("area", {}) as Dictionary):
			_add_scaled_cell(parent, "ReplayPlot_%d" % count, cell, color, Vector2.ONE, REPLAY_CELL_SIZE)
			count += 1
	return count


func _draw_replay_buildings(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		for cell in _area_cells(building.get("area", {}) as Dictionary):
			_add_scaled_cell(parent, "ReplayBuilding_%d" % count, cell, Color(0.55, 0.34, 0.18, 0.98), Vector2.ZERO, REPLAY_CELL_SIZE)
			count += 1
	return count


func _draw_replay_points(parent: Control, entries: Array, prefix: String, color: Color, cell_key: String) -> int:
	var count := 0
	for value in entries:
		var entry: Dictionary = value as Dictionary
		_add_scaled_cell(parent, "%s_%d" % [prefix, count], _cell_from_variant(entry.get(cell_key, {})), color, Vector2.ZERO, REPLAY_CELL_SIZE)
		count += 1
	return count


func _draw_replay_rejected(parent: Control, trace: Dictionary, step: int, width: int, height: int) -> int:
	var count := 0
	for rejected_value in (trace.get("rejected_proposals", []) as Array):
		var rejected: Dictionary = rejected_value as Dictionary
		if int(rejected.get("step", -1)) != step:
			continue
		for cell in _proposal_cells(rejected):
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				continue
			_add_scaled_cell(parent, "ReplayRejected_%d" % count, cell, Color(1.0, 0.18, 0.18, 0.95), Vector2.ZERO, REPLAY_CELL_SIZE)
			count += 1
	return count


func _generic_plot_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "generic":
			count += 1
	return count


func _differentiated_plot_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("status", "")) == "differentiated":
			count += 1
	return count


func _rejected_count_at_step(trace: Dictionary, step: int) -> int:
	var count := 0
	for rejected_value in (trace.get("rejected_proposals", []) as Array):
		var rejected: Dictionary = rejected_value as Dictionary
		if int(rejected.get("step", -1)) == step:
			count += 1
	return count


func _draw_roads(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for road_value in (blueprint.get("roads", []) as Array):
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			_add_cell(parent, "RoadCell_%d" % count, cell, Color(0.70, 0.55, 0.32, 0.96), Vector2(1, 1))
			count += 1
	return count


func _draw_plots(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		var color := _plot_color(plot)
		for cell in _area_cells(plot.get("area", {}) as Dictionary):
			_add_cell(parent, "PlotCell_%d" % count, cell, color, Vector2(2, 2))
			count += 1
	return count


func _draw_buildings(parent: Control, blueprint: Dictionary) -> int:
	var count := 0
	for building_value in (blueprint.get("buildings", []) as Array):
		var building: Dictionary = building_value as Dictionary
		for cell in _area_cells(building.get("area", {}) as Dictionary):
			_add_cell(parent, "BuildingCell_%d" % count, cell, Color(0.55, 0.34, 0.18, 0.98), Vector2(3, 3))
			count += 1
	return count


func _draw_points(parent: Control, entries: Array, prefix: String, color: Color, cell_key: String) -> int:
	var count := 0
	for value in entries:
		var entry: Dictionary = value as Dictionary
		var cell := _cell_from_variant(entry.get(cell_key, {}))
		_add_cell(parent, "%s_%d" % [prefix, count], cell, color, Vector2(2, 2))
		count += 1
	return count


func _draw_rejected(parent: Control, trace: Dictionary, width: int, height: int) -> int:
	var count := 0
	for rejected_value in (trace.get("rejected_proposals", []) as Array):
		var rejected: Dictionary = rejected_value as Dictionary
		var cells := _proposal_cells(rejected)
		for cell in cells:
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
				continue
			_add_cell(parent, "RejectedCell_%d" % count, cell, Color(1.0, 0.18, 0.18, 0.92), Vector2(4, 4))
			count += 1
	return count


func _proposal_cells(proposal: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value in (proposal.get("affected_cells", []) as Array):
		result.append(_cell_from_variant(cell_value))
	if result.is_empty():
		for cell_value in (proposal.get("path", []) as Array):
			result.append(_cell_from_variant(cell_value))
	if result.is_empty() and not (proposal.get("area", {}) as Dictionary).is_empty():
		result = _area_cells(proposal.get("area", {}) as Dictionary)
	return result


func _add_cell(parent: Control, node_name: String, cell: Vector2i, color: Color, inset: Vector2) -> void:
	if cell.x < 0 or cell.y < 0:
		return
	var rect := ColorRect.new()
	rect.name = node_name
	rect.position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE) + inset
	rect.size = Vector2(CELL_SIZE, CELL_SIZE) - inset * 2.0
	rect.color = color
	parent.add_child(rect)


func _add_scaled_cell(parent: Control, node_name: String, cell: Vector2i, color: Color, inset: Vector2, cell_size: int) -> void:
	if cell.x < 0 or cell.y < 0:
		return
	var rect := ColorRect.new()
	rect.name = node_name
	rect.position = Vector2(cell.x * cell_size, cell.y * cell_size) + inset
	rect.size = Vector2(cell_size, cell_size) - inset * 2.0
	rect.color = color
	parent.add_child(rect)


func _plot_color(plot: Dictionary) -> Color:
	var use := str(plot.get("use", "generic"))
	if use == "public":
		return Color(0.95, 0.75, 0.20, 0.82)
	if use == "commercial":
		return Color(0.62, 0.55, 0.24, 0.74)
	if use == "production":
		return Color(0.45, 0.50, 0.24, 0.74)
	if use == "residential":
		return Color(0.33, 0.54, 0.30, 0.74)
	return Color(0.26, 0.58, 0.32, 0.52)


func _cell_text(value: Variant) -> String:
	var cell := _cell_from_variant(value)
	if cell.x < -1000 or cell.y < -1000:
		return "-"
	return "%d,%d" % [cell.x, cell.y]


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
