class_name RegionLocationGraphCompiler
extends RefCounted

const RegionInputScript := preload("res://scripts/systems/regions/region_input.gd")
const SemanticRoleExpanderScript := preload("res://scripts/systems/regions/semantic_role_expander.gd")
const LocationNodeExpanderScript := preload("res://scripts/systems/regions/location_node_expander.gd")
const EdgeContractGeneratorScript := preload("res://scripts/systems/regions/edge_contract_generator.gd")
const COMPILER_VERSION := "v67.4"


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


func compile_edge_contracts_result(inputs: Array, edge_profile_path: String) -> Dictionary:
	if inputs.is_empty():
		return _failure("compile_location_nodes", ["At least one RegionInput is required"], {})
	var location_node_results: Array[Dictionary] = []
	for index in range(inputs.size()):
		if not (inputs[index] is Dictionary):
			return _failure("compile_location_nodes", ["RegionInput[%d] must be an object" % index], {})
		var node_result := compile_location_nodes_result(inputs[index] as Dictionary)
		if not bool(node_result.get("success", false)):
			node_result["region_input_index"] = index
			return node_result
		location_node_results.append((node_result.get("location_node_result", {}) as Dictionary).duplicate(true))
	return compile_edge_contracts_from_location_nodes_result(location_node_results, edge_profile_path)


func compile_edge_contracts_from_location_nodes_result(location_node_results: Array, edge_profile_path: String) -> Dictionary:
	var generator: RefCounted = EdgeContractGeneratorScript.new()
	return generator.generate_edges_result(location_node_results, edge_profile_path)


func compile_to_location_graph_result(inputs: Array, edge_profile_path: String) -> Dictionary:
	var edge_result := compile_edge_contracts_result(inputs, edge_profile_path)
	if not bool(edge_result.get("success", false)):
		return edge_result
	return _failure("edge_contracts_to_location_graph_snapshot", [
		"v67.5 Location Graph Snapshot generation is not implemented; EdgeContractResult is valid, but v67.4 does not produce a Location Graph Snapshot.",
	], {
		"edge_contract_result": edge_result.get("edge_contract_result", {}),
		"location_node_results": edge_result.get("location_node_results", []),
	})


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result
