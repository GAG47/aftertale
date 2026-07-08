class_name EdgeContractGenerator
extends RefCounted

const COMPILER_VERSION := "v67.4"


func generate_edges_result(location_node_result: Dictionary, profile: RefCounted) -> Dictionary:
	var errors := _validate_location_result_shape(location_node_result)
	if profile == null:
		errors.append("RegionTypeProfile is required for edge generation")
	if not errors.is_empty():
		return _failure("validate_location_node_result", errors, {})

	var locations: Array = location_node_result.get("locations", []) as Array
	var locations_by_role_type := _locations_by_role_type(locations)
	var edges: Array[Dictionary] = []
	for rule in profile.connection_rules():
		var rule_result := _apply_connection_rule(rule, locations_by_role_type, edges)
		if not bool(rule_result.get("success", false)):
			return _failure("generate_rule_edges", rule_result.get("errors", []) as Array[String], {
				"location_node_result": location_node_result,
			})
	var external_result := _generate_external_edges(location_node_result, profile, locations_by_role_type, edges)
	if not bool(external_result.get("success", false)):
		return _failure("generate_external_edges", external_result.get("errors", []) as Array[String], {
			"location_node_result": location_node_result,
		})
	_assign_edge_ids(edges, location_node_result)
	var graph_result := location_node_result.duplicate(true)
	graph_result["schema_version"] = 1
	graph_result["compiler_version"] = COMPILER_VERSION
	graph_result["stage"] = "location_graph"
	graph_result["start_location_id"] = _start_location_id(locations, profile)
	graph_result["edges"] = edges
	graph_result["debug_summary"] = _debug_summary(locations, edges)
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"location_graph": graph_result,
	}


func _apply_connection_rule(rule: Dictionary, locations_by_role_type: Dictionary, edges: Array[Dictionary]) -> Dictionary:
	var from_role_type := str(rule.get("from_role_type", ""))
	var to_role_type := str(rule.get("to_role_type", ""))
	var from_locations: Array = locations_by_role_type.get(from_role_type, []) as Array
	var to_locations: Array = locations_by_role_type.get(to_role_type, []) as Array
	if from_locations.is_empty() or to_locations.is_empty():
		if bool(rule.get("required", false)):
			return _failure("generate_rule_edges", [
				"required connection rule cannot resolve roles: %s -> %s" % [from_role_type, to_role_type],
			], {})
		return { "success": true, "errors": [] }
	for from_location_value in from_locations:
		var from_location: Dictionary = from_location_value as Dictionary
		for to_location_value in to_locations:
			var to_location: Dictionary = to_location_value as Dictionary
			edges.append(_edge_contract(from_location, to_location, rule, "rule", ""))
	return { "success": true, "errors": [] }


func _generate_external_edges(location_node_result: Dictionary, profile: RefCounted, locations_by_role_type: Dictionary, edges: Array[Dictionary]) -> Dictionary:
	var anchor_role_type: String = profile.external_connection_anchor_role_type()
	var anchor_locations: Array = locations_by_role_type.get(anchor_role_type, []) as Array
	var external_locations: Array = locations_by_role_type.get(profile.external_intent_role_type(), []) as Array
	if external_locations.is_empty():
		return { "success": true, "errors": [] }
	if anchor_locations.is_empty():
		return _failure("generate_external_edges", [
			"external connection intents cannot resolve anchor role_type: %s" % anchor_role_type,
		], {})
	var intents_by_id: Dictionary = {}
	for intent_value in (location_node_result.get("external_connection_intents", []) as Array):
		var intent: Dictionary = intent_value as Dictionary
		intents_by_id[str(intent.get("intent_id", ""))] = intent
	var anchor: Dictionary = anchor_locations[0] as Dictionary
	for external_value in external_locations:
		var external: Dictionary = external_value as Dictionary
		var intent_id := str(external.get("source_intent_id", ""))
		if intent_id.is_empty() or not intents_by_id.has(intent_id):
			return _failure("generate_external_edges", [
				"external boundary location has no matching external_connection_intent: %s" % str(external.get("location_id", "")),
			], {})
		var intent: Dictionary = intents_by_id.get(intent_id, {}) as Dictionary
		var rule := {
			"travel_type": str(intent.get("travel_type", "")),
			"direction_hint": str(intent.get("direction_hint", "")),
			"access_rule": str(intent.get("access_rule", "always")),
			"exit_style": str(intent.get("exit_style", "")),
		}
		edges.append(_edge_contract(anchor, external, rule, "external", intent_id))
	return { "success": true, "errors": [] }


func _edge_contract(from_location: Dictionary, to_location: Dictionary, rule: Dictionary, edge_source: String, source_intent_id: String) -> Dictionary:
	return {
		"edge_id": "",
		"from_location_id": str(from_location.get("location_id", "")),
		"to_location_id": str(to_location.get("location_id", "")),
		"from_role_id": str(from_location.get("role_id", "")),
		"to_role_id": str(to_location.get("role_id", "")),
		"travel_type": str(rule.get("travel_type", "")),
		"direction_hint": str(rule.get("direction_hint", "")),
		"access_rule": str(rule.get("access_rule", "always")),
		"exit_style": str(rule.get("exit_style", "")),
		"bidirectional": true,
		"edge_source": edge_source,
		"source_intent_id": source_intent_id,
	}


func _assign_edge_ids(edges: Array[Dictionary], graph: Dictionary) -> void:
	var region_id := str(graph.get("region_id", ""))
	var segments := region_id.split(".")
	for index in range(edges.size()):
		var edge: Dictionary = edges[index] as Dictionary
		var from_slug := _location_slug(str(edge.get("from_location_id", "")))
		var to_slug := _location_slug(str(edge.get("to_location_id", "")))
		edge["edge_id"] = "edge.%s.%s.%s.%s__%s.eg_%04d" % [
			str(segments[1]),
			str(graph.get("region_type", "")),
			str(graph.get("region_slug", "")),
			from_slug,
			to_slug,
			index + 1,
		]
		edges[index] = edge


func _start_location_id(locations: Array, profile: RefCounted) -> String:
	var anchor_role_type: String = profile.external_connection_anchor_role_type()
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("role_type", "")) == anchor_role_type:
			return str(location.get("location_id", ""))
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		if str(location.get("role_source", "")) == "required":
			return str(location.get("location_id", ""))
	return ""


func _locations_by_role_type(locations: Array) -> Dictionary:
	var result: Dictionary = {}
	for location_value in locations:
		var location: Dictionary = location_value as Dictionary
		var role_type := str(location.get("role_type", ""))
		var rows: Array = result.get(role_type, []) as Array
		rows.append(location)
		result[role_type] = rows
	return result


func _validate_location_result_shape(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("LocationNodeResult is empty")
	if str(result.get("stage", "")) != "location_nodes":
		errors.append("LocationNodeResult.stage must be location_nodes")
	if not (result.get("locations", null) is Array):
		errors.append("LocationNodeResult.locations must be an array")
	return errors


func _debug_summary(locations: Array, edges: Array[Dictionary]) -> Dictionary:
	return {
		"location_count": locations.size(),
		"edge_count": edges.size(),
	}


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result


static func _location_slug(location_id: String) -> String:
	var segments := location_id.split(".")
	if segments.size() >= 5:
		return str(segments[4])
	return location_id.replace(".", "_")
