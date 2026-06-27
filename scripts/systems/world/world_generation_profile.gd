class_name WorldGenerationProfile
extends RefCounted

const DEFAULT_PROFILE_ID := "temperate_frontier"
const PROFILE_PATH_PATTERN := "res://data/world_generation_profiles/%s.json"


static func load_profile(profile_id_or_path: String) -> Dictionary:
	var profile_id := profile_id_or_path
	if profile_id.is_empty():
		profile_id = DEFAULT_PROFILE_ID
	var resource_path := profile_id
	if not resource_path.begins_with("res://"):
		resource_path = PROFILE_PATH_PATTERN % profile_id

	var data := _load_json_resource(resource_path)
	var profile := _default_profile()
	if not data.is_empty():
		_deep_merge(profile, data)
	if not profile.has("profile_id"):
		profile["profile_id"] = profile_id
	return profile


static func resolve_generation_config(input: Dictionary) -> Dictionary:
	var profile_id := str(input.get("region_profile_id", input.get("profile_id", DEFAULT_PROFILE_ID)))
	var profile_path := str(input.get("region_profile_path", ""))
	var profile := load_profile(profile_path if not profile_path.is_empty() else profile_id)
	var resolved := profile.duplicate(true)
	_deep_merge(resolved, input)
	resolved["region_profile_id"] = str(resolved.get("region_profile_id", resolved.get("profile_id", profile_id)))
	return resolved


static func _default_profile() -> Dictionary:
	return {
		"profile_id": DEFAULT_PROFILE_ID,
		"node_count_range": [4, 6],
		"start_location_policy": "static_test_village",
		"available_location_kinds": ["generated_wild"],
		"available_wild_profiles": ["plain", "forest_edge", "riverbank", "foothill"],
		"location_kind_weights": {
			"generated_wild": 1.0,
		},
		"wild_profile_weights": {
			"plain": 0.35,
			"forest_edge": 0.30,
			"riverbank": 0.20,
			"foothill": 0.15,
		},
		"connection_density": 1.20,
		"branchiness": 0.45,
		"size_ranges": {
			"generated_wild": [
				[48, 48],
				[56, 48],
				[64, 48],
			],
		},
	}


static func _deep_merge(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		var source_value: Variant = source[key]
		if source_value is Dictionary and target.get(key, null) is Dictionary:
			var target_child: Dictionary = target[key] as Dictionary
			_deep_merge(target_child, source_value as Dictionary)
			target[key] = target_child
		else:
			target[key] = source_value


static func _load_json_resource(resource_path: String) -> Dictionary:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)
	return {}
