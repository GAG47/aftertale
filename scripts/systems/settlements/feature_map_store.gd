class_name FeatureMapStore
extends RefCounted

const MAP_IDS := [
	"buildable",
	"occupied",
	"road",
	"plot",
	"reserved",
	"terrain_cost",
	"water",
	"obstacle",
	"accessibility",
	"road_distance",
	"entrance_distance",
	"edge_distance",
	"center_distance",
	"density_pressure",
	"district_pressure",
	"land_value",
]

var map_size: Vector2i = Vector2i.ZERO
var maps: Dictionary = {}
var update_count: int = 0
var last_committed_proposal_id: String = ""


func initialize(context: SettlementContext) -> void:
	map_size = context.map_size
	update_count = 0
	last_committed_proposal_id = ""
	rebuild_from_blueprint(context, null)


func rebuild_from_blueprint(context: SettlementContext, blueprint: SettlementBlueprint) -> void:
	map_size = context.map_size
	maps.clear()
	for map_id in MAP_IDS:
		maps[map_id] = {}

	var road_cells: Array[Vector2i] = _collect_road_cells(blueprint)
	var plot_cells: Array[Vector2i] = _collect_plot_cells(blueprint)
	var occupied_cells: Array[Vector2i] = _collect_occupied_cells(blueprint)
	var core_cells: Array[Vector2i] = _collect_core_cells(blueprint)
	var public_cells: Array[Vector2i] = _collect_public_cells(blueprint)

	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			var key := cell_key(cell)
			var obstacle := context.is_obstacle(cell)
			var water := context.existing_water.has(cell)
			var buildable := 0.0 if obstacle or water else 1.0
			var road_value := 1.0 if road_cells.has(cell) else 0.0
			var plot_value := 1.0 if plot_cells.has(cell) else 0.0
			var occupied_value := 1.0 if occupied_cells.has(cell) else 0.0
			(maps["buildable"] as Dictionary)[key] = buildable
			(maps["occupied"] as Dictionary)[key] = occupied_value
			(maps["road"] as Dictionary)[key] = road_value
			(maps["plot"] as Dictionary)[key] = plot_value
			(maps["reserved"] as Dictionary)[key] = maxf(road_value, maxf(plot_value, occupied_value))
			(maps["terrain_cost"] as Dictionary)[key] = 99.0 if buildable <= 0.0 else 1.0
			(maps["water"] as Dictionary)[key] = 1.0 if water else 0.0
			(maps["obstacle"] as Dictionary)[key] = 1.0 if obstacle else 0.0
			(maps["accessibility"] as Dictionary)[key] = 1.0 if buildable > 0.0 else 0.0
			(maps["road_distance"] as Dictionary)[key] = _nearest_distance(cell, road_cells, map_size.x + map_size.y)
			(maps["entrance_distance"] as Dictionary)[key] = _nearest_distance(cell, context.entrances, map_size.x + map_size.y)
			(maps["edge_distance"] as Dictionary)[key] = float(min(min(x, y), min(map_size.x - 1 - x, map_size.y - 1 - y)))
			(maps["center_distance"] as Dictionary)[key] = cell.distance_to(Vector2(map_size.x, map_size.y) * 0.5)
			(maps["density_pressure"] as Dictionary)[key] = _nearby_count(cell, occupied_cells, 3)
			(maps["district_pressure"] as Dictionary)[key] = _nearby_count(cell, plot_cells, 3)
			(maps["land_value"] as Dictionary)[key] = _land_value(cell, core_cells, road_cells, public_cells, obstacle)


func mark_committed(proposal: PlanProposal) -> void:
	update_count += 1
	last_committed_proposal_id = proposal.proposal_id if proposal != null else ""


func apply_committed_proposal(proposal: PlanProposal) -> void:
	mark_committed(proposal)


func get_value(map_id: String, cell: Vector2i, fallback: float = 0.0) -> float:
	if not maps.has(map_id):
		return fallback
	return float((maps[map_id] as Dictionary).get(cell_key(cell), fallback))


func is_buildable(cell: Vector2i) -> bool:
	return get_value("buildable", cell) > 0.0 and get_value("occupied", cell) <= 0.0


func is_reserved(cell: Vector2i) -> bool:
	return get_value("reserved", cell) > 0.0


func is_road(cell: Vector2i) -> bool:
	return get_value("road", cell) > 0.0


func occupied_count() -> int:
	var result := 0
	for value in (maps.get("occupied", {}) as Dictionary).values():
		if float(value) > 0.0:
			result += 1
	return result


