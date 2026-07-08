class_name LocationNodeResultValidator
extends RefCounted

const SCHEMA_VERSION := 1
const FORBIDDEN_NEXT_STAGE_KEYS := {
	"edge_id": true,
	"edges": true,
	"from_location_id": true,
	"to_location_id": true,
	"target_location_id": true,
	"target_region_id": true,
	"resolved_connection": true,
	"scene_path": true,
	"spawn_id": true,
	"spawns": true,
	"tilemap": true,
	"exit_id": true,
	"target_scene_path": true,
	"start_location_id": true,
	"location_graph": true,
	"external_connection_bindings": true,
	"external_connection_intents": true,
	"source_intent_id": true,
	"boundary_location_id": true,
	"intent_id": true,
	"direction_hint": true,
	"travel_type": true,
	"exit_style": true,
	"access_rule": true,
}


func validate(result: Dictionary, semantic_role_result: Dictionary = {}, profile: RefCounted = null) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("LocationNodeResult is empty")
		return errors
	_scan_for_forbidden_keys(result, "", errors)
	if result.has("locations"):
		errors.append("LocationNodeResult must use location_nodes, not locations")
	if int(result.get("schema_version", 0)) != SCHEMA_VERSION:
		errors.append("LocationNodeResult.schema_version is unsupported: %s" % str(result.get("schema_version", "")))
	if str(result.get("stage", "")) != "location_nodes":
		errors.append("LocationNodeResult.stage must be location_nodes")
	for key in ["compiler_version", "region_id", "region_type", "region_slug", "source_hash", "semantic_role_source_hash"]:
		if str(result.get(key, "")).is_empty():
			errors.append("LocationNodeResult.%s is missing" % key)
	if not result.has("seed"):
		errors.append("LocationNodeResult.seed is missing")
	if profile == null:
		errors.append("LocationNodeProfile is required")
	if not (result.get("location_nodes", null) is Array):
		errors.append("LocationNodeResult.location_nodes must be an array")
		return errors
	if not (result.get("role_node_bindings", null) is Array):
		errors.append("LocationNodeResult.role_node_bindings must be an array")
	var roles_by_id := _roles_by_id(semantic_role_result, errors)
	var nodes: Array = result.get("location_nodes", []) as Array
	var nodes_by_id := _validate_nodes(nodes, roles_by_id, profile, result, errors)
	_validate_role_node_bindings(result, roles_by_id, nodes_by_id, errors)
	return errors


func _roles_by_id(semantic_role_result: Dictionary, errors: Array[String]) -> Dictionary:
	var roles_by_id: Dictionary = {}
	if semantic_role_result.is_empty():
		errors.append("SemanticRoleResult is required to validate LocationNodeResult")
		return roles_by_id
	if str(semantic_role_result.get("stage", "")) != "semantic_roles":
		errors.append("SemanticRoleResult.stage must be semantic_roles")
	if not (semantic_role_result.get("selected_roles", null) is Array):
		errors.append("SemanticRoleResult.selected_roles must be an array")
		return roles_by_id
	for role_value in (semantic_role_result.get("selected_roles", []) as Array):
		var role: Dictionary = role_value as Dictionary
		var role_id := str(role.get("role_id", ""))
		if role_id.is_empty():
			errors.append("SemanticRoleResult contains role without role_id")
			continue
		roles_by_id[role_id] = role
	return roles_by_id


func _validate_nodes(nodes: Array, roles_by_id: Dictionary, profile: RefCounted, result: Dictionary, errors: Array[String]) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	var node_slugs: Dictionary = {}
	var node_counts_by_role: Dictionary = {}
	if nodes.is_empty():
		errors.append("LocationNodeResult.location_nodes must not be empty")
	for index in range(nodes.size()):
		if not (nodes[index] is Dictionary):
			errors.append("LocationNodeResult.location_nodes[%d] must be an object" % index)
			continue
		var node: Dictionary = nodes[index] as Dictionary
		_validate_node(index, node, roles_by_id, profile, result, nodes_by_id, node_slugs, node_counts_by_role, errors)
	for role_id_value in roles_by_id.keys():
		var role_id := str(role_id_value)
		var count := int(node_counts_by_role.get(role_id, 0))
		if count != 1:
			errors.append("LocationNodeResult must contain exactly one location node for source_role_id %s; found %d" % [role_id, count])
	return nodes_by_id


