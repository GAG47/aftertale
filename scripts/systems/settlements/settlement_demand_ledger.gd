class_name SettlementDemandLedger
extends RefCounted

var housing_need: int = 4
var commerce_need: int = 2
var production_need: int = 2
var public_need: int = 1
var road_need: int = 1
var desired_counts: Dictionary = {
	"residential": 4,
	"commercial": 2,
	"production": 2,
	"public": 1,
}
var demand_weights: Dictionary = {}


func configure(policy: SettlementPolicy, context: SettlementContext = null) -> void:
	demand_weights = policy.demand_weight_overrides.duplicate(true)
	var density_factor: float = clampf(policy.density / 0.45, 0.65, 1.65)
	var area_factor: float = 1.0
	if context != null:
		var usable_area: float = maxf(1.0, float(context.map_size.x * context.map_size.y - context.existing_obstacles.size() - context.existing_water.size()))
		area_factor = maxf(1.0, sqrt(usable_area / 280.0))
	var scale_factor: float = _scale_factor(policy.scale)
	desired_counts = {
		"residential": _desired_count("residential", 4, density_factor, area_factor, scale_factor),
		"commercial": _desired_count("commercial", 2, density_factor, area_factor, scale_factor),
		"production": _desired_count("production", 2, density_factor, area_factor, scale_factor),
		"public": _desired_count("public", 1, density_factor, area_factor, scale_factor),
	}
	if policy.required_landmarks.size() > 0:
		desired_counts["public"] = max(1, int(desired_counts.get("public", 1)))


func reset(policy: SettlementPolicy = null, context: SettlementContext = null) -> void:
	if policy != null:
		configure(policy, context)
	housing_need = int(desired_counts.get("residential", 4))
	commerce_need = int(desired_counts.get("commercial", 2))
	production_need = int(desired_counts.get("production", 2))
	public_need = int(desired_counts.get("public", 1))
	road_need = 1


func update_from_session(session, feedback: Dictionary = {}) -> void:
	var counts := _plot_use_counts(session)
	housing_need = max(0, int(desired_counts.get("residential", 4)) - int(counts.get("residential", 0)))
	commerce_need = max(0, int(desired_counts.get("commercial", 2)) - int(counts.get("commercial", 0)))
	production_need = max(0, int(desired_counts.get("production", 2)) - int(counts.get("production", 0)))
	public_need = max(0, int(desired_counts.get("public", 1)) - int(counts.get("public", 0)))
	var isolated_count := (feedback.get("isolated_plots", []) as Array).size()
	road_need = isolated_count
	if bool(feedback.get("need_more_roads", false)):
		road_need += 1
	if bool(feedback.get("entrance_disconnected", false)):
		road_need += 2


func need_for_use(use: String) -> int:
	match use:
		"residential":
			return housing_need
		"commercial":
			return commerce_need
		"production":
			return production_need
		"public":
			return public_need
		_:
			return 0


func to_dictionary() -> Dictionary:
	return {
		"housing_need": housing_need,
		"commerce_need": commerce_need,
		"production_need": production_need,
		"public_need": public_need,
		"road_need": road_need,
		"desired_counts": desired_counts.duplicate(true),
		"demand_weights": demand_weights.duplicate(true),
	}


func _desired_count(use: String, base_count: int, density_factor: float, area_factor: float, scale_factor: float) -> int:
	var weight := float(demand_weights.get(use, 1.0))
	var count := int(round(float(base_count) * density_factor * area_factor * scale_factor * weight))
	if use == "public":
		return max(0, count)
	return max(1, count)


func _scale_factor(scale: String) -> float:
	match scale:
		"camp":
			return 0.78
		"town":
			return 1.45
		"city":
			return 2.20
		_:
			return 1.0


func _plot_use_counts(session) -> Dictionary:
	var result := {
		"residential": 0,
		"commercial": 0,
		"production": 0,
		"public": 0,
	}
	for plot_value in session.blueprint.plots:
		var plot: Dictionary = plot_value as Dictionary
		var use := str(plot.get("use", ""))
		if result.has(use):
			result[use] = int(result.get(use, 0)) + 1
	return result
