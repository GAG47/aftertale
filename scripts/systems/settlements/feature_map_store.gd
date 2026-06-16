class_name FeatureMapStore
extends RefCounted

const MAP_IDS := [
	"buildable",
	"occupied",
	"terrain_cost",
	"accessibility",
	"road_distance",
	"water_distance",
	"entrance_distance",
	"edge_distance",
	"center_distance",
	"slope_or_roughness",
	"resource_proximity",
	"density_pressure",
	"district_pressure",
	"land_value",
	"danger",
	"beauty",
]

var map_size: Vector2i = Vector2i.ZERO
var maps: Dictionary = {}
var update_count: int = 0
var last_committed_proposal_id: String = ""


func initialize(context: SettlementContext) -> void:
	map_size = context.map_size
	maps.clear()
	for map_id in MAP_IDS:
		maps[map_id] = {}

	for y in range(map_size.y):
		for x in range(map_size.x):
			var cell := Vector2i(x, y)
			var key := cell_key(cell)
			var buildable := 0.0 if context.is_obstacle(cell) else 1.0
			(maps["buildable"] as Dictionary)[key] = buildable
			(maps["occupied"] as Dictionary)[key] = 0.0
			(maps["terrain_cost"] as Dictionary)[key] = 99.0 if buildable <= 0.0 else 1.0
			(maps["accessibility"] as Dictionary)[key] = 1.0 if buildable > 0.0 else 0.0
			(maps["road_distance"] as Dictionary)[key] = _nearest_distance(cell, context.existing_roads, map_size.x + map_size.y)
			(maps["water_distance"] as Dictionary)[key] = _nearest_distance(cell, context.existing_water, map_size.x + map_size.y)
			(maps["entrance_distance"] as Dictionary)[key] = _nearest_distance(cell, context.entrances, map_size.x + map_size.y)
			(maps["edge_distance"] as Dictionary)[key] = float(min(min(x, y), min(map_size.x - 1 - x, map_size.y - 1 - y)))
			(maps["center_distance"] as Dictionary)[key] = cell.distance_to(Vector2(map_size.x, map_size.y) * 0.5)
			(maps["slope_or_roughness"] as Dictionary)[key] = 0.0
			(maps["resource_proximity"] as Dictionary)[key] = 1.0 / maxf(1.0, _nearest_distance(cell, context.important_world_points, map_size.x + map_size.y))
			(maps["density_pressure"] as Dictionary)[key] = 0.0
			(maps["district_pressure"] as Dictionary)[key] = 0.0
			(maps["land_value"] as Dictionary)[key] = buildable * (1.0 / maxf(1.0, float((maps["entrance_distance"] as Dictionary)[key])))
			(maps["danger"] as Dictionary)[key] = 0.0
			(maps["beauty"] as Dictionary)[key] = buildable
	update_count = 0
	last_committed_proposal_id = ""


func apply_committed_proposal(proposal: PlanProposal) -> void:
	if proposal == null:
		return
	match proposal.type:
		"add_core", "add_anchor":
			_set_map_value("occupied", proposal.primary_cell(), 1.0)
			_raise_pressure_around(proposal.primary_cell())
		"add_landmark":
			_set_map_value("occupied", proposal.primary_cell(), 1.0)
			_raise_pressure_around(proposal.primary_cell())
			_raise_land_value_around(proposal.primary_cell(), 1.0)
		"add_path", "add_road":
			for cell in proposal.path:
				_set_map_value("road_distance", cell, 0.0)
				_set_map_value("accessibility", cell, 1.0)
				_raise_land_value_around(cell, 0.2)
		"add_plot":
			for cell in _area_cells(proposal.area):
				var current_value: float = get_value("district_pressure", cell)
				_set_map_value("district_pressure", cell, current_value + 0.5)
		"add_building":
			for cell in _area_cells(proposal.area):
				_set_map_value("occupied", cell, 1.0)
				_raise_pressure_around(cell)
	update_count += 1
	last_committed_proposal_id = proposal.proposal_id


func get_value(map_id: String, cell: Vector2i, fallback: float = 0.0) -> float:
	if not maps.has(map_id):
		return fallback
	return float((maps[map_id] as Dictionary).get(cell_key(cell), fallback))


func is_buildable(cell: Vector2i) -> bool:
	return get_value("buildable", cell) > 0.0 and get_value("occupied", cell) <= 0.0


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
	}


func _set_map_value(map_id: String, cell: Vector2i, value: float) -> void:
	if not maps.has(map_id):
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return
	(maps[map_id] as Dictionary)[cell_key(cell)] = value


func _raise_pressure_around(center: Vector2i) -> void:
	for direction in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell: Vector2i = center + direction
		var current: float = get_value("density_pressure", cell)
		_set_map_value("density_pressure", cell, current + 1.0)


func _raise_land_value_around(center: Vector2i, amount: float) -> void:
	for direction in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell: Vector2i = center + direction
		var current: float = get_value("land_value", cell)
		_set_map_value("land_value", cell, current + amount)


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


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func _nearest_distance(cell: Vector2i, targets: Array[Vector2i], fallback: int) -> float:
	if targets.is_empty():
		return float(fallback)
	var best := fallback
	for target in targets:
		best = min(best, absi(cell.x - target.x) + absi(cell.y - target.y))
	return float(best)
