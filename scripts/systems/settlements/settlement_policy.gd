class_name SettlementPolicy
extends RefCounted

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
var asset_family_preferences: Array[String] = []
var seed_override: int = -1


static func from_dictionary(data: Dictionary) -> SettlementPolicy:
	var policy := SettlementPolicy.new()
	policy.settlement_type = str(data.get("settlement_type", policy.settlement_type))
	policy.scale = str(data.get("scale", policy.scale))
	policy.economy_tags = _string_array(data.get("economy_tags", []))
	policy.geography_bias = _string_array(data.get("geography_bias", []))
	policy.road_style = str(data.get("road_style", policy.road_style))
	policy.density = float(data.get("density", policy.density))
	policy.defense_level = int(data.get("defense_level", policy.defense_level))
	policy.wealth_level = int(data.get("wealth_level", policy.wealth_level))
	policy.required_landmarks = _string_array(data.get("required_landmarks", []))
	policy.banned_landmarks = _string_array(data.get("banned_landmarks", []))
	policy.district_rules = (data.get("district_rules", {}) as Dictionary).duplicate(true)
	policy.aesthetic_tags = _string_array(data.get("aesthetic_tags", []))
	policy.agent_weight_overrides = (data.get("agent_weight_overrides", {}) as Dictionary).duplicate(true)
	policy.evaluator_weight_overrides = (data.get("evaluator_weight_overrides", {}) as Dictionary).duplicate(true)
	policy.asset_family_preferences = _string_array(data.get("asset_family_preferences", []))
	policy.seed_override = int(data.get("seed_override", policy.seed_override))
	return policy


func to_dictionary() -> Dictionary:
	return {
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
		"asset_family_preferences": asset_family_preferences.duplicate(),
		"seed_override": seed_override,
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	for item in (value as Array):
		result.append(str(item))
	return result
