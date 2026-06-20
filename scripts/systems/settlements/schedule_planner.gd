class_name SchedulePlanner
extends RefCounted


func build_schedule(npc_id: String, role: String, assignment: Dictionary) -> Array[Dictionary]:
	var home: Dictionary = _target_or_fallback(assignment.get("home_target", {}) as Dictionary, assignment)
	var work: Dictionary = _target_or_fallback(assignment.get("work_target", {}) as Dictionary, assignment)
	var social: Dictionary = _target_or_fallback(assignment.get("social_target", {}) as Dictionary, assignment)
	var rest: Dictionary = _target_or_fallback(assignment.get("rest_target", {}) as Dictionary, assignment)

	match role:
		"merchant", "shopkeeper", "innkeeper":
			return [
				_entry(npc_id, "morning_service", "08:00", "17:59", work, "work", "serving visitors"),
				_entry(npc_id, "evening_social", "18:00", "20:59", social, "social", "talking with locals"),
				_entry(npc_id, "night_home", "21:00", "07:59", rest, "sleep", "resting at home"),
			]
		"worker", "crafter", "blacksmith":
			return [
				_entry(npc_id, "day_work", "08:00", "16:59", work, "work", "working at the station"),
				_entry(npc_id, "evening_social", "17:00", "20:59", social, "social", "sharing news"),
				_entry(npc_id, "night_home", "21:00", "07:59", rest, "sleep", "resting at home"),
			]
		"guard", "trainer":
			return [
				_entry(npc_id, "day_watch", "06:00", "17:59", work, "patrol", "watching the settlement"),
				_entry(npc_id, "evening_watch", "18:00", "21:59", social, "patrol", "keeping watch"),
				_entry(npc_id, "night_rest", "22:00", "05:59", rest, "sleep", "resting between patrols"),
			]
		"traveler":
			return [
				_entry(npc_id, "day_public", "08:00", "17:59", social, "social", "visiting the settlement"),
				_entry(npc_id, "evening_rest", "18:00", "20:59", home, "rest", "settling in"),
				_entry(npc_id, "night_rest", "21:00", "07:59", rest, "sleep", "resting"),
			]
		_:
			return [
				_entry(npc_id, "morning_home", "06:00", "07:59", home, "idle", "starting the day"),
				_entry(npc_id, "day_activity", "08:00", "11:59", work, "work", "helping around the settlement"),
				_entry(npc_id, "midday_social", "12:00", "13:59", social, "social", "taking a break"),
				_entry(npc_id, "afternoon_activity", "14:00", "17:59", work, "work", "helping around the settlement"),
				_entry(npc_id, "evening_home", "18:00", "20:59", home, "idle", "returning home"),
				_entry(npc_id, "night_rest", "21:00", "05:59", rest, "sleep", "resting at home"),
			]


func _entry(npc_id: String, suffix: String, start: String, end: String, target: Dictionary, activity_type: String, activity: String) -> Dictionary:
	return {
		"id": "%s__%s" % [npc_id, suffix],
		"start": start,
		"end": end,
		"location_id": str(target.get("location_id", "")),
		"anchor_id": str(target.get("anchor_id", "")),
		"facing": str(target.get("facing", "down")),
		"activity_type": activity_type,
		"activity": activity,
		"movement": "walk",
	}


func _target_or_fallback(target: Dictionary, assignment: Dictionary) -> Dictionary:
	if _target_is_valid(target):
		return target
	for key in ["fallback_target", "social_target", "home_target", "work_target", "rest_target"]:
		var fallback: Dictionary = assignment.get(key, {}) as Dictionary
		if _target_is_valid(fallback):
			return fallback
	return {}


func _target_is_valid(target: Dictionary) -> bool:
	return not str(target.get("location_id", "")).is_empty() and not str(target.get("anchor_id", "")).is_empty()
