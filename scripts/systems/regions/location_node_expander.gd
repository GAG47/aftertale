class_name LocationNodeExpander
extends RefCounted

const LocationNodeProfileScript := preload("res://scripts/systems/regions/location_node_profile.gd")
const LocationNodeResultValidatorScript := preload("res://scripts/systems/regions/location_node_result_validator.gd")
const SemanticRoleResultValidatorScript := preload("res://scripts/systems/regions/semantic_role_result_validator.gd")
const CanonicalDataSerializerScript := preload("res://scripts/systems/regions/canonical_data_serializer.gd")

const SCHEMA_VERSION := 1
const COMPILER_VERSION := "v67.3"


func expand_locations_result(semantic_role_result: Dictionary) -> Dictionary:
	var semantic_validator: RefCounted = SemanticRoleResultValidatorScript.new()
	var role_errors: Array[String] = semantic_validator.validate(semantic_role_result)
	if not role_errors.is_empty():
		return _failure("validate_semantic_role_result", role_errors, {
			"semantic_role_result": semantic_role_result,
		})

	var profile_loader: RefCounted = LocationNodeProfileScript.new()
	var profile_result: Dictionary = profile_loader.load_profile_result(str(semantic_role_result.get("region_type", "")))
	if not bool(profile_result.get("success", false)):
		return _failure("load_location_node_profile", profile_result.get("errors", []) as Array[String], {
			"semantic_role_result": semantic_role_result,
		})
	var profile: RefCounted = profile_result.get("profile") as RefCounted

	var generation_result := _generate_location_nodes(semantic_role_result, profile)
	if not bool(generation_result.get("success", false)):
		return _failure("expand_location_nodes", generation_result.get("errors", []) as Array[String], {
			"semantic_role_result": semantic_role_result,
			"profile_path": str(profile_result.get("profile_path", "")),
		})

	var location_nodes: Array = generation_result.get("location_nodes", []) as Array
	var role_node_bindings: Array = generation_result.get("role_node_bindings", []) as Array
	var result := {
		"schema_version": SCHEMA_VERSION,
		"compiler_version": COMPILER_VERSION,
		"stage": "location_nodes",
		"region_id": str(semantic_role_result.get("region_id", "")),
		"region_type": str(semantic_role_result.get("region_type", "")),
		"region_slug": str(semantic_role_result.get("region_slug", "")),
		"seed": int(semantic_role_result.get("seed", 0)),
		"source_hash": str(semantic_role_result.get("source_hash", "")),
		"semantic_role_source_hash": _source_hash(semantic_role_result),
		"profile_path": str(profile_result.get("profile_path", "")),
		"semantic_role_profile_path": str(semantic_role_result.get("profile_path", "")),
		"location_nodes": location_nodes,
		"role_node_bindings": role_node_bindings,
		"debug_summary": _debug_summary(location_nodes),
	}
	result["result_hash"] = CanonicalDataSerializerScript.location_node_result_hash(result)
	if str(result.get("result_hash", "")).is_empty():
		return _failure("hash_location_node_result", ["LocationNodeResult could not be canonically hashed"], {
			"semantic_role_result": semantic_role_result,
			"location_node_result": result,
		})
	var validator: RefCounted = LocationNodeResultValidatorScript.new()
	var validation_errors: Array[String] = validator.validate(result, semantic_role_result, profile)
	if not validation_errors.is_empty():
		return _failure("validate_location_node_result", validation_errors, {
			"semantic_role_result": semantic_role_result,
			"location_node_result": result,
			"profile_path": str(profile_result.get("profile_path", "")),
		})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"location_node_result": result,
		"profile": profile,
	}


func _generate_location_nodes(semantic_role_result: Dictionary, profile: RefCounted) -> Dictionary:
	var location_nodes: Array[Dictionary] = []
	var role_node_bindings: Array[Dictionary] = []
	var selected_roles: Array = semantic_role_result.get("selected_roles", []) as Array
	for index in range(selected_roles.size()):
		var role: Dictionary = selected_roles[index] as Dictionary
		var role_type := str(role.get("role_type", ""))
		var rule: Dictionary = profile.role_rule(role_type)
		if rule.is_empty():
			return _failure("expand_location_nodes", ["LocationNodeProfile has no location rule for role_type: %s" % role_type], {})
		if int(rule.get("count", 0)) != 1:
			return _failure("expand_location_nodes", ["LocationNodeProfile role rule count must be exactly 1 in v67.3: %s" % role_type], {})
		var node := _location_from_role(role, semantic_role_result, profile, index)
		location_nodes.append(node)
		role_node_bindings.append({
			"source_role_id": str(role.get("role_id", "")),
			"location_id": str(node.get("location_id", "")),
		})
	return {
		"success": true,
		"errors": [],
		"location_nodes": location_nodes,
		"role_node_bindings": role_node_bindings,
	}


func _location_from_role(role: Dictionary, semantic_role_result: Dictionary, profile: RefCounted, index: int) -> Dictionary:
	var role_type := str(role.get("role_type", ""))
	var node_slug := _node_slug_for_role(role)
	var node := {
		"location_id": _location_id_for_node(semantic_role_result, node_slug, index),
		"location_type": profile.location_type_for_role(role_type),
		"node_slug": node_slug,
		"source_role_id": str(role.get("role_id", "")),
		"source_role_type": role_type,
		"source_role_slug": str(role.get("role_slug", "")),
		"node_source": "semantic_role",
		"node_tags": profile.node_tags_for_role(role_type),
		"is_boundary": profile.is_boundary_role(role_type),
		"is_hidden": profile.is_hidden_role(role_type),
		"is_required": str(role.get("role_source", "")) == "required",
	}
	return node


func _node_slug_for_role(role: Dictionary) -> String:
	var role_slug := str(role.get("role_slug", ""))
	if not role_slug.is_empty():
		return role_slug
	return str(role.get("role_type", ""))


func _location_id_for_node(result: Dictionary, node_slug: String, index: int) -> String:
	var region_id := str(result.get("region_id", ""))
	var segments := region_id.split(".")
	return "loc.%s.%s.%s.%s.ln_%04d" % [
		str(segments[1]),
		str(result.get("region_type", "")),
		str(result.get("region_slug", "")),
		node_slug,
		index + 1,
	]


func _debug_summary(location_nodes: Array) -> Dictionary:
	var counts: Dictionary = {}
	for location_value in location_nodes:
		var location: Dictionary = location_value as Dictionary
		var location_type := str(location.get("location_type", ""))
		counts[location_type] = int(counts.get(location_type, 0)) + 1
	return {
		"location_node_count": location_nodes.size(),
		"location_type_counts": counts,
	}


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result


static func _source_hash(data: Dictionary) -> String:
	return "sh_%d" % _stable_text_hash(_canonical_value(data))


static func _stable_text_hash(text: String) -> int:
	var value := 2166136261
	for index in range(text.length()):
		value = int((value ^ text.unicode_at(index)) * 16777619) % 2147483647
	return abs(value)


static func _canonical_value(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for key_value in dictionary.keys():
			keys.append(str(key_value))
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [JSON.stringify(key), _canonical_value(dictionary.get(key))])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in (value as Array):
			parts.append(_canonical_value(item))
		return "[%s]" % ",".join(parts)
	return JSON.stringify(value)
