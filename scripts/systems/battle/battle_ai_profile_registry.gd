class_name BattleAiProfileRegistry
extends RefCounted

const PROFILE_PATH := "res://data/battle/ai_profiles.json"
const DEFAULT_WEIGHTS := {
	"damage": 1.0,
	"kill": 1.0,
	"control": 1.0,
	"survival": 1.0,
	"tile": 1.0,
	"position": 1.0,
	"target": 1.0,
	"risk": 1.0,
	"resource": 1.0,
	"support": 1.0,
	"reaction": 1.0,
}

static var _profile_data: Dictionary = {}


static func get_profile(profile_id: String) -> Dictionary:
	_ensure_loaded()
	var profiles: Dictionary = _profile_data.get("profiles", {}) as Dictionary
	var default_id: String = str(_profile_data.get("default_profile", "balanced"))
	var resolved_id: String = profile_id if profiles.has(profile_id) else default_id
	var profile: Dictionary = (profiles.get(resolved_id, {}) as Dictionary).duplicate(true)
	var weights: Dictionary = DEFAULT_WEIGHTS.duplicate(true)
	weights.merge(profile.get("weights", {}) as Dictionary, true)
	profile["id"] = resolved_id
	profile["preferred_range"] = max(1, int(profile.get("preferred_range", 1)))
	profile["weights"] = weights
	return profile


static func _ensure_loaded() -> void:
	if not _profile_data.is_empty():
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_profile_data = parsed as Dictionary
	if _profile_data.is_empty():
		push_error("BattleAiProfileRegistry could not load %s" % PROFILE_PATH)
		_profile_data = {
			"default_profile": "balanced",
			"profiles": {
				"balanced": {
					"preferred_range": 1,
					"weights": DEFAULT_WEIGHTS.duplicate(true),
				},
			},
		}
