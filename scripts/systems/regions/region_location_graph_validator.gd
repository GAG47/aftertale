class_name RegionLocationGraphValidator
extends RefCounted

const ALLOWED_TRAVEL_TYPES := ["path", "road", "hidden_path"]
const ALLOWED_ACCESS_RULES := ["always", "quest_locked", "item_required"]
const FORBIDDEN_SCENE_KEYS := {
	"scene_path": true,
	"spawn_id": true,
	"tilemap": true,
	"target_scene_path": true,
}


func validate(graph: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if graph.is_empty():
		errors.append("LocationGraphSnapshot is empty")
		return errors
	_scan_for_forbidden_keys(graph, "", errors)
	if int(graph.get("schema_version", 0)) != 1:
		errors.append("LocationGraphSnapshot.schema_version is unsupported: %s" % str(graph.get("schema_version", "")))
	if str(graph.get("stage", "")) != "location_graph":
		errors.append("LocationGraphSnapshot.stage must be location_graph")
	for key in ["region_id", "region_type", "region_slug", "seed", "source_hash", "start_location_id"]:
		if str(graph.get(key, "")).is_empty():
			errors.append("LocationGraphSnapshot.%s is missing" % key)
	if not (graph.get("selected_roles", null) is Array):
		errors.append("LocationGraphSnapshot.selected_roles must be an array")
	if not (graph.get("locations", null) is Array):
		errors.append("LocationGraphSnapshot.locations must be an array")
	if not (graph.get("edges", null) is Array):
		errors.append("LocationGraphSnapshot.edges must be an array")
	if not errors.is_empty():
		return errors
	var roles_by_id := _roles_by_id(graph.get("selected_roles", []) as Array, errors)
	var locations_by_id := _locations_by_id(graph.get("locations", []) as Array, roles_by_id, errors)
	_validate_edges(graph.get("edges", []) as Array, locations_by_id, roles_by_id, errors)
	var start_location_id := str(graph.get("start_location_id", ""))
	if not locations_by_id.has(start_location_id):
		errors.append("LocationGraphSnapshot.start_location_id references unknown location: %s" % start_location_id)
	if errors.is_empty() and not _is_connected(start_location_id, locations_by_id, graph.get("edges", []) as Array):
		errors.append("LocationGraphSnapshot locations are not all reachable from start_location_id")
	_validate_external_intents_land(graph, locations_by_id, errors)
	return errors


func _roles_by_id(roles: Array, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	var role_slugs: Dictionary = {}
	for role_value in roles:
		var role: Dictionary = role_value as Dictionary
		var role_id := str(role.get("role_id", ""))
		var role_slug := str(role.get("role_slug", ""))
		if role_id.is_empty():
			errors.append("LocationGraphSnapshot selected role missing role_id")
			continue
		if result.has(role_id):
			errors.append("LocationGraphSnapshot duplicate role_id: %s" % role_id)
		if role_slugs.has(role_slug):
			errors.append("LocationGraphSnapshot duplicate role_slug: %s" % role_slug)
		result[role_id] = role
		role_slugs[role_slug] = true
	return result


func _locations_by_id(locations: Array, roles_by_id: Dictionary, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		var location_id := str(location.get("location_id", ""))
		var role_id := str(location.get("role_id", ""))
		if location_id.is_empty():
			errors.append("LocationGraphSnapshot location missing location_id")
			continue
		if result.has(location_id):
			errors.append("LocationGraphSnapshot duplicate location_id: %s" % location_id)
		if str(location.get("location_type", "")).is_empty():
			errors.append("LocationGraphSnapshot location missing location_type: %s" % location_id)
		if not roles_by_id.has(role_id):
			errors.append("LocationGraphSnapshot location references unknown role_id: %s" % role_id)
		result[location_id] = location
	return result


func _validate_edges(edges: Array, locations_by_id: Dictionary, roles_by_id: Dictionary, errors: Array[String]) -> void:
	var edge_ids: Dictionary = {}
	var pair_keys: Dictionary = {}
	for edge_value in edges:
		var edge: Dictionary = edge_value as Dictionary
		var edge_id := str(edge.get("edge_id", ""))
		var from_location_id := str(edge.get("from_location_id", ""))
		var to_location_id := str(edge.get("to_location_id", ""))
		if edge_id.is_empty():
			errors.append("LocationGraphSnapshot edge missing edge_id")
			continue
		if edge_ids.has(edge_id):
			errors.append("LocationGraphSnapshot duplicate edge_id: %s" % edge_id)
		edge_ids[edge_id] = true
		if not locations_by_id.has(from_location_id):
			errors.append("LocationGraphSnapshot edge references unknown from_location_id: %s" % edge_id)
		if not locations_by_id.has(to_location_id):
			errors.append("LocationGraphSnapshot edge references unknown to_location_id: %s" % edge_id)
		if not roles_by_id.has(str(edge.get("from_role_id", ""))):
			errors.append("LocationGraphSnapshot edge references unknown from_role_id: %s" % edge_id)
		if not roles_by_id.has(str(edge.get("to_role_id", ""))):
			errors.append("LocationGraphSnapshot edge references unknown to_role_id: %s" % edge_id)
		if not ALLOWED_TRAVEL_TYPES.has(str(edge.get("travel_type", ""))):
			errors.append("LocationGraphSnapshot edge has illegal travel_type: %s" % edge_id)
		if not ALLOWED_ACCESS_RULES.has(str(edge.get("access_rule", ""))):
			errors.append("LocationGraphSnapshot edge has illegal access_rule: %s" % edge_id)
		for key in ["direction_hint", "exit_style", "edge_source"]:
			if str(edge.get(key, "")).is_empty():
				errors.append("LocationGraphSnapshot edge missing %s: %s" % [key, edge_id])
		var pair_key := "%s::%s" % [from_location_id, to_location_id]
		if pair_keys.has(pair_key):
			errors.append("LocationGraphSnapshot duplicate location edge pair: %s" % pair_key)
		pair_keys[pair_key] = true


func _validate_external_intents_land(graph: Dictionary, locations_by_id: Dictionary, errors: Array[String]) -> void:
	for intent_value in (graph.get("external_connection_intents", []) as Array):
		var intent: Dictionary = intent_value as Dictionary
		var intent_id := str(intent.get("intent_id", ""))
		var found := false
		for location_id in locations_by_id.keys():
			var location: Dictionary = locations_by_id.get(location_id, {}) as Dictionary
			if str(location.get("source_intent_id", "")) == intent_id:
				found = true
				break
		if not found:
			errors.append("LocationGraphSnapshot external_connection_intent has no boundary location: %s" % intent_id)


func _is_connected(start_location_id: String, locations_by_id: Dictionary, edges: Array) -> bool:
	var open: Array[String] = [start_location_id]
	var seen: Dictionary = {}
	var adjacency: Dictionary = {}
	for location_id in locations_by_id.keys():
		adjacency[str(location_id)] = []
	for edge_value in edges:
		var edge: Dictionary = edge_value as Dictionary
		var from_location_id := str(edge.get("from_location_id", ""))
		var to_location_id := str(edge.get("to_location_id", ""))
		if not adjacency.has(from_location_id) or not adjacency.has(to_location_id):
			continue
		(adjacency[from_location_id] as Array).append(to_location_id)
		if bool(edge.get("bidirectional", true)):
			(adjacency[to_location_id] as Array).append(from_location_id)
	while not open.is_empty():
		var current := str(open.pop_front())
		if seen.has(current):
			continue
		seen[current] = true
		for next_value in (adjacency.get(current, []) as Array):
			var next_id := str(next_value)
			if not seen.has(next_id):
				open.append(next_id)
	return seen.size() == locations_by_id.size()


func _scan_for_forbidden_keys(value: Variant, path: String, errors: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key_value in dictionary.keys():
			var key := str(key_value)
			var next_path := key if path.is_empty() else "%s.%s" % [path, key]
			if bool(FORBIDDEN_SCENE_KEYS.get(key, false)):
				errors.append("LocationGraphSnapshot must not contain Scene field in v67: %s" % next_path)
			_scan_for_forbidden_keys(dictionary.get(key_value), next_path, errors)
	elif value is Array:
		var values: Array = value as Array
		for index in range(values.size()):
			_scan_for_forbidden_keys(values[index], "%s[%d]" % [path, index], errors)