func debug_map_sample(map_id: String, limit: int = 12) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not maps.has(map_id):
		return result
	for y in range(map_size.y):
		for x in range(map_size.x):
			if result.size() >= limit:
				return result
			var cell := Vector2i(x, y)
			result.append({
				"cell": { "x": x, "y": y },
				"value": get_value(map_id, cell),
			})
	return result


func to_dictionary() -> Dictionary:
	return {
		"map_size": { "width": map_size.x, "height": map_size.y },
		"map_ids": MAP_IDS.duplicate(),
		"update_count": update_count,
		"last_committed_proposal_id": last_committed_proposal_id,
		"occupied_count": occupied_count(),
		"buildable_sample": debug_map_sample("buildable"),
		"occupied_sample": debug_map_sample("occupied"),
		"road_sample": debug_map_sample("road"),
		"plot_sample": debug_map_sample("plot"),
		"land_value_sample": debug_map_sample("land_value"),
	}


func cells_for_map_value(map_id: String, threshold: float = 0.0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			if get_value(map_id, cell) > threshold:
				result.append(cell)
	return result


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _nearest_distance(cell: Vector2i, targets: Array[Vector2i], fallback: int) -> float:
	if targets.is_empty():
		return float(fallback)
	var best := fallback
	for target in targets:
		best = min(best, absi(cell.x - target.x) + absi(cell.y - target.y))
	return float(best)


static func _nearby_count(cell: Vector2i, targets: Array[Vector2i], radius: int) -> float:
	var count := 0
	for target in targets:
		if absi(cell.x - target.x) + absi(cell.y - target.y) <= radius:
			count += 1
	return float(count)


static func _land_value(cell: Vector2i, core_cells: Array[Vector2i], road_cells: Array[Vector2i], public_cells: Array[Vector2i], obstacle: bool) -> float:
	if obstacle:
		return -2.0
	var value := 0.0
	value += 3.0 / maxf(1.0, _nearest_distance(cell, core_cells, 99))
	value += 2.0 / maxf(1.0, _nearest_distance(cell, road_cells, 99))
	value += 2.0 / maxf(1.0, _nearest_distance(cell, public_cells, 99))
	return value


static func _collect_core_cells(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if blueprint == null:
		return result
	for core_value in blueprint.cores:
		var core: Dictionary = core_value as Dictionary
		result.append(_cell_from_variant(core.get("cell", {})))
	return result


static func _collect_road_cells(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if blueprint == null:
		return result
	for road_value in blueprint.roads:
		var road: Dictionary = road_value as Dictionary
		for cell_value in (road.get("path", []) as Array):
			var cell := _cell_from_variant(cell_value)
			if not result.has(cell):
				result.append(cell)
	return result


static func _collect_plot_cells(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if blueprint == null:
		return result
	for plot_value in blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		for cell in _area_cells(plot.get("area", {}) as Dictionary):
			if not result.has(cell):
				result.append(cell)
	return result


static func _collect_occupied_cells(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if blueprint == null:
		return result
	for building_value in blueprint.buildings:
		var building: Dictionary = building_value as Dictionary
		for cell in _area_cells(building.get("area", {}) as Dictionary):
			if not result.has(cell):
				result.append(cell)
	for landmark_value in blueprint.landmarks:
		var landmark: Dictionary = landmark_value as Dictionary
		var cell := _cell_from_variant(landmark.get("cell", {}))
		if not result.has(cell):
			result.append(cell)
	return result


static func _collect_public_cells(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if blueprint == null:
		return result
	for plot_value in blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		if str(plot.get("use", "")) != "public":
			continue
		for cell in _area_cells(plot.get("area", {}) as Dictionary):
			if not result.has(cell):
				result.append(cell)
	return result


static func _area_cells(area: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x0 := int(area.get("x", 0))
	var y0 := int(area.get("y", 0))
	var width := int(area.get("width", area.get("w", 0)))
	var height := int(area.get("height", area.get("h", 0)))
	for y in range(y0, y0 + height):
		for x in range(x0, x0 + width):
			result.append(Vector2i(x, y))
	return result


static func _cell_from_variant(value: Variant) -> Vector2i:
	if typeof(value) == TYPE_VECTOR2I:
		return value as Vector2i
	if typeof(value) == TYPE_DICTIONARY:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -9999)), int(data.get("y", -9999)))
	return Vector2i(-9999, -9999)
