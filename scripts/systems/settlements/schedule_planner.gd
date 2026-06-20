class_name SchedulePlanner
extends RefCounted


func build_schedule(npc_id: String, role: String, assignment: Dictionary) -> Array[Dictionary]:
	var home: Dictionary = _target_or_fallback(assignment.get("home_target", {}) as Dictionary, assignment)
	var work: Dictionary = _target_or_fallback(assignment.get("work_target", {}) as Dictionary, assignment)
	var social: Dictionary = _target_or_fallback(assignment.get("social_target", {}) as Dictionary, assignment)
	var rest: Dictionary = _target_or_fallback(assignment.get("rest_target", {}) as Dictionary, assignment)

	match role:
		"merchant", "shopkeeper", "innkeeper":
			return _with_transition_metadata([
				_entry(npc_id, "morning_service", "08:00", "17:59", work, "work", "serving visitors"),
				_entry(npc_id, "evening_social", "18:00", "20:59", social, "social", "talking with locals"),
				_entry(npc_id, "night_home", "21:00", "07:59", rest, "sleep", "resting at home"),
			], assignment)
		"worker", "crafter", "blacksmith":
			return _with_transition_metadata([
				_entry(npc_id, "day_work", "08:00", "16:59", work, "work", "working at the station"),
				_entry(npc_id, "evening_social", "17:00", "20:59", social, "social", "sharing news"),
				_entry(npc_id, "night_home", "21:00", "07:59", rest, "sleep", "resting at home"),
			], assignment)
		"guard", "trainer":
			return _with_transition_metadata([
				_entry(npc_id, "day_watch", "06:00", "17:59", work, "patrol", "watching the settlement"),
				_entry(npc_id, "evening_watch", "18:00", "21:59", social, "patrol", "keeping watch"),
				_entry(npc_id, "night_rest", "22:00", "05:59", rest, "sleep", "resting between patrols"),
			], assignment)
		"traveler":
			return _with_transition_metadata([
				_entry(npc_id, "day_public", "08:00", "17:59", social, "social", "visiting the settlement"),
				_entry(npc_id, "evening_rest", "18:00", "20:59", home, "rest", "settling in"),
				_entry(npc_id, "night_rest", "21:00", "07:59", rest, "sleep", "resting"),
			], assignment)
		_:
			return _with_transition_metadata([
				_entry(npc_id, "morning_home", "06:00", "07:59", home, "idle", "starting the day"),
				_entry(npc_id, "day_activity", "08:00", "11:59", work, "work", "helping around the settlement"),
				_entry(npc_id, "midday_social", "12:00", "13:59", social, "social", "taking a break"),
				_entry(npc_id, "afternoon_activity", "14:00", "17:59", work, "work", "helping around the settlement"),
				_entry(npc_id, "evening_home", "18:00", "20:59", home, "idle", "returning home"),
				_entry(npc_id, "night_rest", "21:00", "05:59", rest, "sleep", "resting at home"),
			], assignment)


func _entry(npc_id: String, suffix: String, start: String, end: String, target: Dictionary, activity_type: String, activity: String) -> Dictionary:
	var entry := {
		"id": "%s__%s" % [npc_id, suffix],
		"start": start,
		"end": end,
		"location_id": str(target.get("location_id", "")),
		"anchor_id": str(target.get("anchor_id", "")),
		"facing": str(target.get("facing", "down")),
		"activity_type": activity_type,
		"activity": activity,
		"movement": "walk",
		"target_location_id": str(target.get("location_id", "")),
		"target_anchor_id": str(target.get("anchor_id", "")),
	}
	if target.has("grid_position"):
		entry["grid_position"] = (target.get("grid_position", {}) as Dictionary).duplicate(true)
	if target.has("activity_cells"):
		entry["activity_cells"] = (target.get("activity_cells", []) as Array).duplicate(true)
	if target.has("target_key"):
		entry["target_key"] = str(target.get("target_key", ""))
	if target.has("capacity"):
		entry["target_capacity"] = int(target.get("capacity", 1))
	if target.has("slot_index"):
		entry["target_slot_index"] = int(target.get("slot_index", 0))
	if target.has("uses_capacity_slot"):
		entry["uses_capacity_slot"] = bool(target.get("uses_capacity_slot", false))
	for key in [
		"source_building_id",
		"target_type",
		"interior_location_id",
		"exterior_location_id",
		"exterior_anchor_id",
		"arrival_anchor_id",
		"departure_anchor_id",
	]:
		if target.has(key):
			entry[key] = target[key]
	return entry


func _with_transition_metadata(entries: Array[Dictionary], _assignment: Dictionary) -> Array[Dictionary]:
	if entries.is_empty():
		return entries
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var previous: Dictionary = entries[(index - 1 + entries.size()) % entries.size()]
		entry["source_location_id"] = str(previous.get("location_id", ""))
		entry["source_anchor_id"] = str(previous.get("anchor_id", ""))
		entry["target_location_id"] = str(entry.get("location_id", ""))
		entry["target_anchor_id"] = str(entry.get("anchor_id", ""))
		if str(previous.get("location_id", "")) == str(entry.get("location_id", "")):
			entry["transition_kind"] = "same_location"
			entry["departure_location_id"] = str(entry.get("location_id", ""))
			entry["departure_anchor_id"] = str(previous.get("anchor_id", ""))
			entry["arrival_location_id"] = str(entry.get("location_id", ""))
			entry["arrival_anchor_id"] = str(entry.get("anchor_id", ""))
			entry["transition_anchor_by_location"] = {
				str(entry.get("location_id", "")): str(entry.get("anchor_id", "")),
			}
		else:
			var departure_anchor := _departure_anchor_for_entry(previous)
			var arrival_anchor := _arrival_anchor_for_entry(entry)
			entry["transition_kind"] = "cross_location"
			entry["departure_location_id"] = str(previous.get("location_id", ""))
			entry["departure_anchor_id"] = departure_anchor
			entry["arrival_location_id"] = str(entry.get("location_id", ""))
			entry["arrival_anchor_id"] = arrival_anchor
			var anchors_by_location := {
				str(previous.get("location_id", "")): departure_anchor,
				str(entry.get("location_id", "")): arrival_anchor,
			}
			var exterior_location_id := str(entry.get("exterior_location_id", ""))
			var exterior_anchor_id := str(entry.get("exterior_anchor_id", ""))
			if not exterior_location_id.is_empty() and not exterior_anchor_id.is_empty():
				anchors_by_location[exterior_location_id] = exterior_anchor_id
			entry["transition_anchor_by_location"] = anchors_by_location
		entries[index] = entry
	return entries


func _arrival_anchor_for_entry(entry: Dictionary) -> String:
	var location_id := str(entry.get("location_id", ""))
	if location_id == str(entry.get("interior_location_id", "")):
		return str(entry.get("arrival_anchor_id", "entry"))
	return str(entry.get("arrival_anchor_id", entry.get("anchor_id", "")))


func _departure_anchor_for_entry(entry: Dictionary) -> String:
	var location_id := str(entry.get("location_id", ""))
	if location_id == str(entry.get("interior_location_id", "")):
		return str(entry.get("departure_anchor_id", "exit"))
	return str(entry.get("departure_anchor_id", entry.get("anchor_id", "")))


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
