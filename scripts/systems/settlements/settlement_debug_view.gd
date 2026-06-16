class_name SettlementDebugView
extends Control

const CELL_SIZE := 12
const GRID_ORIGIN := Vector2(16, 190)

var session_result: Dictionary = {}
var _rendered_summary: Dictionary = {}


func _ready() -> void:
	if session_result.is_empty():
		var session := SettlementGenerationSession.new()
		session_result = session.run()
	_render()


func configure(result: Dictionary) -> void:
	session_result = result.duplicate(true)
	if is_inside_tree():
		_render()


func get_debug_summary() -> Dictionary:
	return _rendered_summary.duplicate(true)


func _render() -> void:
	for child in get_children():
		child.queue_free()

	custom_minimum_size = Vector2(1240, 620)
	var blueprint := session_result.get("blueprint", {}) as Dictionary
	var feature_maps := session_result.get("feature_maps", {}) as Dictionary
	var trace := session_result.get("trace", {}) as Dictionary
	var trace_summary := trace.get("summary", {}) as Dictionary

	_add_label("BlueprintPanel", Vector2(16, 12), Vector2(190, 112), "Blueprint\ncores: %d\nroads: %d\nanchors: %d" % [
		(blueprint.get("cores", []) as Array).size(),
		(blueprint.get("roads", []) as Array).size(),
		(blueprint.get("interaction_anchors", []) as Array).size(),
	])
	_add_label("LayerPanel", Vector2(236, 12), Vector2(210, 112), "Layers\nplots: %d\nbuildings: %d\npublic plots: %d" % [
		(blueprint.get("plots", []) as Array).size(),
		(blueprint.get("buildings", []) as Array).size(),
		_public_plot_count(blueprint),
	])
	_add_label("ProposalPanel", Vector2(482, 12), Vector2(220, 112), "Proposals\naccepted: %d\nrejected: %d\ncommitted: %d" % [
		int(trace_summary.get("accepted_count", 0)),
		int(trace_summary.get("rejected_count", 0)),
		int(trace_summary.get("committed_count", 0)),
	])
	_add_label("EvaluatorPanel", Vector2(728, 12), Vector2(210, 112), "Evaluator\nreports: %d\nlast score: %.2f" % [
		int(trace_summary.get("evaluator_report_count", 0)),
		_last_evaluator_score(trace),
	])
	_add_label("TracePanel", Vector2(964, 12), Vector2(190, 112), "Trace\nrandom: %d\nsteps: %d\nall proposals: %d" % [
		int(trace_summary.get("random_decision_count", 0)),
		int(trace_summary.get("step_count", 0)),
		int(trace_summary.get("proposal_count", 0)),
	])

	_add_label("LegendPanel", Vector2(16, 138), Vector2(920, 32), "Legend: core=blue  road=tan  plot=green  building=brown  rejected=red")
	_add_label("StepLogPanel", Vector2(340, 190), Vector2(860, 330), _step_log_text(trace))

	var grid_panel := Control.new()
	grid_panel.name = "FeatureMapPanel"
	grid_panel.position = GRID_ORIGIN
	add_child(grid_panel)
	var map_size: Dictionary = feature_maps.get("map_size", {}) as Dictionary
	var width := int(map_size.get("width", 0))
	var height := int(map_size.get("height", 0))
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
	var rejected_cell_count := _draw_rejected(grid_panel, trace)

	_rendered_summary = {
		"has_blueprint_panel": has_node("BlueprintPanel"),
		"has_proposal_panel": has_node("ProposalPanel"),
		"has_feature_map_panel": has_node("FeatureMapPanel"),
		"has_evaluator_panel": has_node("EvaluatorPanel"),
		"has_trace_panel": has_node("TracePanel"),
		"feature_cell_count": cell_count,
		"road_cell_count": road_cell_count,
		"plot_cell_count": plot_cell_count,
		"building_cell_count": building_cell_count,
		"core_marker_count": core_count,
		"rejected_cell_count": rejected_cell_count,
		"accepted_count": int(trace_summary.get("accepted_count", 0)),
		"rejected_count": int(trace_summary.get("rejected_count", 0)),
		"step_count": int(trace_summary.get("step_count", 0)),
		"process_log_line_count": _step_log_rows(trace).size(),
	}


func _add_label(node_name: String, pos: Vector2, size: Vector2, text: String) -> void:
	var label := Label.new()
	label.name = node_name
	label.position = pos
	label.size = size
	label.text = text
	add_child(label)


func _last_evaluator_score(trace: Dictionary) -> float:
	var reports: Array = trace.get("evaluator_reports", []) as Array
	if reports.is_empty():
		return 0.0
	var report: Dictionary = reports[reports.size() - 1] as Dictionary
	return float(report.get("score", 0.0))


func _public_plot_count(blueprint: Dictionary) -> int:
	var count := 0
	for plot_value in (blueprint.get("plots", []) as Array):
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) == "public":
			count += 1
	return count


func _step_log_text(trace: Dictionary) -> String:
	var rows := _step_log_rows(trace)
	var start_index: int = max(0, rows.size() - 12)
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
			rows.append("step %02d: %s accepted" % [step, _proposal_label(winner)])
		for loser_value in (resolution.get("losers", []) as Array):
			var loser: Dictionary = loser_value as Dictionary
			var proposal: Dictionary = loser.get("proposal", {}) as Dictionary
			rows.append("step %02d: %s rejected" % [step, _proposal_label(proposal)])
	return rows


func _proposal_label(proposal: Dictionary) -> String:
	var type := str(proposal.get("type", "proposal"))
	match type:
		"add_road_segment":
			return "road segment"
		"add_generic_plot":
			return "generic plot"
		"differentiate_plot":
			return "plot -> %s" % str((proposal.get("payload", {}) as Dictionary).get("use", "use"))
		"add_building_footprint":
			return "building footprint"
		"add_core_seed":
			return "core seed"
		_:
			return type


func _sample_cells(samples: Array) -> Dictionary:
	var result: Dictionary = {}
	for sample_value in samples:
		var sample: Dictionary = sample_value as Dictionary
		if float(sample.get("value", 0.0)) <= 0.0:
			continue
		var cell: Dictionary = sample.get("cell", {}) as Dictionary
		result["%d,%d" % [int(cell.get("x", 0)), int(cell.get("y", 0))]] = true
	return result


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
		for cell in _area_cells(plot.get("area", {}) as Dictionary):
			_add_cell(parent, "PlotCell_%d" % count, cell, Color(0.26, 0.58, 0.32, 0.52), Vector2(2, 2))
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


func _draw_rejected(parent: Control, trace: Dictionary) -> int:
	var count := 0
	for rejected_value in (trace.get("rejected_proposals", []) as Array):
		var rejected: Dictionary = rejected_value as Dictionary
		var cells := _proposal_cells(rejected)
		for cell in cells:
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
