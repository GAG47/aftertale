class_name EdgeContractGenerator
extends RefCounted

const COMPILER_VERSION := "v67.4"


func generate_edges_result(location_node_result: Dictionary, _profile: RefCounted = null) -> Dictionary:
	var errors := _validate_location_result_shape(location_node_result)
	if not errors.is_empty():
		return _failure("validate_location_node_result", errors, {})
	return _failure("location_nodes_to_edge_contracts", [
		"v67.4 edge contract generation is not implemented; LocationNodeResult is valid, but v67.3 cannot produce a Location Graph.",
	], {
		"location_node_result": location_node_result,
	})


func _validate_location_result_shape(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if result.is_empty():
		errors.append("LocationNodeResult is empty")
	if str(result.get("stage", "")) != "location_nodes":
		errors.append("LocationNodeResult.stage must be location_nodes")
	if not (result.get("location_nodes", null) is Array):
		errors.append("LocationNodeResult.location_nodes must be an array")
	return errors


func _failure(stage: String, errors: Array[String], extra: Dictionary) -> Dictionary:
	var result := extra.duplicate(true)
	result["success"] = false
	result["stage"] = stage
	result["errors"] = errors.duplicate()
	result["warnings"] = []
	result["compiler_version"] = COMPILER_VERSION
	return result
