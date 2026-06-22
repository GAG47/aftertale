class_name AgentSettlementPlanner
extends RefCounted

const DEFAULT_PLANNING_STEPS := 72
const MIN_WIDTH := 24
const MIN_HEIGHT := 18
const ROAD := "road_growth"
const PUBLIC_SPACE := "public_space"
const CIVILIAN_PLOT := "civilian_plot"
const RESIDENTIAL_BID := "residential_bid"
const SHOP_BID := "shop_bid"
const WORKSHOP_BID := "workshop_bid"
const TAVERN_BID := "tavern_bid"
const FARM_CLAIM := "farm_claim"
const TRAINING_CLAIM := "training_claim"
const GATE_CLAIM := "gate_claim"
const DECORATION_FILL := "decoration_fill"
const REQUIRED_ZONE_IDS: Array[String] = ["plaza", "residential", "market", "farm", "training", "gate"]
const REQUIRED_REQUEST_IDS: Array[String] = ["residential", "shop"]

const AVAILABLE_AGENTS: Array[String] = [
	ROAD,
	PUBLIC_SPACE,
	CIVILIAN_PLOT,
	RESIDENTIAL_BID,
	SHOP_BID,
	WORKSHOP_BID,
	TAVERN_BID,
	FARM_CLAIM,
	TRAINING_CLAIM,
	GATE_CLAIM,
	DECORATION_FILL,
]

var _rng := RandomNumberGenerator.new()


class FeatureMapSet:
	var width: int = 0
	var height: int = 0
	var maps: Dictionary = {}
	var score_maps: Dictionary = {}
	var road_distance: Dictionary = {}

	func _init(map_width: int = 0, map_height: int = 0) -> void:
		width = map_width
		height = map_height
		_reset()

	func rebuild_from_blueprint(blueprint: SettlementBlueprint) -> void:
		_reset()
		for road_value in blueprint.road_cells:
			set_bool("road_map", road_value as Vector2i, true)
		for rect_value in blueprint.special_rects():
			mark_rect("reserved_map", rect_value as Dictionary, true)
		for parcel_value in blueprint.generic_parcels:
			var parcel: Dictionary = parcel_value as Dictionary
			var parcel_cells: Array = parcel.get("cells", []) as Array
			if parcel_cells.is_empty():
				mark_rect("plot_map", parcel, true)
			else:
				for cell_value in parcel_cells:
					set_bool("plot_map", _cell_from_dict(cell_value as Dictionary), true)
			var access_cell := _cell_from_dict(parcel.get("access_cell", parcel.get("frontage_cell", {})) as Dictionary)
			set_bool("frontage_map", access_cell, true)
		_rebuild_road_distance(blueprint.road_cells)

	func set_bool(map_id: String, cell: Vector2i, value: bool) -> void:
		if not in_bounds(cell) or not maps.has(map_id):
			return
		var target: Dictionary = maps[map_id] as Dictionary
		var key := cell_key(cell)
		if value:
			target[key] = true
		else:
			target.erase(key)

	func get_bool(map_id: String, cell: Vector2i) -> bool:
		if not in_bounds(cell) or not maps.has(map_id):
			return false
		return bool((maps[map_id] as Dictionary).get(cell_key(cell), false))

	func score(map_id: String, cell: Vector2i) -> float:
		if not in_bounds(cell) or not score_maps.has(map_id):
			return 0.0
		return float((score_maps[map_id] as Dictionary).get(cell_key(cell), 0.0))

	func distance_to_road(cell: Vector2i) -> int:
		return int(road_distance.get(cell_key(cell), 9999))

	func mark_rect(map_id: String, rect: Dictionary, value: bool) -> void:
		for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
			for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
				set_bool(map_id, Vector2i(x, y), value)

	func rect_has_any(map_id: String, rect: Dictionary) -> bool:
		for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
			for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
				if get_bool(map_id, Vector2i(x, y)):
					return true
		return false

	func rect_in_bounds(rect: Dictionary) -> bool:
		if rect.is_empty():
			return false
		var x: int = int(rect.get("x", -1))
		var y: int = int(rect.get("y", -1))
		var w: int = int(rect.get("w", 0))
		var h: int = int(rect.get("h", 0))
		return w > 0 and h > 0 and in_bounds(Vector2i(x, y)) and in_bounds(Vector2i(x + w - 1, y + h - 1))

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

	func cell_key(cell: Vector2i) -> String:
		return "%d,%d" % [cell.x, cell.y]

	func summary() -> Dictionary:
		var result: Dictionary = {}
		for map_id in maps.keys():
			result[str(map_id)] = (maps[map_id] as Dictionary).size()
		return result

	func _reset() -> void:
		maps = {
			"walkable_map": {},
			"blocked_map": {},
			"road_map": {},
			"plot_map": {},
			"reserved_map": {},
			"frontage_map": {},
			"water_map": {},
		}
		score_maps = {
			"edge_score_map": {},
			"center_score_map": {},
			"quiet_score_map": {},
			"farm_score_map": {},
			"public_score_map": {},
		}
		road_distance.clear()
		var center := Vector2(float(width) * 0.50, float(height) * 0.56)
		for y in range(height):
			for x in range(width):
				var cell := Vector2i(x, y)
				var key := cell_key(cell)
				(maps["walkable_map"] as Dictionary)[key] = true
				var edge_distance: int = min(min(x, width - 1 - x), min(y, height - 1 - y))
				var center_distance := Vector2(float(x), float(y)).distance_to(center)
				(score_maps["edge_score_map"] as Dictionary)[key] = maxf(0.0, 18.0 - float(edge_distance))
				(score_maps["center_score_map"] as Dictionary)[key] = maxf(0.0, 30.0 - center_distance)
				(score_maps["quiet_score_map"] as Dictionary)[key] = float(edge_distance) + maxf(0.0, float(y) - float(height) * 0.45)
				(score_maps["farm_score_map"] as Dictionary)[key] = float(edge_distance)
				(score_maps["public_score_map"] as Dictionary)[key] = maxf(0.0, 26.0 - center_distance)

	func _rebuild_road_distance(road_cells: Array[Vector2i]) -> void:
		road_distance.clear()
		var frontier: Array[Vector2i] = []
		for road_cell in road_cells:
			if not in_bounds(road_cell):
				continue
			road_distance[cell_key(road_cell)] = 0
			frontier.append(road_cell)
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front() as Vector2i
			var current_distance: int = int(road_distance.get(cell_key(current), 0))
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var next_cell: Vector2i = current + direction
				if not in_bounds(next_cell):
					continue
				var key := cell_key(next_cell)
				if road_distance.has(key):
					continue
				road_distance[key] = current_distance + 1
				frontier.append(next_cell)

	func _cell_from_dict(value: Dictionary) -> Vector2i:
		return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


