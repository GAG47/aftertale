class_name RegionLocationGraphCompiler
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const SemanticRoleExpanderScript := preload("res://scripts/systems/regions/semantic_role_expander.gd")
const LocationNodeExpanderScript := preload("res://scripts/systems/regions/location_node_expander.gd")
const COMPILER_VERSION := "v67.3"


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


func compile_location_nodes_result(input: Dictionary) -> Dictionary:
	var role_result := compile_semantic_roles_result(input)
	if not bool(role_result.get("success", false)):
		return role_result
	var node_expander: RefCounted = LocationNodeExpanderScript.new()
	return node_expander.expand_locations_result(role_result.get("semantic_role_result", {}) as Dictionary)


func compile_to_location_graph_result(input: Dictionary) -> Dictionary:
	var node_result := compile_location_nodes_result(input)
	if not bool(node_result.get("success", false)):
		return node_result
	return _failure("location_nodes_to_edge_contracts", [
		"v67.4 edge contract generation is not implemented; LocationNodeResult is valid, but v67.3 cannot produce a Location Graph.",
	], {
		"location_node_result": node_result.get("location_node_result", {}),
	})


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result
