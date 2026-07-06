class_name RegionLocationGraphCompiler
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const SemanticRoleExpanderScript := preload("res://scripts/systems/regions/semantic_role_expander.gd")
const COMPILER_VERSION := "v67.2"


func validate_region_input_result(input: Dictionary) -> Dictionary:
	var region_input: RefCounted = RegionInputScript.new()
	var errors: Array[String] = region_input.configure(input)
	if not errors.is_empty():
		return _failure("validate_region_input", errors, {})
	return {
		"success": true,
		"errors": [],
		"warnings": [],
		"region_input": region_input.to_dictionary(),
		"compiler_version": COMPILER_VERSION,
	}


func compile_semantic_roles_result(input: Dictionary) -> Dictionary:
	var expander: RefCounted = SemanticRoleExpanderScript.new()
	return expander.expand_roles_result(input)


func compile_to_location_graph_result(input: Dictionary) -> Dictionary:
	var role_result := compile_semantic_roles_result(input)
	if not bool(role_result.get("success", false)):
		return role_result
	return _failure("semantic_roles_to_location_nodes", [
		"v67.3 role-to-location-node expansion is not implemented; SemanticRoleResult is valid, but v67.2 cannot produce a Location Graph.",
	], {
		"semantic_role_result": role_result.get("semantic_role_result", {}),
	})


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result