class SettlementBlueprint:
	var width: int = 0
	var height: int = 0
	var road_cells: Array[Vector2i] = []
	var road_cell_keys: Dictionary = {}
	var road_birth_step: Dictionary = {}
	var plaza: Dictionary = {}
	var farm: Dictionary = {}
	var training: Dictionary = {}
	var wild_gate: Dictionary = {}
	var generic_parcels: Array[Dictionary] = []
	var building_plans: Array[Dictionary] = []
	var decoration_slots: Array[Dictionary] = []
	var commit_log: Array[Dictionary] = []
	var rejected_log: Array[Dictionary] = []
	var auction_log: Array[Dictionary] = []
	var unmet_goals: Array[String] = []
	var state: Dictionary = {}

	func _init(map_width: int = 0, map_height: int = 0) -> void:
		width = map_width
		height = map_height

	func add_seed(cell: Vector2i) -> void:
		_commit_road_cells([cell + Vector2i.LEFT, cell, cell + Vector2i.RIGHT], 0)
		commit_log.append({
			"step": 0,
			"agent_id": "settlement_seed",
			"type": "road_path",
			"score": 0.0,
			"reason": "bootstrap road seed chosen from settlement suitability",
		})

	func commit(candidate: Dictionary, step: int) -> void:
		var candidate_type := str(candidate.get("type", ""))
		match candidate_type:
			"road_path":
				_commit_road_cells(candidate.get("cells", []) as Array, step)
			"plaza":
				plaza = (candidate.get("rect", {}) as Dictionary).duplicate(true)
			"farm":
				farm = (candidate.get("rect", {}) as Dictionary).duplicate(true)
			"training":
				training = (candidate.get("rect", {}) as Dictionary).duplicate(true)
			"gate":
				_commit_road_cells(candidate.get("road_cells", []) as Array, step)
				wild_gate = (candidate.get("rect", {}) as Dictionary).duplicate(true)
			"generic_parcel":
				var lot: Dictionary = candidate.get("lot", {}) as Dictionary
				lot["growth_step"] = step
				generic_parcels.append(lot.duplicate(true))
			"building_bid":
				_commit_building_bid(candidate, step)
			"decoration_slot":
				var slot: Dictionary = candidate.get("slot", {}) as Dictionary
				slot["growth_step"] = step
				decoration_slots.append(slot.duplicate(true))

		commit_log.append({
			"step": step,
			"agent_id": str(candidate.get("agent_id", "")),
			"type": candidate_type,
			"score": float(candidate.get("score", 0.0)),
			"reason": str(candidate.get("reason", "")),
		})

	func reject(candidate: Dictionary, reason: String, step: int) -> void:
		rejected_log.append({
			"step": step,
			"agent_id": str(candidate.get("agent_id", "")),
			"type": str(candidate.get("type", "")),
			"reason": reason,
		})

	func special_rects() -> Array[Dictionary]:
		var rects: Array[Dictionary] = []
		for rect_value in [plaza, farm, training, wild_gate]:
			var rect: Dictionary = rect_value as Dictionary
			if not rect.is_empty():
				rects.append(rect.duplicate(true))
		return rects

	func assigned_request_ids() -> Dictionary:
		var result: Dictionary = {}
		for plan_value in building_plans:
			var plan: Dictionary = plan_value as Dictionary
			var request: Dictionary = plan.get("request", {}) as Dictionary
			result[str(request.get("id", ""))] = true
		return result

	func assigned_request_id_list() -> Array[String]:
		var result: Array[String] = []
		for request_id in assigned_request_ids().keys():
			result.append(str(request_id))
		result.sort()
		return result

	func assigned_parcel_ids() -> Dictionary:
		var result: Dictionary = {}
		for plan_value in building_plans:
			var plan: Dictionary = plan_value as Dictionary
			var lot: Dictionary = plan.get("lot", {}) as Dictionary
			result[str(lot.get("parcel_id", ""))] = true
		return result

	func committed_agent_ids() -> Array[String]:
		var result: Array[String] = []
		for entry_value in commit_log:
			var entry: Dictionary = entry_value as Dictionary
			var agent_id := str(entry.get("agent_id", ""))
			if not agent_id.is_empty() and not result.has(agent_id):
				result.append(agent_id)
		return result

	func to_plan(feature_maps: FeatureMapSet, available_agents: Array[String], planning_steps: int) -> Dictionary:
		return {
			"source": "agent_settlement_blueprint",
			"default_layout_authority": "agent_settlement_planner",
			"uses_bsp_layout": false,
			"road_cells": road_cells.duplicate(),
			"plaza": plaza.duplicate(true),
			"farm": farm.duplicate(true),
			"training": training.duplicate(true),
			"wild_gate": wild_gate.duplicate(true),
			"frontage_candidates": generic_parcels.duplicate(true),
			"generic_parcels": generic_parcels.duplicate(true),
			"building_requests": building_plans.duplicate(true),
			"decoration_slots": decoration_slots.duplicate(true),
			"planning_summary": {
				"type": "agent_settlement_blueprint",
				"control_model": "open_growth_auction",
				"scripted_stage_sequence": false,
				"planning_steps": planning_steps,
				"commit_count": commit_log.size(),
				"auction_count": auction_log.size(),
				"rejection_count": rejected_log.size(),
				"available_agents": available_agents.duplicate(),
				"committed_agents": committed_agent_ids(),
				"feature_maps": feature_maps.summary(),
				"required_zone_ids": REQUIRED_ZONE_IDS.duplicate(),
				"required_request_ids": REQUIRED_REQUEST_IDS.duplicate(),
				"required_goal_policy": "priority_filtered_auction",
				"required_goal_failures": unmet_goals.duplicate(),
				"demand_model": "state_weighted_request_pool",
				"parcel_shape_model": "cell_set_organic_growth_lot",
				"generic_parcel_count": generic_parcels.size(),
				"building_plan_count": building_plans.size(),
				"assigned_request_ids": assigned_request_id_list(),
				"unassigned_parcel_count": maxi(0, generic_parcels.size() - assigned_parcel_ids().size()),
				"unmet_goals": unmet_goals.duplicate(),
				"commit_log": commit_log.duplicate(true),
				"auction_log": auction_log.duplicate(true),
				"rejected_log": rejected_log.duplicate(true),
			},
		}

	func _commit_road_cells(cells: Array, step: int) -> void:
		for cell_value in cells:
			var cell: Vector2i = cell_value as Vector2i
			if cell.x < 1 or cell.y < 1 or cell.x >= width - 1 or cell.y >= height - 1:
				continue
			var key := _cell_key(cell)
			if road_cell_keys.has(key):
				continue
			road_cell_keys[key] = true
			road_birth_step[key] = step
			road_cells.append(cell)

	func _commit_building_bid(candidate: Dictionary, step: int) -> void:
		var parcel_id := str(candidate.get("parcel_id", ""))
		var request: Dictionary = candidate.get("request", {}) as Dictionary
		var semantic_zone_id := str(candidate.get("semantic_zone_id", ""))
		for index in range(generic_parcels.size()):
			var parcel: Dictionary = generic_parcels[index] as Dictionary
			if str(parcel.get("parcel_id", "")) != parcel_id:
				continue
			parcel["semantic_zone_id"] = semantic_zone_id
			parcel["assigned_request_id"] = str(request.get("id", ""))
			parcel["assigned_step"] = step
			generic_parcels[index] = parcel
			building_plans.append({
				"request": request.duplicate(true),
				"lot": parcel.duplicate(true),
				"semantic_zone_id": semantic_zone_id,
				"agent_id": str(candidate.get("agent_id", "")),
				"growth_step": step,
				"bid_score": float(candidate.get("score", 0.0)),
			})
			return

	func _cell_key(cell: Vector2i) -> String:
		return "%d,%d" % [cell.x, cell.y]


func plan(context: Dictionary) -> Dictionary:
	var width: int = max(MIN_WIDTH, int(context.get("width", MIN_WIDTH)))
	var height: int = max(MIN_HEIGHT, int(context.get("height", MIN_HEIGHT)))
	var seed: int = int(context.get("seed", 5601))
	var planning_steps: int = int(context.get("planning_steps", DEFAULT_PLANNING_STEPS))
	var building_requests: Array[Dictionary] = []
	for request_value in (context.get("building_requests", []) as Array):
		building_requests.append((request_value as Dictionary).duplicate(true))
	_rng.seed = seed

	var blueprint := SettlementBlueprint.new(width, height)
	blueprint.add_seed(_seed_cell(width, height))
	var feature_maps := FeatureMapSet.new(width, height)

	for step in range(1, planning_steps + 1):
		feature_maps.rebuild_from_blueprint(blueprint)
		var candidates := _collect_candidates(blueprint, feature_maps, building_requests, step, planning_steps)
		var valid_candidates: Array[Dictionary] = []
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value as Dictionary
			var validation := _validate_candidate(candidate, blueprint, feature_maps)
			if bool(validation.get("valid", false)):
				valid_candidates.append(candidate)
			else:
				blueprint.reject(candidate, str(validation.get("reason", "invalid candidate")), step)
		if valid_candidates.is_empty():
			blueprint.auction_log.append({
				"step": step,
				"candidate_count": candidates.size(),
				"winner_agent": "",
				"winner_type": "",
				"winner_score": 0.0,
			})
			continue

		var winner := _choose_winner(valid_candidates, blueprint)
		blueprint.auction_log.append({
			"step": step,
			"candidate_count": valid_candidates.size(),
			"winner_agent": str(winner.get("agent_id", "")),
			"winner_type": str(winner.get("type", "")),
			"winner_score": float(winner.get("score", 0.0)),
		})
		blueprint.commit(winner, step)

	blueprint.unmet_goals = _audit_unmet_goals(blueprint)
	feature_maps.rebuild_from_blueprint(blueprint)
	return blueprint.to_plan(feature_maps, AVAILABLE_AGENTS, planning_steps)