func _validate_node(index: int, node: Dictionary, roles_by_id: Dictionary, profile: RefCounted, result: Dictionary, nodes_by_id: Dictionary, node_slugs: Dictionary, node_counts_by_role: Dictionary, errors: Array[String]) -> void:
	for key in ["location_id", "location_type", "node_slug", "source_role_id", "source_role_type", "source_role_slug", "node_source", "node_tags", "is_boundary", "is_hidden", "is_required"]:
		if not node.has(key):
			errors.append("LocationNodeResult.location_nodes[%d].%s is missing" % [index, key])
	var location_id := str(node.get("location_id", ""))
	var node_slug := str(node.get("node_slug", ""))
	var source_role_id := str(node.get("source_role_id", ""))
	var source_role_type := str(node.get("source_role_type", ""))
	var source_role_slug := str(node.get("source_role_slug", ""))
	var location_type := str(node.get("location_type", ""))
	if location_id.is_empty() or not _is_location_id(location_id, str(result.get("region_type", "")), str(result.get("region_slug", "")), node_slug):
		errors.append("LocationNodeResult.location_nodes[%d].location_id is invalid: %s" % [index, location_id])
	elif nodes_by_id.has(location_id):
		errors.append("LocationNodeResult contains duplicate location_id: %s" % location_id)
	nodes_by_id[location_id] = node
	if node_slug.is_empty() or not _is_system_token(node_slug):
		errors.append("LocationNodeResult.location_nodes[%d].node_slug is invalid: %s" % [index, node_slug])
	elif node_slugs.has(node_slug):
		errors.append("LocationNodeResult contains duplicate node_slug: %s" % node_slug)
	node_slugs[node_slug] = true
	if str(node.get("node_source", "")) != "semantic_role":
		errors.append("LocationNodeResult.location_nodes[%d].node_source must be semantic_role" % index)
	if not (node.get("node_tags", null) is Array):
		errors.append("LocationNodeResult.location_nodes[%d].node_tags must be an array" % index)
	elif not _string_array_is_valid(node.get("node_tags")):
		errors.append("LocationNodeResult.location_nodes[%d].node_tags must contain lowercase system tokens" % index)
	for boolean_key in ["is_boundary", "is_hidden", "is_required"]:
		if not (node.get(boolean_key, null) is bool):
			errors.append("LocationNodeResult.location_nodes[%d].%s must be a boolean" % [index, boolean_key])
	if not roles_by_id.has(source_role_id):
		errors.append("LocationNodeResult.location_nodes[%d].source_role_id does not exist: %s" % [index, source_role_id])
		return
	node_counts_by_role[source_role_id] = int(node_counts_by_role.get(source_role_id, 0)) + 1
	var role: Dictionary = roles_by_id.get(source_role_id, {}) as Dictionary
	if source_role_type != str(role.get("role_type", "")):
		errors.append("LocationNodeResult.location_nodes[%d].source_role_type does not match role: %s" % [index, source_role_type])
	if source_role_slug != str(role.get("role_slug", "")):
		errors.append("LocationNodeResult.location_nodes[%d].source_role_slug does not match role: %s" % [index, source_role_slug])
	if source_role_slug.is_empty() and node_slug != source_role_type:
		errors.append("LocationNodeResult.location_nodes[%d].node_slug must use role_type when role_slug is missing" % index)
	elif not source_role_slug.is_empty() and node_slug != source_role_slug:
		errors.append("LocationNodeResult.location_nodes[%d].node_slug must use source_role_slug" % index)
	if profile != null:
		var rule: Dictionary = profile.role_rule(source_role_type)
		if rule.is_empty():
			errors.append("LocationNodeProfile has no location rule for role_type: %s" % source_role_type)
		elif location_type != str(rule.get("location_type", "")):
			errors.append("LocationNodeResult.location_nodes[%d].location_type does not match LocationNodeProfile rule for %s" % [index, source_role_type])
		elif not profile.supports_location_type(location_type):
			errors.append("LocationNodeResult.location_nodes[%d].location_type is unsupported: %s" % [index, location_type])
		if bool(node.get("is_boundary", false)) != bool(rule.get("boundary", false)):
			errors.append("LocationNodeResult.location_nodes[%d].is_boundary does not match LocationNodeProfile rule for %s" % [index, source_role_type])
	if bool(node.get("is_required", false)) != (str(role.get("role_source", "")) == "required"):
		errors.append("LocationNodeResult.location_nodes[%d].is_required does not match source role" % index)


