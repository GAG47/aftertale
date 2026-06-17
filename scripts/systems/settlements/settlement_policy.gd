class_name SettlementPolicy
extends RefCounted

const PROFILE_DIR := "res://data/settlement_policies"

var policy_id: String = ""
var settlement_type: String = "test_settlement"
var scale: String = "village"
var economy_tags: Array[String] = []
var geography_bias: Array[String] = []
var road_style: String = "organic"
var density: float = 0.45
var defense_level: int = 0
var wealth_level: int = 1
var required_landmarks: Array[String] = []
var banned_landmarks: Array[String] = []
var district_rules: Dictionary = {}
var aesthetic_tags: Array[String] = []
var agent_weight_overrides: Dictionary = {}
var evaluator_weight_overrides: Dictionary = {}
var demand_weight_overrides: Dictionary = {}
var plot_use_weight_overrides: Dictionary = {}
var asset_family_preferences: Array[String] = []
var gameplay_hook_rules: Dictionary = {}
var random_seed: int = -1
var seed_override: int = -1


static func from_dictionary(data: Dictionary) -> SettlementPolicy:
	var policy := SettlementPolicy.new()
	policy.apply_dictionary(data)
	return policy


static func from_profile_id(profile_id: String) -> SettlementPolicy:
	var policy := SettlementPolicy.new()
	if profile_id.strip_edges().is_empty():
		return policy
	var path := "%s/%s.json" % [PROFILE_DIR, profile_id]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SettlementPolicy could not open policy profile: %s" % path)
		policy.policy_id = profile_id
		return policy
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SettlementPolicy expected policy profile to be a JSON object: %s" % path)
		policy.policy_id = profile_id
		return policy
	policy.apply_dictionary(parsed as Dictionary)
	if policy.policy_id.is_empty():
		policy.policy_id = profile_id
	return policy


static func from_generator_data(generator_data: Dictionary) -> SettlementPolicy:
	var profile_id := str(generator_data.get("settlement_policy_id", generator_data.get("policy_id", "")))
	var policy := from_profile_id(profile_id) if not profile_id.is_empty() else SettlementPolicy.new()
	if generator_data.has("policy"):
		policy.apply_dictionary(generator_data.get("policy", {}) as Dictionary)
	if not profile_id.is_empty():
		policy.policy_id = profile_id
	if generator_data.has("seed"):
		policy.seed_override = int(generator_data.get("seed", policy.seed_override))
	if policy.seed_override < 0 and policy.random_seed >= 0:
		policy.seed_override = policy.random_seed
	return policy


func apply_dictionary(data: Dictionary) -> void:
	policy_id = str(data.get("policy_id", data.get("id", policy_id)))
	settlement_type = str(data.get("settlement_type", settlement_type))
	scale = str(data.get("scale", scale))
	economy_tags = _string_array(data.get("economy_tags", economy_tags))
	geography_bias = _string_array(data.get("geography_bias", geography_bias))
	road_style = str(data.get("road_style", road_style))
	density = float(data.get("density", density))
	defense_level = int(data.get("defense_level", defense_level))
	wealth_level = int(data.get("wealth_level", wealth_level))
	required_landmarks = _string_array(data.get("required_landmarks", required_landmarks))
	banned_landmarks = _string_array(data.get("banned_landmarks", banned_landmarks))
	district_rules = _merged_dictionary(district_rules, data.get("district_rules", {}) as Dictionary)
	aesthetic_tags = _string_array(data.get("aesthetic_tags", aesthetic_tags))
	agent_weight_overrides = _merged_dictionary(agent_weight_overrides, data.get("agent_weight_overrides", {}) as Dictionary)
	evaluator_weight_overrides = _merged_dictionary(evaluator_weight_overrides, data.get("evaluator_weight_overrides", {}) as Dictionary)
	demand_weight_overrides = _merged_dictionary(demand_weight_overrides, data.get("demand_weight_overrides", {}) as Dictionary)
	plot_use_weight_overrides = _merged_dictionary(plot_use_weight_overrides, data.get("plot_use_weight_overrides", {}) as Dictionary)
	asset_family_preferences = _string_array(data.get("asset_family_preferences", asset_family_preferences))
	gameplay_hook_rules = _merged_dictionary(gameplay_hook_rules, data.get("gameplay_hook_rules", {}) as Dictionary)
	random_seed = int(data.get("random_seed", random_seed))
	seed_override = int(data.get("seed_override", seed_override))


func to_dictionary() -> Dictionary:
	return {
		"policy_id": policy_id,
		"settlement_type": settlement_type,
		"scale": scale,
		"economy_tags": economy_tags.duplicate(),
		"geography_bias": geography_bias.duplicate(),
		"road_style": road_style,
		"density": density,
		"defense_level": defense_level,
		"wealth_level": wealth_level,
		"required_landmarks": required_landmarks.duplicate(),
		"banned_landmarks": banned_landmarks.duplicate(),
		"district_rules": district_rules.duplicate(true),
		"aesthetic_tags": aesthetic_tags.duplicate(),
		"agent_weight_overrides": agent_weight_overrides.duplicate(true),
		"evaluator_weight_overrides": evaluator_weight_overrides.duplicate(true),
		"demand_weight_overrides": demand_weight_overrides.duplicate(true),
		"plot_use_weight_overrides": plot_use_weight_overrides.duplicate(true),
		"asset_family_preferences": asset_family_preferences.duplicate(),
		"gameplay_hook_rules": gameplay_hook_rules.duplicate(true),
		"random_seed": random_seed,
		"seed_override": seed_override,
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in (value as Array):
		result.append(str(item))
	return result


static func _merged_dictionary(base: Dictionary, override: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in override.keys():
		result[key] = override[key]
	return result