func _collect_candidates(
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	building_requests: Array[Dictionary],
	step: int,
	planning_steps: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	candidates.append_array(_road_candidates(blueprint, features, step))
	candidates.append_array(_public_space_candidates(blueprint, features))
	candidates.append_array(_generic_plot_candidates(blueprint, features, building_requests, step))
	candidates.append_array(_building_bid_candidates(blueprint, features, building_requests))
	candidates.append_array(_farm_candidates(blueprint, features))
	candidates.append_array(_training_candidates(blueprint, features))
	candidates.append_array(_gate_candidates(blueprint, features))
	candidates.append_array(_decoration_candidates(blueprint, features, step, planning_steps))
	return candidates


func _road_candidates(blueprint: SettlementBlueprint, features: FeatureMapSet, step: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var samples := _road_frontier_samples(blueprint)
	var road_pressure := maxf(0.0, 28.0 - float(blueprint.road_cells.size()) * 1.25)
	road_pressure += _missing_pressure(blueprint, "road")
	for sample_value in samples:
		var start: Vector2i = sample_value as Vector2i
		for direction in _direction_order(start, blueprint.width, blueprint.height, step):
			var path := _build_road_path(start, direction, blueprint, features, step)
			if path.is_empty():
				continue
			var end_cell: Vector2i = path[path.size() - 1]
			var score := 16.0 + road_pressure
			score += features.score("edge_score_map", end_cell) * 0.35 if not blueprint.wild_gate.is_empty() else features.score("edge_score_map", end_cell) * 0.10
			score += _road_future_frontage_score(path, features) * 0.45
			score -= _road_local_density_penalty(path, features)
			score += _jitter(1.3)
			candidates.append({
				"type": "road_path",
				"agent_id": ROAD,
				"cells": path,
				"score": score,
				"reason": "extend current road network toward useful future frontage",
			})
	return candidates


func _public_space_candidates(blueprint: SettlementBlueprint, features: FeatureMapSet) -> Array[Dictionary]:
	if not blueprint.plaza.is_empty() or blueprint.road_cells.size() < 8:
		return []
	var candidates: Array[Dictionary] = []
	for road_cell in blueprint.road_cells:
		var degree := _road_degree(road_cell, blueprint)
		if degree < 2 and features.score("center_score_map", road_cell) < 20.0:
			continue
		var rect := _rect_around(road_cell, 6, 4, blueprint.width, blueprint.height)
		if not features.rect_in_bounds(rect):
			continue
		var score := 90.0 + _missing_pressure(blueprint, "plaza")
		score += float(degree) * 8.0
		score += features.score("public_score_map", road_cell)
		score += _jitter(1.0)
		candidates.append({
			"type": "plaza",
			"agent_id": PUBLIC_SPACE,
			"rect": rect,
			"score": score,
			"reason": "widen a road-supported social node into the village plaza",
		})
	return candidates


func _generic_plot_candidates(
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	building_requests: Array[Dictionary],
	step: int
) -> Array[Dictionary]:
	var unassigned_request_count := _unassigned_required_or_useful_requests(blueprint, building_requests).size()
	if unassigned_request_count <= 0:
		return []
	if blueprint.plaza.is_empty() and blueprint.road_cells.size() < 10:
		return []
	var candidates: Array[Dictionary] = []
	for road_cell in blueprint.road_cells:
		if road_cell.x < 2 or road_cell.y < 2 or road_cell.x > blueprint.width - 3 or road_cell.y > blueprint.height - 3:
			continue
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			for size in [Vector2i(7, 6), Vector2i(6, 6), Vector2i(7, 5)]:
				var lot := _organic_lot_from_road_access(road_cell, direction, size, blueprint, features, step, candidates.size())
				if lot.is_empty():
					continue
				lot["semantic_zone_id"] = ""
				lot["parcel_id"] = "growth_parcel_%03d_%02d" % [step, candidates.size() + 1]
				if not features.rect_in_bounds(lot):
					continue
				if _lot_has_any_feature(lot, features, ["road_map", "plot_map", "reserved_map"]):
					continue
				var score := 72.0 + minf(42.0, float(unassigned_request_count) * 10.0)
				if not blueprint.assigned_request_ids().has("residential"):
					score += 34.0
				if not blueprint.assigned_request_ids().has("shop"):
					score += 38.0
				score += features.score("quiet_score_map", road_cell) * 0.18
				score += features.score("public_score_map", road_cell) * 0.22
				score -= _plot_neighbor_penalty(lot, blueprint)
				score += _jitter(1.0)
				candidates.append({
					"type": "generic_parcel",
					"agent_id": CIVILIAN_PLOT,
					"lot": lot,
					"score": score,
					"reason": "claim a road-connected civilian plot with an independent access side",
				})
	return candidates


func _building_bid_candidates(
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	building_requests: Array[Dictionary]
) -> Array[Dictionary]:
	var assigned_parcels := blueprint.assigned_parcel_ids()
	var assigned_requests := blueprint.assigned_request_ids()
	var candidates: Array[Dictionary] = []
	for parcel_value in blueprint.generic_parcels:
		var parcel: Dictionary = parcel_value as Dictionary
		var parcel_id := str(parcel.get("parcel_id", ""))
		if assigned_parcels.has(parcel_id):
			continue
		for request_value in building_requests:
			var request: Dictionary = request_value as Dictionary
			var request_id := str(request.get("id", ""))
			if assigned_requests.has(request_id):
				continue
			var agent_id := _bid_agent_for_request(request_id)
			if agent_id.is_empty():
				continue
			var bid_score := _score_building_bid(parcel, request, blueprint, features)
			if bid_score <= -INF * 0.5:
				continue
			candidates.append({
				"type": "building_bid",
				"agent_id": agent_id,
				"parcel_id": parcel_id,
				"request": request.duplicate(true),
				"semantic_zone_id": _semantic_zone_for_request(request),
				"score": bid_score,
				"reason": "bid to differentiate a generic civilian plot through local utility",
			})
	return candidates


func _farm_candidates(blueprint: SettlementBlueprint, features: FeatureMapSet) -> Array[Dictionary]:
	if not blueprint.farm.is_empty() or blueprint.road_cells.size() < 10:
		return []
	var candidates: Array[Dictionary] = []
	for rect_value in _farm_site_rects(blueprint):
		var rect: Dictionary = rect_value as Dictionary
		if not features.rect_in_bounds(rect):
			continue
		var access_cell := _rect_road_access_cell(rect, blueprint, features)
		if access_cell == Vector2i(-1, -1):
			continue
		rect["access_cell"] = _dict_cell(access_cell)
		var center_cell := _rect_center_cell(rect)
		var score := 42.0 + _missing_pressure(blueprint, "farm")
		score += features.score("edge_score_map", center_cell) * 0.35
		score += maxf(0.0, 18.0 - _near_same_role_rect_penalty(rect, blueprint, "home"))
		score += maxf(0.0, 24.0 - float(features.distance_to_road(center_cell)) * 2.4)
		score += _jitter(1.0)
		candidates.append({
			"type": "farm",
			"agent_id": FARM_CLAIM,
			"rect": rect,
			"score": score,
			"reason": "claim an edge-connected open patch as farm land",
		})
	return candidates


func _training_candidates(blueprint: SettlementBlueprint, features: FeatureMapSet) -> Array[Dictionary]:
	if not blueprint.training.is_empty() or blueprint.road_cells.size() < 10:
		return []
	var candidates: Array[Dictionary] = []
	for rect_value in _training_site_rects(blueprint):
		var rect: Dictionary = rect_value as Dictionary
		if not features.rect_in_bounds(rect):
			continue
		var access_cell := _rect_road_access_cell(rect, blueprint, features)
		if access_cell == Vector2i(-1, -1):
			continue
		rect["access_cell"] = _dict_cell(access_cell)
		var center_cell := _rect_center_cell(rect)
		var score := 42.0 + _missing_pressure(blueprint, "training")
		score += features.score("edge_score_map", center_cell) * 0.45
		score += maxf(0.0, 22.0 - float(features.distance_to_road(center_cell)) * 2.2)
		score += _jitter(1.0)
		candidates.append({
			"type": "training",
			"agent_id": TRAINING_CLAIM,
			"rect": rect,
			"score": score,
			"reason": "claim a reachable edge yard for guard training",
		})
	return candidates


func _gate_candidates(blueprint: SettlementBlueprint, features: FeatureMapSet) -> Array[Dictionary]:
	if not blueprint.wild_gate.is_empty() or blueprint.road_cells.size() < 12:
		return []
	var candidates: Array[Dictionary] = []
	for road_cell in blueprint.road_cells:
		if road_cell.x < int(float(blueprint.width) * 0.65):
			continue
		var y := clampi(road_cell.y - 1, 1, blueprint.height - 4)
		var gate_anchor := Vector2i(blueprint.width - 3, y + 1)
		var road_cells := _horizontal_path(road_cell, gate_anchor)
		if road_cells.is_empty():
			continue
		var blocked := false
		for cell in road_cells:
			if features.get_bool("plot_map", cell) or features.get_bool("reserved_map", cell):
				blocked = true
				break
		if blocked:
			continue
		var rect := _clamped_rect({ "x": blueprint.width - 6, "y": y, "w": 5, "h": 3 }, blueprint.width, blueprint.height)
		rect["access_cell"] = _dict_cell(gate_anchor)
		var score := 36.0 + _missing_pressure(blueprint, "gate")
		score += features.score("edge_score_map", gate_anchor)
		score -= float(absi(road_cell.y - y)) * 1.5
		score += _jitter(1.0)
		candidates.append({
			"type": "gate",
			"agent_id": GATE_CLAIM,
			"rect": rect,
			"road_cells": road_cells,
			"score": score,
			"reason": "claim a road-reachable edge exit and guard post source",
		})
	return candidates


func _decoration_candidates(
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	step: int,
	planning_steps: int
) -> Array[Dictionary]:
	if step < int(float(planning_steps) * 0.65) and not _critical_goals_met(blueprint):
		return []
	if blueprint.decoration_slots.size() >= 6:
		return []
	var candidates: Array[Dictionary] = []
	for road_cell in blueprint.road_cells:
		for offset in [Vector2i(0, 2), Vector2i(-1, 1), Vector2i(1, 1)]:
			var cell: Vector2i = road_cell + offset
			if not features.in_bounds(cell):
				continue
			if features.get_bool("road_map", cell) or features.get_bool("plot_map", cell) or features.get_bool("reserved_map", cell):
				continue
			var score := 5.0 + float(step) * 0.05 + _jitter(0.5)
			candidates.append({
				"type": "decoration_slot",
				"agent_id": DECORATION_FILL,
				"slot": {
					"type": "grass_clump" if (cell.x + cell.y) % 2 == 0 else "stone",
					"grid_position": _dict_cell(cell),
					"blocks_movement": false,
				},
				"score": score,
				"reason": "fill non-critical residual space after growth pressure eases",
			})
	return candidates


func _validate_candidate(candidate: Dictionary, blueprint: SettlementBlueprint, features: FeatureMapSet) -> Dictionary:
	match str(candidate.get("type", "")):
		"road_path":
			return _validate_road(candidate, blueprint, features)
		"plaza", "gate":
			return _validate_special(candidate, blueprint, features, true)
		"farm", "training":
			return _validate_special(candidate, blueprint, features, false)
		"generic_parcel":
			return _validate_generic_parcel(candidate, features)
		"building_bid":
			return _validate_building_bid(candidate, blueprint)
		"decoration_slot":
			return _validate_decoration(candidate, features)
		_:
			return { "valid": false, "reason": "unknown candidate type" }


func _validate_road(candidate: Dictionary, blueprint: SettlementBlueprint, features: FeatureMapSet) -> Dictionary:
	var cells: Array = candidate.get("cells", []) as Array
	if cells.is_empty():
		return { "valid": false, "reason": "road path is empty" }
	var connected := false
	for cell_value in cells:
		var cell: Vector2i = cell_value as Vector2i
		if not features.in_bounds(cell):
			return { "valid": false, "reason": "road cell out of bounds" }
		if features.get_bool("plot_map", cell) or features.get_bool("reserved_map", cell):
			return { "valid": false, "reason": "road conflicts with plot or reserved area" }
		if blueprint.road_cell_keys.has(_cell_key(cell)):
			connected = true
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if blueprint.road_cell_keys.has(_cell_key(cell + direction)):
				connected = true
	if not connected:
		return { "valid": false, "reason": "road path is not connected" }
	return { "valid": true }


func _validate_special(candidate: Dictionary, blueprint: SettlementBlueprint, features: FeatureMapSet, allow_road_overlap: bool) -> Dictionary:
	var rect: Dictionary = candidate.get("rect", {}) as Dictionary
	if not features.rect_in_bounds(rect):
		return { "valid": false, "reason": "special area out of bounds" }
	for other_value in blueprint.special_rects():
		if _rects_overlap(rect, other_value as Dictionary, 1):
			return { "valid": false, "reason": "special area overlaps another claim" }
	if features.rect_has_any("plot_map", rect):
		return { "valid": false, "reason": "special area overlaps plot" }
	if not allow_road_overlap and features.rect_has_any("road_map", rect):
		return { "valid": false, "reason": "special area blocks existing road" }
	if not allow_road_overlap:
		var access_cell := _cell_from_dict(rect.get("access_cell", {}) as Dictionary)
		if access_cell == Vector2i(-1, -1) or not _cell_touches_road(access_cell, blueprint):
			return { "valid": false, "reason": "special area has no planned road access" }
	return { "valid": true }


func _validate_generic_parcel(candidate: Dictionary, features: FeatureMapSet) -> Dictionary:
	var lot: Dictionary = candidate.get("lot", {}) as Dictionary
	if not features.rect_in_bounds(lot):
		return { "valid": false, "reason": "plot out of bounds" }
	if _lot_has_any_feature(lot, features, ["road_map", "plot_map", "reserved_map"]):
		return { "valid": false, "reason": "plot conflicts with road, plot, or reserved area" }
	var frontage_cell := _cell_from_dict(lot.get("frontage_cell", {}) as Dictionary)
	if not features.get_bool("road_map", frontage_cell):
		return { "valid": false, "reason": "plot frontage is not on road" }
	var access_cell := _cell_from_dict(lot.get("access_cell", {}) as Dictionary)
	if not features.in_bounds(access_cell) or not _rect_contains_cell(lot, access_cell):
		return { "valid": false, "reason": "plot access cell is not inside the plot" }
	if not _cell_adjacent(access_cell, frontage_cell):
		return { "valid": false, "reason": "plot access cell does not touch planned road" }
	var cells: Array = lot.get("cells", []) as Array
	if cells.is_empty():
		return { "valid": false, "reason": "plot has no cell-set shape" }
	var has_access_cell := false
	for cell_value in cells:
		if _cell_from_dict(cell_value as Dictionary) == access_cell:
			has_access_cell = true
			break
	if not has_access_cell:
		return { "valid": false, "reason": "plot cell-set does not include access cell" }
	if not _lot_has_south_door_core_candidate(lot):
		return { "valid": false, "reason": "plot cell-set cannot host a south-door building core" }
	return { "valid": true }


func _validate_building_bid(candidate: Dictionary, blueprint: SettlementBlueprint) -> Dictionary:
	var request: Dictionary = candidate.get("request", {}) as Dictionary
	var request_id := str(request.get("id", ""))
	if request_id.is_empty():
		return { "valid": false, "reason": "bid has no request id" }
	if blueprint.assigned_request_ids().has(request_id):
		return { "valid": false, "reason": "request already assigned" }
	var parcel_id := str(candidate.get("parcel_id", ""))
	if parcel_id.is_empty() or blueprint.assigned_parcel_ids().has(parcel_id):
		return { "valid": false, "reason": "parcel missing or already assigned" }
	for parcel_value in blueprint.generic_parcels:
		var parcel: Dictionary = parcel_value as Dictionary
		if str(parcel.get("parcel_id", "")) == parcel_id:
			return { "valid": true }
	return { "valid": false, "reason": "bid references missing parcel" }


func _validate_decoration(candidate: Dictionary, features: FeatureMapSet) -> Dictionary:
	var slot: Dictionary = candidate.get("slot", {}) as Dictionary
	var cell := _cell_from_dict(slot.get("grid_position", {}) as Dictionary)
	if not features.in_bounds(cell):
		return { "valid": false, "reason": "decoration out of bounds" }
	if features.get_bool("road_map", cell) or features.get_bool("plot_map", cell) or features.get_bool("reserved_map", cell):
		return { "valid": false, "reason": "decoration overlaps critical map" }
	return { "valid": true }


func _choose_winner(candidates: Array[Dictionary], blueprint: SettlementBlueprint) -> Dictionary:
	var eligible := candidates
	if not _critical_goals_met(blueprint):
		var direct_required_candidates: Array[Dictionary] = []
		var support_required_candidates: Array[Dictionary] = []
		for candidate_value in candidates:
			var candidate: Dictionary = candidate_value as Dictionary
			if _candidate_advances_required_goal(candidate, blueprint):
				if str(candidate.get("type", "")) == "road_path":
					support_required_candidates.append(candidate)
				else:
					direct_required_candidates.append(candidate)
		if not direct_required_candidates.is_empty():
			eligible = direct_required_candidates
		elif not support_required_candidates.is_empty():
			eligible = support_required_candidates
	var best: Dictionary = eligible[0] as Dictionary
	var best_score := float(best.get("score", -INF))
	for candidate_value in eligible:
		var candidate: Dictionary = candidate_value as Dictionary
		var score := float(candidate.get("score", -INF))
		if score > best_score:
			best = candidate
			best_score = score
	return best


func _candidate_advances_required_goal(candidate: Dictionary, blueprint: SettlementBlueprint) -> bool:
	var candidate_type := str(candidate.get("type", ""))
	var missing_land_claims := _missing_required_land_claims(blueprint)
	match candidate_type:
		"road_path":
			return not _critical_goals_met(blueprint)
		"plaza":
			return missing_land_claims.has("plaza")
		"farm":
			return not missing_land_claims.has("plaza") and missing_land_claims.has("farm")
		"training":
			return not missing_land_claims.has("plaza") and missing_land_claims.has("training")
		"gate":
			return not missing_land_claims.has("plaza") and missing_land_claims.has("gate")
		"generic_parcel":
			if not missing_land_claims.is_empty():
				return false
			var assigned := blueprint.assigned_request_ids()
			for request_id in REQUIRED_REQUEST_IDS:
				if not assigned.has(request_id):
					return true
			return false
		"building_bid":
			if not missing_land_claims.is_empty():
				return false
			var request: Dictionary = candidate.get("request", {}) as Dictionary
			var request_id := str(request.get("id", ""))
			return REQUIRED_REQUEST_IDS.has(request_id) and not blueprint.assigned_request_ids().has(request_id)
		_:
			return false


func _missing_required_land_claims(blueprint: SettlementBlueprint) -> Array[String]:
	var missing: Array[String] = []
	if blueprint.plaza.is_empty():
		missing.append("plaza")
	if blueprint.farm.is_empty():
		missing.append("farm")
	if blueprint.training.is_empty():
		missing.append("training")
	if blueprint.wild_gate.is_empty():
		missing.append("gate")
	return missing


func _score_building_bid(parcel: Dictionary, request: Dictionary, blueprint: SettlementBlueprint, features: FeatureMapSet) -> float:
	var request_id := str(request.get("id", ""))
	var center := _rect_center(parcel)
	var frontage_cell := _cell_from_dict(parcel.get("frontage_cell", {}) as Dictionary)
	var pressure := _request_pressure(request_id, blueprint)
	if pressure <= 0.0:
		return -INF
	var score := 18.0 + pressure
	if request_id == "residential" or request_id == "worker_cottage" or request_id == "farmer_cottage":
		score += features.score("quiet_score_map", frontage_cell) * 0.65
		score += _near_same_role_bonus(parcel, blueprint, "home")
	elif request_id == "shop":
		score += _near_plaza_bonus(parcel, blueprint) * 1.6
		score += features.score("public_score_map", frontage_cell) * 0.8
	elif request_id == "workshop":
		score += features.score("edge_score_map", frontage_cell) * 0.45
		score -= _near_same_role_bonus(parcel, blueprint, "home") * 0.35
	elif request_id == "tavern":
		score += _near_plaza_bonus(parcel, blueprint) * 1.2
		score += features.score("public_score_map", frontage_cell) * 0.55
	elif request_id == "guardhouse":
		score += _near_gate_bonus(parcel, blueprint) * 1.5
	score += maxf(0.0, 18.0 - center.distance_to(Vector2(float(blueprint.width) * 0.5, float(blueprint.height) * 0.5)) * 0.35)
	score += _jitter(0.8)
	return score


func _missing_pressure(blueprint: SettlementBlueprint, goal: String) -> float:
	var assigned := blueprint.assigned_request_ids()
	match goal:
		"road":
			return 42.0 if blueprint.road_cells.size() < 26 else 0.0
		"plaza":
			return 58.0 if blueprint.plaza.is_empty() else 0.0
		"farm":
			return 116.0 if blueprint.farm.is_empty() else 0.0
		"training":
			return 118.0 if blueprint.training.is_empty() else 0.0
		"gate":
			return 42.0 if blueprint.wild_gate.is_empty() else 0.0
		"residential":
			return 72.0 if not assigned.has("residential") else 0.0
		"shop":
			return 76.0 if not assigned.has("shop") else 0.0
		"workshop":
			return _request_pressure("workshop", blueprint)
		"tavern":
			return _request_pressure("tavern", blueprint)
		"farmer_cottage":
			return _request_pressure("farmer_cottage", blueprint)
		"worker_cottage":
			return _request_pressure("worker_cottage", blueprint)
		"storage_shed":
			return _request_pressure("storage_shed", blueprint)
		"guardhouse":
			return _request_pressure("guardhouse", blueprint)
		_:
			return 0.0


func _audit_unmet_goals(blueprint: SettlementBlueprint) -> Array[String]:
	var missing: Array[String] = []
	var assigned := blueprint.assigned_request_ids()
	if blueprint.plaza.is_empty():
		missing.append("plaza")
	if blueprint.farm.is_empty():
		missing.append("farm")
	if blueprint.training.is_empty():
		missing.append("training")
	if blueprint.wild_gate.is_empty():
		missing.append("gate")
	if not assigned.has("residential"):
		missing.append("residential")
	if not assigned.has("shop"):
		missing.append("shop")
	return missing


func _critical_goals_met(blueprint: SettlementBlueprint) -> bool:
	return _audit_unmet_goals(blueprint).is_empty()


func _unassigned_required_or_useful_requests(blueprint: SettlementBlueprint, building_requests: Array[Dictionary]) -> Array[Dictionary]:
	var assigned := blueprint.assigned_request_ids()
	var result: Array[Dictionary] = []
	for request_value in building_requests:
		var request: Dictionary = request_value as Dictionary
		var request_id := str(request.get("id", ""))
		if assigned.has(request_id):
			continue
		if request_id in ["residential", "shop", "workshop", "tavern", "farmer_cottage", "worker_cottage", "storage_shed", "guardhouse"] \
			and _request_pressure(request_id, blueprint) > 0.0:
			result.append(request)
	return result


func _road_frontier_samples(blueprint: SettlementBlueprint) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for road_cell in blueprint.road_cells:
		if _road_degree(road_cell, blueprint) <= 1:
			result.append(road_cell)
	for road_cell in blueprint.road_cells:
		if result.size() >= 10:
			break
		if not result.has(road_cell) and (road_cell.x + road_cell.y) % 5 == 0:
			result.append(road_cell)
	return result


func _direction_order(cell: Vector2i, width: int, height: int, step: int) -> Array[Vector2i]:
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var center := Vector2(float(width) * 0.5, float(height) * 0.56)
	directions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var score_a := Vector2(float(cell.x + a.x * 3), float(cell.y + a.y * 3)).distance_to(center)
		var score_b := Vector2(float(cell.x + b.x * 3), float(cell.y + b.y * 3)).distance_to(center)
		return score_a < score_b if step < 18 else score_a > score_b
	)
	return directions


func _build_road_path(
	start: Vector2i,
	direction: Vector2i,
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	step: int
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := start
	var length := 2 + int(absf(sin(float(start.x * 13 + start.y * 7 + step))) * 3.0)
	var current_direction := direction
	for index in range(length):
		if index == 2 and (start.x + start.y + step) % 3 == 0:
			current_direction = Vector2i(current_direction.y, current_direction.x)
			if current_direction == Vector2i.ZERO:
				current_direction = direction
		cursor += current_direction
		if cursor.x < 1 or cursor.y < 1 or cursor.x >= blueprint.width - 1 or cursor.y >= blueprint.height - 1:
			break
		if features.get_bool("plot_map", cursor) or features.get_bool("reserved_map", cursor):
			break
		path.append(cursor)
	return path


func _road_future_frontage_score(path: Array[Vector2i], features: FeatureMapSet) -> float:
	var score := 0.0
	for cell in path:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var probe := _lot_envelope_from_road_access(cell, direction, Vector2i(7, 6), features.width, features.height)
			if probe.is_empty():
				continue
			if features.rect_in_bounds(probe) and not features.rect_has_any("road_map", probe) and not features.rect_has_any("plot_map", probe) and not features.rect_has_any("reserved_map", probe):
				score += 2.0
	return score


func _road_local_density_penalty(path: Array[Vector2i], features: FeatureMapSet) -> float:
	var penalty := 0.0
	for cell in path:
		var neighbors := 0
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if features.get_bool("road_map", cell + direction):
				neighbors += 1
		if neighbors > 2:
			penalty += float(neighbors - 2) * 4.0
	return penalty


func _lot_envelope_from_road_access(road_cell: Vector2i, direction: Vector2i, size: Vector2i, width: int, height: int) -> Dictionary:
	var x := road_cell.x - int(size.x / 2)
	var y := road_cell.y - int(size.y / 2)
	var access_side := ""
	if direction == Vector2i.UP:
		x = road_cell.x - int(size.x / 2)
		y = road_cell.y - size.y
		access_side = "south"
	elif direction == Vector2i.DOWN:
		x = road_cell.x - int(size.x / 2)
		y = road_cell.y + 1
		access_side = "north"
	elif direction == Vector2i.LEFT:
		x = road_cell.x - size.x
		y = road_cell.y - int(size.y / 2)
		access_side = "east"
	elif direction == Vector2i.RIGHT:
		x = road_cell.x + 1
		y = road_cell.y - int(size.y / 2)
		access_side = "west"
	else:
		return {}

	var lot := { "x": x, "y": y, "w": size.x, "h": size.y }
	if x < 1 or y < 1 or x + size.x >= width - 1 or y + size.y >= height - 1:
		return {}
	var access_cell := road_cell + direction
	if not _rect_contains_cell(lot, access_cell):
		return {}
	lot["frontage_cell"] = _dict_cell(road_cell)
	lot["access_cell"] = _dict_cell(access_cell)
	lot["access_side"] = access_side
	lot["frontage_side"] = access_side
	return lot


func _organic_lot_from_road_access(
	road_cell: Vector2i,
	direction: Vector2i,
	size: Vector2i,
	blueprint: SettlementBlueprint,
	features: FeatureMapSet,
	step: int,
	variant_index: int
) -> Dictionary:
	var lot := _lot_envelope_from_road_access(road_cell, direction, size, blueprint.width, blueprint.height)
	if lot.is_empty():
		return {}
	var access_cell := _cell_from_dict(lot.get("access_cell", {}) as Dictionary)
	var grown_cells := _grow_organic_lot_cells(lot, access_cell, direction, features, step, variant_index)
	if grown_cells.size() < 18:
		return {}
	var bounds := _bounds_from_cells(grown_cells)
	lot["x"] = int(bounds.get("x", int(lot.get("x", 0))))
	lot["y"] = int(bounds.get("y", int(lot.get("y", 0))))
	lot["w"] = int(bounds.get("w", int(lot.get("w", 0))))
	lot["h"] = int(bounds.get("h", int(lot.get("h", 0))))
	lot["shape_model"] = "cell_set_organic_growth_lot"
	lot["growth_model"] = "frontier_expansion_from_road_access"
	lot["cells"] = _dict_path(grown_cells)
	lot["cell_count"] = grown_cells.size()
	lot["organic_target_cell_count"] = _organic_target_cell_count(size, step, variant_index)
	return lot


func _grow_organic_lot_cells(
	envelope: Dictionary,
	access_cell: Vector2i,
	direction: Vector2i,
	features: FeatureMapSet,
	step: int,
	variant_index: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var cell_keys: Dictionary = {}
	if not _organic_lot_cell_allowed(access_cell, envelope, features):
		return cells
	_add_lot_growth_cell(cells, cell_keys, access_cell)

	var core_rect := _organic_core_rect(envelope)
	for y in range(int(core_rect.get("y", 0)), int(core_rect.get("y", 0)) + int(core_rect.get("h", 0))):
		for x in range(int(core_rect.get("x", 0)), int(core_rect.get("x", 0)) + int(core_rect.get("w", 0))):
			var core_cell := Vector2i(x, y)
			if _organic_lot_cell_allowed(core_cell, envelope, features):
				_add_lot_growth_cell(cells, cell_keys, core_cell)

	var core_center := _rect_center_cell(core_rect)
	for path_cell in _simple_axis_path(access_cell, core_center):
		if _organic_lot_cell_allowed(path_cell, envelope, features):
			_add_lot_growth_cell(cells, cell_keys, path_cell)

	var target_count := _organic_target_cell_count(Vector2i(int(envelope.get("w", 0)), int(envelope.get("h", 0))), step, variant_index)
	while cells.size() < target_count:
		var best_cell := Vector2i(-1, -1)
		var best_score := -INF
		for current in cells:
			for neighbor_direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var candidate: Vector2i = current + neighbor_direction
				var key := _cell_key(candidate)
				if cell_keys.has(key):
					continue
				if not _organic_lot_cell_allowed(candidate, envelope, features):
					continue
				var score := _organic_growth_score(candidate, access_cell, direction, envelope, step, variant_index)
				if score > best_score:
					best_score = score
					best_cell = candidate
		if best_cell == Vector2i(-1, -1):
			break
		_add_lot_growth_cell(cells, cell_keys, best_cell)
	return cells


func _organic_lot_cell_allowed(cell: Vector2i, envelope: Dictionary, features: FeatureMapSet) -> bool:
	if not _rect_contains_cell(envelope, cell):
		return false
	if not features.in_bounds(cell):
		return false
	return not features.get_bool("road_map", cell) \
		and not features.get_bool("plot_map", cell) \
		and not features.get_bool("reserved_map", cell)


func _organic_core_rect(envelope: Dictionary) -> Dictionary:
	var x0: int = int(envelope.get("x", 0))
	var y0: int = int(envelope.get("y", 0))
	var w: int = int(envelope.get("w", 0))
	var h: int = int(envelope.get("h", 0))
	var core_w: int = clampi(w - 2, 3, 5)
	var core_h: int = clampi(h - 2, 3, 4)
	return {
		"x": x0 + max(1, int((w - core_w) / 2)),
		"y": y0 + max(1, int((h - core_h) / 2)),
		"w": core_w,
		"h": core_h,
	}


func _organic_target_cell_count(size: Vector2i, step: int, variant_index: int) -> int:
	var area := size.x * size.y
	var wobble := absi((step * 17 + variant_index * 11 + size.x * 5 + size.y * 7) % 5)
	return clampi(int(float(area) * 0.76) + wobble, min(18, area), max(18, area - 4))


func _organic_growth_score(
	cell: Vector2i,
	access_cell: Vector2i,
	direction: Vector2i,
	envelope: Dictionary,
	step: int,
	variant_index: int
) -> float:
	var center := _rect_center(envelope)
	var cell_center := Vector2(float(cell.x), float(cell.y))
	var distance_to_center := cell_center.distance_to(center)
	var distance_to_access := float(absi(cell.x - access_cell.x) + absi(cell.y - access_cell.y))
	var directional_depth := float((cell.x - access_cell.x) * direction.x + (cell.y - access_cell.y) * direction.y)
	var edge_noise := _hash_noise(cell, step, variant_index)
	var edge_penalty := 0.0
	if _is_rect_cornerish(envelope, cell):
		edge_penalty += 2.5
	return 20.0 \
		- distance_to_center * 1.2 \
		- distance_to_access * 0.25 \
		+ directional_depth * 0.45 \
		+ edge_noise * 4.0 \
		- edge_penalty


func _add_lot_growth_cell(cells: Array[Vector2i], cell_keys: Dictionary, cell: Vector2i) -> void:
	var key := _cell_key(cell)
	if cell_keys.has(key):
		return
	cell_keys[key] = true
	cells.append(cell)


func _simple_axis_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if to_cell.x > cursor.x else -1
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if to_cell.y > cursor.y else -1
		path.append(cursor)
	return path


func _bounds_from_cells(cells: Array[Vector2i]) -> Dictionary:
	if cells.is_empty():
		return {}
	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_y := cells[0].y
	var max_y := cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return { "x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1 }


func _is_rect_cornerish(rect: Dictionary, cell: Vector2i) -> bool:
	var x0: int = int(rect.get("x", 0))
	var y0: int = int(rect.get("y", 0))
	var x1: int = x0 + int(rect.get("w", 0)) - 1
	var y1: int = y0 + int(rect.get("h", 0)) - 1
	return (cell.x == x0 or cell.x == x1) and (cell.y == y0 or cell.y == y1)


func _hash_noise(cell: Vector2i, step: int, variant_index: int) -> float:
	var value := int(cell.x * 73856093) ^ int(cell.y * 19349663) ^ int(step * 83492791) ^ int(variant_index * 2654435761)
	value = abs(value % 1000)
	return float(value) / 999.0


func _lot_has_any_feature(lot: Dictionary, features: FeatureMapSet, map_ids: Array[String]) -> bool:
	var cells: Array = lot.get("cells", []) as Array
	if cells.is_empty():
		for map_id in map_ids:
			if features.rect_has_any(map_id, lot):
				return true
		return false
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		for map_id in map_ids:
			if features.get_bool(map_id, cell):
				return true
	return false


func _lot_has_south_door_core_candidate(lot: Dictionary) -> bool:
	var cells: Array = lot.get("cells", []) as Array
	if cells.is_empty():
		return false
	var cell_keys: Dictionary = {}
	for cell_value in cells:
		var cell := _cell_from_dict(cell_value as Dictionary)
		cell_keys[_cell_key(cell)] = true
	var x0: int = int(lot.get("x", 0))
	var y0: int = int(lot.get("y", 0))
	var w: int = int(lot.get("w", 0))
	var h: int = int(lot.get("h", 0))
	for y in range(y0, y0 + h - 3):
		for x in range(x0, x0 + w - 3):
			var rect := { "x": x, "y": y, "w": 4, "h": 3 }
			if not _rect_inside_cell_keys(rect, cell_keys):
				continue
			var door := Vector2i(x + 2, y + 2)
			var step := door + Vector2i.DOWN
			if cell_keys.has(_cell_key(door)) and cell_keys.has(_cell_key(step)):
				return true
	return false


func _rect_inside_cell_keys(rect: Dictionary, cell_keys: Dictionary) -> bool:
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			if not cell_keys.has(_cell_key(Vector2i(x, y))):
				return false
	return true


func _horizontal_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := from_cell
	var step := 1 if to_cell.x >= from_cell.x else -1
	while cursor.x != to_cell.x:
		cursor.x += step
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if to_cell.y > cursor.y else -1
		path.append(cursor)
	return path


func _rect_road_access_cell(rect: Dictionary, blueprint: SettlementBlueprint, features: FeatureMapSet) -> Vector2i:
	var best_cell := Vector2i(-1, -1)
	var best_score := -INF
	for y in range(int(rect.get("y", 0)), int(rect.get("y", 0)) + int(rect.get("h", 0))):
		for x in range(int(rect.get("x", 0)), int(rect.get("x", 0)) + int(rect.get("w", 0))):
			var cell := Vector2i(x, y)
			if not _is_rect_edge_cell(rect, cell):
				continue
			if not _cell_touches_road(cell, blueprint):
				continue
			var score := features.score("public_score_map", cell) + features.score("edge_score_map", cell) * 0.2
			score -= float(features.distance_to_road(cell))
			if score > best_score:
				best_score = score
				best_cell = cell
	return best_cell


func _cell_touches_road(cell: Vector2i, blueprint: SettlementBlueprint) -> bool:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if blueprint.road_cell_keys.has(_cell_key(cell + direction)):
			return true
	return false


func _cell_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _rect_contains_cell(rect: Dictionary, cell: Vector2i) -> bool:
	return cell.x >= int(rect.get("x", 0)) \
		and cell.y >= int(rect.get("y", 0)) \
		and cell.x < int(rect.get("x", 0)) + int(rect.get("w", 0)) \
		and cell.y < int(rect.get("y", 0)) + int(rect.get("h", 0))


func _is_rect_edge_cell(rect: Dictionary, cell: Vector2i) -> bool:
	var x: int = int(rect.get("x", 0))
	var y: int = int(rect.get("y", 0))
	var w: int = int(rect.get("w", 0))
	var h: int = int(rect.get("h", 0))
	return cell.x == x or cell.y == y or cell.x == x + w - 1 or cell.y == y + h - 1


func _near_same_role_rect_penalty(rect: Dictionary, blueprint: SettlementBlueprint, role: String) -> float:
	var center := _rect_center(rect)
	var penalty := 0.0
	for plan_value in blueprint.building_plans:
		var plan: Dictionary = plan_value as Dictionary
		var request: Dictionary = plan.get("request", {}) as Dictionary
		if str(request.get("role", "")) != role:
			continue
		penalty += maxf(0.0, 12.0 - center.distance_to(_rect_center(plan.get("lot", {}) as Dictionary)))
	return penalty


func _request_pressure(request_id: String, blueprint: SettlementBlueprint) -> float:
	var assigned := blueprint.assigned_request_ids()
	if assigned.has(request_id):
		return 0.0
	match request_id:
		"residential":
			return 72.0
		"shop":
			return 76.0
		"workshop":
			return 46.0 if assigned.has("shop") or blueprint.generic_parcels.size() >= 2 else 18.0
		"tavern":
			return 44.0 if not blueprint.plaza.is_empty() else 0.0
		"farmer_cottage":
			return 42.0 if not blueprint.farm.is_empty() else 0.0
		"worker_cottage":
			return 34.0 if assigned.has("residential") else 0.0
		"storage_shed":
			return 40.0 if not blueprint.farm.is_empty() else 0.0
		"guardhouse":
			return 46.0 if not blueprint.wild_gate.is_empty() else 0.0
		_:
			return 0.0


func _farm_site_rects(blueprint: SettlementBlueprint) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	var seen: Dictionary = {}
	var max_x := blueprint.width - 1 - 8
	var max_y := blueprint.height - 1 - 7
	for y in range(2, max_y + 1):
		for x in range(2, max_x + 1):
			_append_unique_rect(rects, seen, _fit_rect({ "x": x, "y": y, "w": 8, "h": 7 }, blueprint.width, blueprint.height))
	return rects


func _training_site_rects(blueprint: SettlementBlueprint) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	var seen: Dictionary = {}
	var max_x := blueprint.width - 1 - 7
	var max_y := blueprint.height - 1 - 5
	for y in range(2, max_y + 1):
		for x in range(2, max_x + 1):
			_append_unique_rect(rects, seen, _fit_rect({ "x": x, "y": y, "w": 7, "h": 5 }, blueprint.width, blueprint.height))
	return rects


func _append_unique_rect(rects: Array[Dictionary], seen: Dictionary, rect: Dictionary) -> void:
	var key := "%d,%d,%d,%d" % [
		int(rect.get("x", 0)),
		int(rect.get("y", 0)),
		int(rect.get("w", 0)),
		int(rect.get("h", 0)),
	]
	if seen.has(key):
		return
	seen[key] = true
	rects.append(rect)


func _road_degree(cell: Vector2i, blueprint: SettlementBlueprint) -> int:
	var degree := 0
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if blueprint.road_cell_keys.has(_cell_key(cell + direction)):
			degree += 1
	return degree


func _plot_neighbor_penalty(lot: Dictionary, blueprint: SettlementBlueprint) -> float:
	var center := _rect_center(lot)
	var penalty := 0.0
	for parcel_value in blueprint.generic_parcels:
		var parcel: Dictionary = parcel_value as Dictionary
		var distance := center.distance_to(_rect_center(parcel))
		if distance < 5.5:
			penalty += (5.5 - distance) * 3.0
	return penalty


func _near_same_role_bonus(parcel: Dictionary, blueprint: SettlementBlueprint, role: String) -> float:
	var center := _rect_center(parcel)
	var bonus := 0.0
	for plan_value in blueprint.building_plans:
		var plan: Dictionary = plan_value as Dictionary
		var request: Dictionary = plan.get("request", {}) as Dictionary
		if str(request.get("role", "")) != role:
			continue
		var lot: Dictionary = plan.get("lot", {}) as Dictionary
		bonus += maxf(0.0, 16.0 - center.distance_to(_rect_center(lot)) * 1.8)
	return bonus


func _near_plaza_bonus(parcel: Dictionary, blueprint: SettlementBlueprint) -> float:
	if blueprint.plaza.is_empty():
		return 0.0
	return maxf(0.0, 28.0 - _rect_center(parcel).distance_to(_rect_center(blueprint.plaza)) * 1.8)


func _near_gate_bonus(parcel: Dictionary, blueprint: SettlementBlueprint) -> float:
	if blueprint.wild_gate.is_empty():
		return 0.0
	return maxf(0.0, 26.0 - _rect_center(parcel).distance_to(_rect_center(blueprint.wild_gate)) * 1.5)


func _bid_agent_for_request(request_id: String) -> String:
	match request_id:
		"residential", "farmer_cottage", "worker_cottage":
			return RESIDENTIAL_BID
		"shop":
			return SHOP_BID
		"workshop", "storage_shed":
			return WORKSHOP_BID
		"tavern":
			return TAVERN_BID
		"guardhouse":
			return GATE_CLAIM
		_:
			return ""


func _semantic_zone_for_request(request: Dictionary) -> String:
	match str(request.get("id", "")):
		"shop", "workshop":
			return "market"
		"tavern":
			return "tavern"
		"farmer_cottage":
			return "farm_service"
		"storage_shed":
			return "farm_storage"
		"guardhouse":
			return "gate_service"
		_:
			return "residential"


func _seed_cell(width: int, height: int) -> Vector2i:
	return Vector2i(
		clampi(int(float(width) * 0.48) + _rng.randi_range(-2, 2), 8, width - 8),
		clampi(int(float(height) * 0.58) + _rng.randi_range(-1, 1), 9, height - 6)
	)


func _rect_around(cell: Vector2i, w: int, h: int, width: int, height: int) -> Dictionary:
	return _clamped_rect({ "x": cell.x - int(w / 2), "y": cell.y - int(h / 2), "w": w, "h": h }, width, height)


func _clamped_rect(rect: Dictionary, width: int, height: int) -> Dictionary:
	var x := clampi(int(rect.get("x", 0)), 1, width - 2)
	var y := clampi(int(rect.get("y", 0)), 1, height - 2)
	var w: int = min(int(rect.get("w", 1)), width - 1 - x)
	var h: int = min(int(rect.get("h", 1)), height - 1 - y)
	return { "x": x, "y": y, "w": max(1, w), "h": max(1, h) }


func _fit_rect(rect: Dictionary, width: int, height: int) -> Dictionary:
	var w: int = clampi(int(rect.get("w", 1)), 1, width - 2)
	var h: int = clampi(int(rect.get("h", 1)), 1, height - 2)
	var x := clampi(int(rect.get("x", 0)), 1, width - 1 - w)
	var y := clampi(int(rect.get("y", 0)), 1, height - 1 - h)
	return { "x": x, "y": y, "w": w, "h": h }


func _rect_center(rect: Dictionary) -> Vector2:
	return Vector2(
		float(int(rect.get("x", 0))) + float(int(rect.get("w", 0))) * 0.5,
		float(int(rect.get("y", 0))) + float(int(rect.get("h", 0))) * 0.5
	)


func _rect_center_cell(rect: Dictionary) -> Vector2i:
	return Vector2i(
		int(rect.get("x", 0)) + int(int(rect.get("w", 0)) / 2),
		int(rect.get("y", 0)) + int(int(rect.get("h", 0)) / 2)
	)


func _rects_overlap(a: Dictionary, b: Dictionary, padding: int = 0) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var ax: int = int(a.get("x", 0))
	var ay: int = int(a.get("y", 0))
	var aw: int = int(a.get("w", 0))
	var ah: int = int(a.get("h", 0))
	var bx: int = int(b.get("x", 0))
	var by: int = int(b.get("y", 0))
	var bw: int = int(b.get("w", 0))
	var bh: int = int(b.get("h", 0))
	return ax - padding < bx + bw \
		and bx - padding < ax + aw \
		and ay - padding < by + bh \
		and by - padding < ay + ah


func _cell_from_dict(value: Dictionary) -> Vector2i:
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _dict_cell(cell: Vector2i) -> Dictionary:
	return { "x": cell.x, "y": cell.y }


func _dict_path(path: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in path:
		result.append(_dict_cell(cell))
	return result


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _jitter(amount: float) -> float:
	return _rng.randf_range(-amount, amount)