func _validate_role_node_bindings(result: Dictionary, roles_by_id: Dictionary, nodes_by_id: Dictionary, errors: Array[String]) -> void:
	var bindings: Array = result.get("role_node_bindings", []) as Array
	var roles_seen: Dictionary = {}
	var nodes_seen: Dictionary = {}
	for index in range(bindings.size()):
		if not (bindings[index] is Dictionary):
			errors.append("LocationNodeResult.role_node_bindings[%d] must be an object" % index)
			continue
		var binding: Dictionary = bindings[index] as Dictionary
		var source_role_id := str(binding.get("source_role_id", ""))
		var location_id := str(binding.get("location_id", ""))
		if not roles_by_id.has(source_role_id):
			errors.append("LocationNodeResult.role_node_bindings[%d].source_role_id does not exist: %s" % [index, source_role_id])
		elif roles_seen.has(source_role_id):
			errors.append("LocationNodeResult contains duplicate role_node_binding for source_role_id: %s" % source_role_id)
		roles_seen[source_role_id] = true
		if not nodes_by_id.has(location_id):
			errors.append("LocationNodeResult.role_node_bindings[%d].location_id does not exist: %s" % [index, location_id])
		elif nodes_seen.has(location_id):
			errors.append("LocationNodeResult contains duplicate role_node_binding for location_id: %s" % location_id)
		nodes_seen[location_id] = true
		if nodes_by_id.has(location_id):
			var node: Dictionary = nodes_by_id.get(location_id, {}) as Dictionary
			if str(node.get("source_role_id", "")) != source_role_id:
				errors.append("LocationNodeResult.role_node_bindings[%d] does not match node.source_role_id" % index)
	for role_id_value in roles_by_id.keys():
		var role_id := str(role_id_value)
		if not roles_seen.has(role_id):
			errors.append("LocationNodeResult is missing role_node_binding for source_role_id: %s" % role_id)


func _scan_for_forbidden_keys(value: Variant, path: String, errors: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for key_value in dictionary.keys():
			var key := str(key_value)
			var next_path := key if path.is_empty() else "%s.%s" % [path, key]
			if bool(FORBIDDEN_NEXT_STAGE_KEYS.get(key, false)):
				errors.append("LocationNodeResult must not contain v67.4 edge/scene/runtime field: %s" % next_path)
			_scan_for_forbidden_keys(dictionary.get(key_value), next_path, errors)
	elif value is Array:
		var values: Array = value as Array
		for index in range(values.size()):
			_scan_for_forbidden_keys(values[index], "%s[%d]" % [path, index], errors)


static func _is_location_id(value: String, region_type: String, region_slug: String, node_slug: String) -> bool:
	var segments := value.split(".")
	if segments.size() != 6:
		return false
	if str(segments[0]) != "loc":
		return false
	if not _is_system_token(str(segments[1])):
		return false
	if str(segments[2]) != region_type or not _is_system_token(str(segments[2])) or not str(segments[2]).ends_with("_region"):
		return false
	if str(segments[3]) != region_slug or not _is_system_token(str(segments[3])):
		return false
	if str(segments[4]) != node_slug or not _is_system_token(str(segments[4])):
		return false
	var code := str(segments[5])
	if not code.begins_with("ln_"):
		return false
	return code.substr(3).is_valid_int()


static func _string_array_is_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	for item in (value as Array):
		var text := str(item)
		if text.is_empty() or not _is_system_token(text):
			return false
	return true


static func _is_system_token(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		if not is_digit and not is_lower and code != 95:
			return false
	return true
